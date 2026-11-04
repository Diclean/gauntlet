import type {
  ChallengeRow,
  ChallengeWithMyStatusJson,
  Env,
  GroupRow,
  LeaderboardEntryJson,
  MyChallengeStatus,
  WeekRow,
} from '../types';
import { toPublicUser } from '../types';
import { all, first } from '../lib/db';
import { randomId } from '../lib/crypto';
import { notFound } from '../lib/errors';
import {
  FIRST_FINISH_BONUS,
  WEEKLY_WINNER_BONUS,
  computeStreaks,
  firstAcceptedSubmission,
  pointsForDifficulty,
  rankByPoints,
  streakBonus,
  weeklyWinnerIds,
  type AcceptedSubmissionRef,
  type WeekRef,
} from '../business/points';
import { startOfLocalWeek, weekBoundsFromStart } from '../business/time';
import { generateChallenges } from '../deepseek';
import { weekJson } from './groups';

/** Week creation/generation, finalization and leaderboard aggregation. */

export async function getWeekByStart(
  db: D1Database,
  groupId: string,
  startsAt: number,
): Promise<WeekRow | null> {
  return await first<WeekRow>(
    db
      .prepare('SELECT * FROM weeks WHERE group_id = ? AND starts_at = ?')
      .bind(groupId, startsAt),
  );
}

export async function getLatestWeek(db: D1Database, groupId: string): Promise<WeekRow | null> {
  return await first<WeekRow>(
    db
      .prepare('SELECT * FROM weeks WHERE group_id = ? ORDER BY starts_at DESC LIMIT 1')
      .bind(groupId),
  );
}

export async function getWeekById(db: D1Database, weekId: string): Promise<WeekRow | null> {
  return await first<WeekRow>(db.prepare('SELECT * FROM weeks WHERE id = ?').bind(weekId));
}

export async function getChallengesForWeek(
  db: D1Database,
  weekId: string,
): Promise<ChallengeRow[]> {
  return await all<ChallengeRow>(
    db.prepare('SELECT * FROM challenges WHERE week_id = ? ORDER BY position ASC').bind(weekId),
  );
}

export interface ChallengeStatusRow extends ChallengeRow {
  accepted_count: number;
  my_status: string | null;
}

export async function challengesWithMyStatus(
  db: D1Database,
  weekId: string,
  userId: string,
): Promise<ChallengeWithMyStatusJson[]> {
  const rows = await all<ChallengeStatusRow>(
    db
      .prepare(
        `SELECT c.*,
                (SELECT COUNT(*) FROM submissions s
                  WHERE s.challenge_id = c.id AND s.status = 'accepted') AS accepted_count,
                (SELECT s.status FROM submissions s
                  WHERE s.challenge_id = c.id AND s.user_id = ?
                  ORDER BY s.created_at DESC, s.id DESC LIMIT 1) AS my_status
           FROM challenges c
          WHERE c.week_id = ?
          ORDER BY c.position ASC, c.id ASC`,
      )
      .bind(userId, weekId),
  );

  return rows.map((row) => {
    let myStatus: MyChallengeStatus = 'todo';
    if (row.my_status === 'accepted') myStatus = 'accepted';
    else if (row.my_status === 'pending') myStatus = 'pending';
    else if (row.my_status === 'rejected' || row.my_status === 'expired') myStatus = 'rejected';
    return {
      id: row.id,
      title: row.title,
      description: row.description,
      difficulty: row.difficulty,
      points: row.points,
      position: row.position,
      myStatus,
      acceptedCount: row.accepted_count,
    };
  });
}

/** Titles from the previous three weeks (for the DeepSeek no-repeat prompt). */
export async function previousChallengeTitles(
  db: D1Database,
  groupId: string,
  beforeStartsAt: number,
): Promise<string[]> {
  const rows = await all<{ week_id: string; title: string }>(
    db
      .prepare(
        `SELECT w.id AS week_id, c.title AS title
           FROM challenges c
           JOIN weeks w ON w.id = c.week_id
          WHERE w.group_id = ? AND w.starts_at < ?
          ORDER BY w.starts_at DESC, c.position ASC
          LIMIT 120`,
      )
      .bind(groupId, beforeStartsAt),
  );

  const titles: string[] = [];
  const weekIds = new Set<string>();
  for (const row of rows) {
    if (!weekIds.has(row.week_id)) {
      if (weekIds.size >= 3) break;
      weekIds.add(row.week_id);
    }
    titles.push(row.title);
  }
  return titles;
}

export interface CreatedWeek {
  week: WeekRow;
  created: boolean;
  challenges: ChallengeRow[];
}

/**
 * Inserts the week (idempotent through UNIQUE(group_id, starts_at)) and, only
 * when it was actually inserted, generates its challenges. A duplicate insert
 * returns the existing week untouched.
 */
export async function createWeekAndChallenges(
  env: Env,
  group: GroupRow,
  startsAt: number,
): Promise<CreatedWeek> {
  const bounds = weekBoundsFromStart(startsAt, group.timezone);
  const weekId = randomId();

  const insert = await env.DB.prepare(
    `INSERT INTO weeks (id, group_id, starts_at, ends_at, vote_deadline, status, reminder_sent)
     VALUES (?, ?, ?, ?, ?, 'open', 0)
     ON CONFLICT(group_id, starts_at) DO NOTHING`,
  )
    .bind(weekId, group.id, bounds.startsAt, bounds.endsAt, bounds.voteDeadline)
    .run();

  if ((insert.meta.changes ?? 0) === 0) {
    const existing = await getWeekByStart(env.DB, group.id, startsAt);
    if (!existing) throw new Error('week_insert_conflict_without_row');
    let challenges = await getChallengesForWeek(env.DB, existing.id);
    if (challenges.length === 0) {
      // A previous tick inserted the week but crashed before generating its
      // challenges. Remove the empty week and retry; the NOT EXISTS guard means
      // we never delete a week another request just populated.
      const removed = await env.DB.prepare(
        `DELETE FROM weeks
          WHERE id = ? AND NOT EXISTS (SELECT 1 FROM challenges WHERE week_id = ?)`,
      )
        .bind(existing.id, existing.id)
        .run();
      if ((removed.meta.changes ?? 0) > 0) return await createWeekAndChallenges(env, group, startsAt);

      const refreshed = await getWeekByStart(env.DB, group.id, startsAt);
      if (!refreshed) throw new Error('week_disappeared_during_generation');
      challenges = await getChallengesForWeek(env.DB, refreshed.id);
      return { week: refreshed, created: false, challenges };
    }
    return { week: existing, created: false, challenges };
  }

  const previousTitles = await previousChallengeTitles(env.DB, group.id, startsAt);
  const generated = await generateChallenges({
    env,
    count: group.challenges_per_week,
    theme: group.theme,
    language: group.language,
    timezone: group.timezone,
    previousTitles,
  });

  const challenges: ChallengeRow[] = generated.challenges.slice(0, group.challenges_per_week).map(
    (draft, index) => ({
      id: randomId(),
      week_id: weekId,
      title: draft.title,
      description: draft.description,
      difficulty: draft.difficulty,
      points: pointsForDifficulty(draft.difficulty),
      position: index,
    }),
  );

  if (challenges.length === 0) {
    // Should be impossible (fallback always returns N); keep the week usable.
    throw new Error('challenge_generation_empty');
  }

  await env.DB.batch(
    challenges.map((challenge) =>
      env.DB.prepare(
        `INSERT INTO challenges (id, week_id, title, description, difficulty, points, position)
         VALUES (?, ?, ?, ?, ?, ?, ?)`,
      ).bind(
        challenge.id,
        challenge.week_id,
        challenge.title,
        challenge.description,
        challenge.difficulty,
        challenge.points,
        challenge.position,
      ),
    ),
  );

  return {
    week: {
      id: weekId,
      group_id: group.id,
      starts_at: bounds.startsAt,
      ends_at: bounds.endsAt,
      vote_deadline: bounds.voteDeadline,
      status: 'open',
      reminder_sent: 0,
    },
    created: true,
    challenges,
  };
}

/** Creates the current local week if it is missing. */
export async function ensureCurrentWeek(env: Env, group: GroupRow, now: number): Promise<CreatedWeek> {
  const startsAt = startOfLocalWeek(now, group.timezone);
  const existing = await getWeekByStart(env.DB, group.id, startsAt);
  if (existing) {
    const challenges = await getChallengesForWeek(env.DB, existing.id);
    if (challenges.length > 0) {
      return { week: existing, created: false, challenges };
    }
    // Empty week (crash between week insert and challenge batch): let the
    // duplicate-insert recovery path remove and regenerate it.
    return await createWeekAndChallenges(env, group, startsAt);
  }
  return await createWeekAndChallenges(env, group, startsAt);
}

/** Current week for reads; creates one if this group has never had a week. */
export async function ensureReadableWeek(env: Env, group: GroupRow, now: number): Promise<WeekRow> {
  const latest = await getLatestWeek(env.DB, group.id);
  if (latest) return latest;
  const created = await ensureCurrentWeek(env, group, now);
  return created.week;
}

export async function closeOpenWeeksBefore(
  db: D1Database,
  groupId: string,
  startsAt: number,
): Promise<void> {
  await db
    .prepare(
      `UPDATE weeks SET status = 'closed'
        WHERE group_id = ? AND starts_at < ? AND status = 'open'`,
    )
    .bind(groupId, startsAt)
    .run();
}

export async function expirePendingForWeek(db: D1Database, weekId: string): Promise<void> {
  await db
    .prepare(
      `UPDATE submissions SET status = 'expired'
        WHERE status = 'pending'
          AND challenge_id IN (SELECT id FROM challenges WHERE week_id = ?)`,
    )
    .bind(weekId)
    .run();
}

/** Cron step 3: pending submissions whose week's vote deadline has passed. */
export async function expirePastDeadlineSubmissions(db: D1Database, now: number): Promise<number> {
  const result = await db
    .prepare(
      `UPDATE submissions SET status = 'expired'
        WHERE status = 'pending'
          AND challenge_id IN (
            SELECT c.id FROM challenges c
            JOIN weeks w ON w.id = c.week_id
            WHERE w.vote_deadline <= ?
          )`,
    )
    .bind(now)
    .run();
  return result.meta.changes ?? 0;
}

async function insertPointEvent(
  env: Env,
  event: {
    groupId: string;
    weekId: string;
    userId: string;
    kind: 'challenge' | 'first_bonus' | 'weekly_winner' | 'streak';
    points: number;
    submissionId: string | null;
    now: number;
  },
): Promise<void> {
  await env.DB.prepare(
    `INSERT OR IGNORE INTO point_events
       (id, group_id, week_id, user_id, kind, points, submission_id, created_at)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
  )
    .bind(
      randomId(),
      event.groupId,
      event.weekId,
      event.userId,
      event.kind,
      event.points,
      event.submissionId,
      event.now,
    )
    .run();
}

/**
 * Awards challenge points when a submission is accepted, plus the +10
 * first-to-finish bonus if this was the first accepted proof of the challenge.
 * Returns the total points awarded to this member.
 */
export async function awardAcceptedSubmission(
  env: Env,
  params: {
    groupId: string;
    weekId: string;
    submission: { id: string; user_id: string; challenge_id: string; decided_at: number | null; created_at: number };
    challengePoints: number;
    now: number;
  },
): Promise<number> {
  await insertPointEvent(env, {
    groupId: params.groupId,
    weekId: params.weekId,
    userId: params.submission.user_id,
    kind: 'challenge',
    points: params.challengePoints,
    submissionId: params.submission.id,
    now: params.now,
  });

  const acceptedRows = await all<{
    id: string;
    user_id: string;
    challenge_id: string;
    decided_at: number | null;
    created_at: number;
    points: number;
  }>(
    env.DB.prepare(
      `SELECT s.id, s.user_id, s.challenge_id, s.decided_at, s.created_at, c.points
         FROM submissions s
         JOIN challenges c ON c.id = s.challenge_id
        WHERE s.challenge_id = ? AND s.status = 'accepted'`,
    ).bind(params.submission.challenge_id),
  );

  const accepted: AcceptedSubmissionRef[] = acceptedRows.map((row) => ({
    id: row.id,
    userId: row.user_id,
    challengeId: row.challenge_id,
    decidedAt: row.decided_at ?? params.now,
    createdAt: row.created_at,
    points: row.points,
  }));

  const first = firstAcceptedSubmission(accepted);
  let awarded = params.challengePoints;
  if (first?.id === params.submission.id) {
    await insertPointEvent(env, {
      groupId: params.groupId,
      weekId: params.weekId,
      userId: params.submission.user_id,
      kind: 'first_bonus',
      points: FIRST_FINISH_BONUS,
      submissionId: params.submission.id,
      now: params.now,
    });
    awarded += FIRST_FINISH_BONUS;
  }
  return awarded;
}

export async function loadWeekRefs(db: D1Database, groupId: string): Promise<WeekRef[]> {
  const rows = await all<{ id: string; starts_at: number }>(
    db.prepare('SELECT id, starts_at FROM weeks WHERE group_id = ? ORDER BY starts_at ASC').bind(groupId),
  );
  return rows.map((row) => ({ id: row.id, startsAt: row.starts_at }));
}

export async function loadAcceptedByWeek(
  db: D1Database,
  groupId: string,
): Promise<Map<string, Set<string>>> {
  const rows = await all<{ week_id: string; user_id: string }>(
    db
      .prepare(
        `SELECT w.id AS week_id, s.user_id AS user_id
           FROM submissions s
           JOIN challenges c ON c.id = s.challenge_id
           JOIN weeks w ON w.id = c.week_id
          WHERE w.group_id = ? AND s.status = 'accepted'`,
      )
      .bind(groupId),
  );
  const map = new Map<string, Set<string>>();
  for (const row of rows) {
    let set = map.get(row.week_id);
    if (!set) {
      set = new Set();
      map.set(row.week_id, set);
    }
    set.add(row.user_id);
  }
  return map;
}

export async function memberIds(db: D1Database, groupId: string): Promise<string[]> {
  const rows = await all<{ user_id: string }>(
    db.prepare('SELECT user_id FROM group_members WHERE group_id = ?').bind(groupId),
  );
  return rows.map((row) => row.user_id);
}

/**
 * Weekly winner (+50 to every member tied for most points) and streak bonuses
 * (only at/after the vote deadline, so grace-period votes count). Awards are
 * INSERT OR IGNORE, making repeated cron ticks idempotent.
 */
export async function awardWeekEnd(
  env: Env,
  group: GroupRow,
  week: WeekRow,
  now: number,
): Promise<{ winners: string[]; streaks: Map<string, number> }> {
  if (week.vote_deadline > now) return { winners: [], streaks: new Map() };

  await expirePendingForWeek(env.DB, week.id);

  const totals = await all<{ user_id: string; points: number }>(
    env.DB.prepare(
      `SELECT user_id, SUM(points) AS points
         FROM point_events
        WHERE group_id = ? AND week_id = ? AND kind IN ('challenge', 'first_bonus')
        GROUP BY user_id`,
    ).bind(group.id, week.id),
  );

  const members = await memberIds(env.DB, group.id);
  const memberSet = new Set(members);
  const winners = weeklyWinnerIds(
    totals
      .filter((row) => memberSet.has(row.user_id))
      .map((row) => ({ userId: row.user_id, points: row.points })),
  );
  for (const userId of winners) {
    await insertPointEvent(env, {
      groupId: group.id,
      weekId: week.id,
      userId,
      kind: 'weekly_winner',
      points: WEEKLY_WINNER_BONUS,
      submissionId: null,
      now,
    });
  }

  const weeks = await loadWeekRefs(env.DB, group.id);
  const accepted = await loadAcceptedByWeek(env.DB, group.id);
  const streaks = computeStreaks(weeks, accepted, week.id, members);

  for (const [userId, streak] of streaks) {
    const bonus = streakBonus(streak);
    if (bonus <= 0) continue;
    await insertPointEvent(env, {
      groupId: group.id,
      weekId: week.id,
      userId,
      kind: 'streak',
      points: bonus,
      submissionId: null,
      now,
    });
  }

  return { winners, streaks };
}

export async function finalizeDueWeeks(env: Env, group: GroupRow, now: number): Promise<void> {
  const due = await all<WeekRow>(
    env.DB.prepare(
      `SELECT * FROM weeks
        WHERE group_id = ? AND status = 'closed' AND vote_deadline <= ?
        ORDER BY starts_at DESC LIMIT 12`,
    ).bind(group.id, now),
  );
  for (const week of due) await awardWeekEnd(env, group, week, now);
}

export interface LeaderboardScope {
  week: WeekRow | null;
  entries: LeaderboardEntryJson[];
}

export async function leaderboard(
  db: D1Database,
  groupId: string,
  scope: 'week' | 'all',
): Promise<LeaderboardScope> {
  const latest = await getLatestWeek(db, groupId);
  const weekSql = `SELECT u.id, u.display_name, u.avatar_emoji, gm.joined_at,
                COALESCE((SELECT SUM(pe.points) FROM point_events pe
                           WHERE pe.group_id = gm.group_id AND pe.week_id = ? AND pe.user_id = u.id), 0) AS points
           FROM group_members gm
           JOIN users u ON u.id = gm.user_id
          WHERE gm.group_id = ?
          ORDER BY gm.joined_at ASC, u.id ASC`;
  const allTimeSql = `SELECT u.id, u.display_name, u.avatar_emoji, gm.joined_at,
                COALESCE((SELECT SUM(pe.points) FROM point_events pe
                           WHERE pe.group_id = gm.group_id AND pe.user_id = u.id), 0) AS points
           FROM group_members gm
           JOIN users u ON u.id = gm.user_id
          WHERE gm.group_id = ?
          ORDER BY gm.joined_at ASC, u.id ASC`;

  const statement =
    scope === 'week'
      ? db.prepare(weekSql).bind(latest?.id ?? '', groupId)
      : db.prepare(allTimeSql).bind(groupId);

  const rows = await all<{
    id: string;
    display_name: string;
    avatar_emoji: string | null;
    joined_at: number;
    points: number;
  }>(statement);

  const weeks = await loadWeekRefs(db, groupId);
  const accepted = await loadAcceptedByWeek(db, groupId);
  const streaks = latest
    ? computeStreaks(weeks, accepted, latest.id, rows.map((row) => row.id))
    : new Map<string, number>();

  const ranked = rankByPoints(
    rows.map((row) => ({
      user: toPublicUser({
        id: row.id,
        apple_sub: '',
        display_name: row.display_name,
        avatar_emoji: row.avatar_emoji,
        created_at: 0,
      }),
      points: row.points,
      streak: streaks.get(row.id) ?? 0,
    })),
  );

  return {
    week: latest,
    entries: ranked.map((entry) => ({
      user: entry.user,
      points: entry.points,
      rank: entry.rank,
      streak: entry.streak,
    })),
  };
}

/** Members with at least one challenge still unaccepted this week. */
export async function membersWithChallengesLeft(
  db: D1Database,
  groupId: string,
  weekId: string,
): Promise<Array<{ userId: string; count: number }>> {
  const challengeRows = await all<{ id: string }>(
    db.prepare('SELECT id FROM challenges WHERE week_id = ?').bind(weekId),
  );
  if (challengeRows.length === 0) return [];

  const acceptedRows = await all<{ user_id: string; challenge_id: string }>(
    db
      .prepare(
        `SELECT DISTINCT s.user_id, s.challenge_id
           FROM submissions s
           JOIN challenges c ON c.id = s.challenge_id
          WHERE c.week_id = ? AND s.status = 'accepted'`,
      )
      .bind(weekId),
  );
  const acceptedByUser = new Map<string, Set<string>>();
  for (const row of acceptedRows) {
    let set = acceptedByUser.get(row.user_id);
    if (!set) {
      set = new Set();
      acceptedByUser.set(row.user_id, set);
    }
    set.add(row.challenge_id);
  }

  const members = await memberIds(db, groupId);
  return members.map((userId) => ({
    userId,
    count: challengeRows.length - (acceptedByUser.get(userId)?.size ?? 0),
  }));
}

export async function weekForRead(
  db: D1Database,
  weekId: string,
): Promise<WeekRow> {
  const week = await getWeekById(db, weekId);
  if (!week) throw notFound('Week not found');
  return week;
}

/** Convenience used by cron: delete ancient sessions/rate-limit rows. */
export async function cleanupEphemeral(db: D1Database, now: number): Promise<void> {
  await db.batch([
    db.prepare('DELETE FROM sessions WHERE expires_at <= ?').bind(now),
    db.prepare('DELETE FROM rate_limits WHERE updated_at <= ?').bind(now - 2 * 86_400),
  ]);
}

/** Exposed for tests/routes that need a week JSON without an import cycle. */
export function serializeWeek(week: WeekRow) {
  return weekJson(week);
}
