import type {
  AwardJson,
  AwardKey,
  AwardWinnerJson,
  Env,
  GroupRow,
  MonthlyAwardRow,
  PublicUser,
  TrophyJson,
  WeekRow,
} from '../types';
import { toPublicUser } from '../types';
import { all, first } from '../lib/db';
import { randomId } from '../lib/crypto';
import {
  CEREMONY_ORDER,
  PLAYER_OF_THE_MONTH_BONUS,
  awardOrder,
  computeMonthlyAwards,
  playerOfTheMonthStats,
  type AwardMetricInput,
  type MonthlyAward,
} from '../business/awards';
import { isMonthlyAwardsWindow, monthLabel, monthRange, previousMonthKey } from '../business/time';
import { rankTotals } from '../business/receipt';
import { pushAwardsLive } from '../push';

/**
 * Monthly awards: aggregation, idempotent storage and read models.
 *
 * Stored rows are one per winner (ties => several rows). `point_events` also
 * gets a +50 `monthly_award` row for each Player of the Month winner, attributed
 * to the month's last week. The run guard, award rows and ledger rows are
 * written in one D1 batch keyed by `monthly_award_runs(group_id, month)`, so
 * repeated hourly ticks cannot double-award or re-push.
 */

interface MemberRow {
  id: string;
  display_name: string;
  avatar_emoji: string | null;
  joined_at: number;
}

interface MonthContext {
  month: string;
  input: AwardMetricInput;
  monthWeeks: WeekRow[];
  members: MemberRow[];
}

export interface MonthlyAwardRun {
  month: string;
  awards: MonthlyAward[];
  /** Award rows inserted by this call (0 when the run was already recorded). */
  created: number;
  lastWeekId: string;
  /** True only for the call that inserted the `monthly_award_runs` row. */
  newlyRan: boolean;
}

export interface MonthlyAwardsTick {
  month: string;
  /** True only when this tick inserted the one-shot run row. */
  recorded: boolean;
  /** Award rows stored by this tick. */
  awards: number;
  /** True only when the Awards-night push was actually attempted. */
  pushed: boolean;
}

function memberUser(row: MemberRow): PublicUser {
  return toPublicUser({
    id: row.id,
    apple_sub: '',
    display_name: row.display_name,
    avatar_emoji: row.avatar_emoji,
    created_at: 0,
  });
}

async function buildMonthContext(
  db: D1Database,
  group: GroupRow,
  month: string,
): Promise<MonthContext | null> {
  const range = monthRange(month, group.timezone);

  const [allWeeks, members, acceptedRows, rejectedRows, rejectionRows, firstBonusRows, pointRows] =
    await Promise.all([
      all<WeekRow>(
        db
          .prepare('SELECT * FROM weeks WHERE group_id = ? ORDER BY starts_at ASC')
          .bind(group.id),
      ),
      all<MemberRow>(
        db
          .prepare(
            `SELECT u.id, u.display_name, u.avatar_emoji, gm.joined_at
               FROM group_members gm
               JOIN users u ON u.id = gm.user_id
              WHERE gm.group_id = ?
              ORDER BY gm.joined_at ASC, u.id ASC`,
          )
          .bind(group.id),
      ),
      all<{ user_id: string; count: number }>(
        db
          .prepare(
            `SELECT s.user_id, COUNT(*) AS count
               FROM submissions s
               JOIN challenges c ON c.id = s.challenge_id
               JOIN weeks w ON w.id = c.week_id
              WHERE w.group_id = ? AND w.starts_at >= ? AND w.starts_at < ?
                AND s.status = 'accepted'
              GROUP BY s.user_id`,
          )
          .bind(group.id, range.start, range.end),
      ),
      all<{ user_id: string; count: number }>(
        db
          .prepare(
            `SELECT s.user_id, COUNT(*) AS count
               FROM submissions s
               JOIN challenges c ON c.id = s.challenge_id
               JOIN weeks w ON w.id = c.week_id
              WHERE w.group_id = ? AND w.starts_at >= ? AND w.starts_at < ?
                AND s.status = 'rejected'
              GROUP BY s.user_id`,
          )
          .bind(group.id, range.start, range.end),
      ),
      all<{ user_id: string; count: number }>(
        db
          .prepare(
            `SELECT v.voter_id AS user_id, COUNT(*) AS count
               FROM votes v
               JOIN submissions s ON s.id = v.submission_id
               JOIN challenges c ON c.id = s.challenge_id
               JOIN weeks w ON w.id = c.week_id
              WHERE w.group_id = ? AND w.starts_at >= ? AND w.starts_at < ?
                AND v.approve = 0
              GROUP BY v.voter_id`,
          )
          .bind(group.id, range.start, range.end),
      ),
      all<{ user_id: string; count: number }>(
        db
          .prepare(
            `SELECT pe.user_id, COUNT(*) AS count
               FROM point_events pe
               JOIN weeks w ON w.id = pe.week_id
              WHERE pe.group_id = ? AND pe.kind = 'first_bonus'
                AND w.starts_at >= ? AND w.starts_at < ?
              GROUP BY pe.user_id`,
          )
          .bind(group.id, range.start, range.end),
      ),
      all<{ week_id: string; user_id: string; kind: string; points: number }>(
        db
          .prepare(
            `SELECT week_id, user_id, kind, SUM(points) AS points
               FROM point_events
              WHERE group_id = ?
              GROUP BY week_id, user_id, kind`,
          )
          .bind(group.id),
      ),
    ]);

  // Every week that *starts* in the month belongs to it, including the last
  // one (e.g. Mon Oct 27 -> Sun Nov 2) whose vote deadline is on the following
  // Monday. The caller decides whether they are all ready to be awarded.
  const monthWeeks = allWeeks.filter(
    (week) => week.starts_at >= range.start && week.starts_at < range.end,
  );
  if (monthWeeks.length === 0) return null;

  const memberIds = members.map((row) => row.id);
  const memberSet = new Set(memberIds);
  const weekStartById = new Map(allWeeks.map((week) => [week.id, week.starts_at]));

  const points = new Map<string, number>();
  const pointsByWeek = new Map<string, Map<string, number>>();
  const totalsAtStart = new Map<string, number>(memberIds.map((id) => [id, 0]));
  const totalsAtEnd = new Map<string, number>(memberIds.map((id) => [id, 0]));

  for (const row of pointRows) {
    if (!memberSet.has(row.user_id)) continue;
    const startsAt = weekStartById.get(row.week_id);
    if (startsAt === undefined) continue;

    if (startsAt < range.start) {
      totalsAtStart.set(row.user_id, (totalsAtStart.get(row.user_id) ?? 0) + row.points);
      totalsAtEnd.set(row.user_id, (totalsAtEnd.get(row.user_id) ?? 0) + row.points);
      continue;
    }
    if (startsAt >= range.end) continue;

    // Exclude this month's own monthly_award bonus so re-running the
    // computation after storing it produces identical winners.
    if (row.kind === 'monthly_award') continue;
    points.set(row.user_id, (points.get(row.user_id) ?? 0) + row.points);
    const byWeek = pointsByWeek.get(row.user_id) ?? new Map<string, number>();
    byWeek.set(row.week_id, (byWeek.get(row.week_id) ?? 0) + row.points);
    pointsByWeek.set(row.user_id, byWeek);
    totalsAtEnd.set(row.user_id, (totalsAtEnd.get(row.user_id) ?? 0) + row.points);
  }

  const rankAtStart = ranksFromTotals(totalsAtStart);
  const rankAtEnd = ranksFromTotals(totalsAtEnd);

  const toMetricMap = (rows: ReadonlyArray<{ user_id: string; count: number }>) => {
    const map = new Map<string, number>();
    for (const row of rows) {
      if (memberSet.has(row.user_id)) map.set(row.user_id, row.count);
    }
    return map;
  };

  const presentAllMonth = new Set(
    members.filter((row) => row.joined_at <= range.start).map((row) => row.id),
  );

  const input: AwardMetricInput = {
    month,
    memberIds,
    presentAllMonth,
    points,
    acceptedSubmissions: toMetricMap(acceptedRows),
    rejectedSubmissions: toMetricMap(rejectedRows),
    rejectionVotes: toMetricMap(rejectionRows),
    firstBonuses: toMetricMap(firstBonusRows),
    pointsByWeek,
    rankAtStart,
    rankAtEnd,
  };

  return { month, input, monthWeeks, members };
}

function ranksFromTotals(totals: ReadonlyMap<string, number>): Map<string, number> {
  return new Map(
    [...rankTotals(totals).entries()].map(([userId, snapshot]) => [userId, snapshot.rank]),
  );
}

/**
 * Computes + stores one month's awards.
 *
 * Returns null when the month has no weeks at all, or when at least one of its
 * weeks is still open / inside its vote deadline. The caller retries on the
 * next hourly tick: by the first Monday 19:00 the last week starting in the
 * previous month is always closed and past its 12:00 deadline.
 *
 * One-shot: every write is in a single D1 batch whose first statement inserts
 * the `monthly_award_runs(group_id, month)` guard. A repeated call is a no-op,
 * even if the data has since changed enough to compute different winners.
 */
export async function runMonthlyAwards(
  env: Env,
  group: GroupRow,
  month: string,
  now: number,
): Promise<MonthlyAwardRun | null> {
  const context = await buildMonthContext(env.DB, group, month);
  if (!context) return null;

  // Include the whole month, including the week that spills into next month.
  // If any of its weeks is not closed or still inside the vote grace, do
  // nothing this hour and let the next cron tick retry.
  const ready = context.monthWeeks.every(
    (week) => week.status === 'closed' && week.vote_deadline <= now,
  );
  if (!ready) return null;

  const lastWeekId = context.monthWeeks.at(-1)!.id;
  const awards = computeMonthlyAwards(context.input);

  // Fast path: a previous tick already recorded this month. Read-only.
  const existing = await first<{ ran_at: number }>(
    env.DB.prepare(
      'SELECT ran_at FROM monthly_award_runs WHERE group_id = ? AND month = ?',
    ).bind(group.id, month),
  );
  if (existing) {
    return { month, awards, created: 0, lastWeekId, newlyRan: false };
  }

  // The guard insert is deliberately not OR IGNORE: a concurrent tick that
  // gets there first makes this statement fail and D1 rolls the whole batch
  // back, so only one caller can ever write the awards below.
  const runStatement = env.DB.prepare(
    'INSERT INTO monthly_award_runs (group_id, month, ran_at) VALUES (?, ?, ?)',
  ).bind(group.id, month, now);

  const awardStatements = awards.flatMap((award) =>
    award.winners.map((winner) =>
      env.DB.prepare(
        `INSERT OR IGNORE INTO monthly_awards
           (id, group_id, month, award, user_id, value, created_at)
         VALUES (?, ?, ?, ?, ?, ?, ?)`,
      ).bind(
        randomId(),
        group.id,
        month,
        award.award,
        winner.userId,
        winner.value,
        now,
      ),
    ),
  );

  const pointStatements: D1PreparedStatement[] = [];
  const playerAward = awards.find((award) => award.award === 'player_of_the_month');
  if (playerAward) {
    for (const winner of playerAward.winners) {
      // Idempotent through idx_point_events_idempotent (submission_id is NULL).
      pointStatements.push(
        env.DB.prepare(
          `INSERT OR IGNORE INTO point_events
             (id, group_id, week_id, user_id, kind, points, submission_id, created_at)
           VALUES (?, ?, ?, ?, 'monthly_award', ?, NULL, ?)`,
        ).bind(
          randomId(),
          group.id,
          lastWeekId,
          winner.userId,
          PLAYER_OF_THE_MONTH_BONUS,
          now,
        ),
      );
    }
  }

  let results: D1Result[];
  try {
    results = await env.DB.batch([runStatement, ...awardStatements, ...pointStatements]);
  } catch (error) {
    // A concurrent isolate inserted the guard first: the batch rolled back.
    const raced = await first<{ ran_at: number }>(
      env.DB.prepare(
        'SELECT ran_at FROM monthly_award_runs WHERE group_id = ? AND month = ?',
      ).bind(group.id, month),
    );
    if (raced) {
      return { month, awards, created: 0, lastWeekId, newlyRan: false };
    }
    throw error;
  }

  const created = results
    .slice(1, 1 + awardStatements.length)
    .reduce((sum, result) => sum + (result.meta.changes ?? 0), 0);

  return { month, awards, created, lastWeekId, newlyRan: true };
}

/** Cron glue: first Monday of the month at/after 19:00 local, previous month. */
export async function maybeRunMonthlyAwards(
  env: Env,
  group: GroupRow,
  now: number,
): Promise<MonthlyAwardsTick | null> {
  if (!isMonthlyAwardsWindow(now, group.timezone)) return null;

  const month = previousMonthKey(now, group.timezone);
  const run = await runMonthlyAwards(env, group, month, now);
  if (!run) return { month, recorded: false, awards: 0, pushed: false };

  let pushed = false;
  if (run.newlyRan && run.awards.length > 0) {
    try {
      await pushAwardsLive(env, group.id, monthLabel(month));
      pushed = true;
    } catch (error) {
      // Push is best effort; the awards are already stored.
      console.log('push_failed', { reason: error instanceof Error ? error.name : 'unknown' });
    }
  }

  return { month, recorded: run.newlyRan, awards: run.created, pushed };
}

export async function latestAwardMonth(db: D1Database, groupId: string): Promise<string | null> {
  const row = await first<{ month: string }>(
    db
      .prepare(
        'SELECT month FROM monthly_awards WHERE group_id = ? ORDER BY month DESC LIMIT 1',
      )
      .bind(groupId),
  );
  return row?.month ?? null;
}

export async function listAwardMonths(db: D1Database, groupId: string): Promise<string[]> {
  const rows = await all<{ month: string }>(
    db
      .prepare(
        `SELECT DISTINCT month FROM monthly_awards
          WHERE group_id = ?
          ORDER BY month DESC`,
      )
      .bind(groupId),
  );
  return rows.map((row) => row.month);
}

interface AwardRowWithUser extends MonthlyAwardRow {
  display_name: string;
  avatar_emoji: string | null;
}

/** GET /groups/:id/awards?month=YYYY-MM (default latest stored month). */
export async function groupAwards(
  db: D1Database,
  group: GroupRow,
  requestedMonth?: string,
): Promise<{ month: string | null; awards: AwardJson[] }> {
  const month = requestedMonth ?? (await latestAwardMonth(db, group.id));
  if (!month) return { month: null, awards: [] };

  const rows = await all<AwardRowWithUser>(
    db
      .prepare(
        `SELECT ma.*, u.display_name, u.avatar_emoji
           FROM monthly_awards ma
           JOIN users u ON u.id = ma.user_id
          WHERE ma.group_id = ? AND ma.month = ?
          ORDER BY ma.award ASC, u.id ASC`,
      )
      .bind(group.id, month),
  );
  if (rows.length === 0) return { month, awards: [] };

  const context = await buildMonthContext(db, group, month);
  const computed = context
    ? new Map(computeMonthlyAwards(context.input).map((award) => [award.award, award]))
    : new Map<AwardKey, MonthlyAward>();
  const userById = new Map((context?.members ?? []).map((member) => [member.id, memberUser(member)]));

  const byAward = new Map<AwardKey, AwardRowWithUser[]>();
  for (const row of rows) {
    const list = byAward.get(row.award);
    if (list) list.push(row);
    else byAward.set(row.award, [row]);
  }

  const awards: AwardJson[] = [];
  for (const award of CEREMONY_ORDER) {
    const awardRows = byAward.get(award);
    if (!awardRows || awardRows.length === 0) continue;

    const winners: PublicUser[] = awardRows.map((row) =>
      toPublicUser({
        id: row.user_id,
        apple_sub: '',
        display_name: row.display_name,
        avatar_emoji: row.avatar_emoji,
        created_at: 0,
      }),
    );

    let nominees: AwardWinnerJson[] = (computed.get(award)?.nominees ?? [])
      .map((nominee) => {
        const user = userById.get(nominee.userId);
        return user ? { user, value: nominee.value } : null;
      })
      .filter((entry): entry is AwardWinnerJson => entry !== null);

    if (nominees.length === 0) {
      nominees = winners.map((user, index) => ({ user, value: awardRows[index]!.value }));
    }

    // Only the Player of the Month pennant carries the winner's month stats.
    const stats =
      award === 'player_of_the_month' && context
        ? playerOfTheMonthStats(context.input, awardRows[0]!.user_id)
        : undefined;

    awards.push({
      award,
      winners,
      value: awardRows[0]!.value,
      nominees,
      ...(stats === undefined ? {} : { stats }),
    });
  }

  // Defensive: preserve ceremony order even if a new/award enum row sneaks in.
  awards.sort((a, b) => awardOrder(a.award) - awardOrder(b.award));
  return { month, awards };
}

/** GET /me/trophies — the whole cabinet, across groups. */
export async function userTrophies(db: D1Database, userId: string): Promise<TrophyJson[]> {
  const rows = await all<{
    group_id: string;
    group_name: string;
    month: string;
    award: AwardKey;
    value: number;
  }>(
    db
      .prepare(
        `SELECT ma.group_id, g.name AS group_name, ma.month, ma.award, ma.value
           FROM monthly_awards ma
           JOIN groups g ON g.id = ma.group_id
          WHERE ma.user_id = ?
          ORDER BY ma.month DESC, ma.created_at DESC, ma.award ASC`,
      )
      .bind(userId),
  );

  return rows.map((row) => ({
    groupId: row.group_id,
    groupName: row.group_name,
    month: row.month,
    award: row.award,
    value: row.value,
  }));
}
