import type {
  PublicUser,
  RaceJson,
  ReceiptJson,
  WeekRow,
} from '../types';
import { toPublicUser } from '../types';
import { all } from '../lib/db';
import { computeStreaks } from '../business/points';
import {
  buildRaceSeries,
  computeRaceMe,
  raceJson,
  type RaceMemberInput,
  type RacePointEvent,
} from '../business/race';
import {
  buildReceiptLines,
  pickManOfTheMatch,
  pickWoodenSpoon,
  rankTotals,
  type ReceiptBonusInput,
  type ReceiptSubmissionInput,
} from '../business/receipt';
import { loadAcceptedByWeek } from './weeks';
import { countWeekReplacements } from './groups';

/** Read-side aggregation for the v2 title race and full-time receipts. */

interface MemberRow {
  id: string;
  display_name: string;
  avatar_emoji: string | null;
  joined_at: number;
}

async function loadMembers(db: D1Database, groupId: string): Promise<MemberRow[]> {
  return await all<MemberRow>(
    db
      .prepare(
        `SELECT u.id, u.display_name, u.avatar_emoji, gm.joined_at
           FROM group_members gm
           JOIN users u ON u.id = gm.user_id
          WHERE gm.group_id = ?
          ORDER BY gm.joined_at ASC, u.id ASC`,
      )
      .bind(groupId),
  );
}

async function loadWeeks(db: D1Database, groupId: string): Promise<WeekRow[]> {
  return await all<WeekRow>(
    db
      .prepare('SELECT * FROM weeks WHERE group_id = ? ORDER BY starts_at ASC')
      .bind(groupId),
  );
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

/** GET /groups/:id/stats/race */
export async function groupRace(
  db: D1Database,
  groupId: string,
  userId: string,
): Promise<RaceJson> {
  const [weekRows, memberRows, events, accepted] = await Promise.all([
    loadWeeks(db, groupId),
    loadMembers(db, groupId),
    all<{ week_id: string; user_id: string; points: number }>(
      db.prepare('SELECT week_id, user_id, points FROM point_events WHERE group_id = ?').bind(groupId),
    ),
    loadAcceptedByWeek(db, groupId),
  ]);

  const members: RaceMemberInput[] = memberRows.map((row) => ({
    user: memberUser(row),
    joinedAt: row.joined_at,
  }));
  const raceEvents: RacePointEvent[] = events.map((row) => ({
    weekId: row.week_id,
    userId: row.user_id,
    points: row.points,
  }));

  const result = buildRaceSeries(
    weekRows.map((week) => ({ id: week.id, number: week.number, startsAt: week.starts_at })),
    members,
    raceEvents,
  );

  const latest = weekRows.at(-1);
  const streak = latest
    ? computeStreaks(
        weekRows.map((week) => ({ id: week.id, startsAt: week.starts_at })),
        accepted,
        latest.id,
        memberRows.map((row) => row.id),
      ).get(userId) ?? 0
    : 0;

  return raceJson(result, computeRaceMe(result, userId, streak));
}

/** GET /groups/:id/weeks/:weekId/receipt */
export async function weekReceipt(
  db: D1Database,
  group: { id: string; name: string; forfeit: string },
  week: WeekRow,
  userId: string,
): Promise<ReceiptJson> {
  const [weekRows, memberRows, totals, submissions, bonuses, vetoesUsed] = await Promise.all([
    loadWeeks(db, group.id),
    loadMembers(db, group.id),
    all<{ week_id: string; user_id: string; points: number }>(
      db
        .prepare(
          `SELECT week_id, user_id, SUM(points) AS points
             FROM point_events
            WHERE group_id = ?
            GROUP BY week_id, user_id`,
        )
        .bind(group.id),
    ),
    all<{
      challenge_id: string;
      challenge_title: string;
      status: 'pending' | 'accepted' | 'rejected' | 'expired' | 'removed';
      points: number;
    }>(
      db
        .prepare(
          `SELECT s.challenge_id, c.title AS challenge_title, s.status, c.points
             FROM submissions s
             JOIN challenges c ON c.id = s.challenge_id
            WHERE c.week_id = ? AND s.user_id = ?
            ORDER BY s.created_at ASC, s.id ASC`,
        )
        .bind(week.id, userId),
    ),
    all<{ kind: ReceiptBonusInput['kind']; points: number }>(
      db
        .prepare(
          `SELECT kind, SUM(points) AS points
             FROM point_events
            WHERE group_id = ? AND week_id = ? AND user_id = ?
              AND kind IN ('first_bonus', 'captain', 'streak', 'weekly_winner')
            GROUP BY kind`,
        )
        .bind(group.id, week.id, userId),
    ),
    countWeekReplacements(db, week.id),
  ]);

  const memberIds = memberRows.map((row) => row.id);
  const userById = new Map(memberRows.map((row) => [row.id, memberUser(row)]));

  const totalsBefore = new Map<string, number>(memberIds.map((id) => [id, 0]));
  const totalsThrough = new Map<string, number>(memberIds.map((id) => [id, 0]));
  const weekPoints = new Map<string, number>();

  const totalsByWeek = new Map<string, Map<string, number>>();
  for (const row of totals) {
    let perUser = totalsByWeek.get(row.week_id);
    if (!perUser) {
      perUser = new Map();
      totalsByWeek.set(row.week_id, perUser);
    }
    perUser.set(row.user_id, (perUser.get(row.user_id) ?? 0) + row.points);
  }

  for (const other of weekRows) {
    if (other.starts_at > week.starts_at) continue;
    const perUser = totalsByWeek.get(other.id);
    if (!perUser) continue;
    for (const memberId of memberIds) {
      const points = perUser.get(memberId) ?? 0;
      if (other.starts_at < week.starts_at) {
        totalsBefore.set(memberId, (totalsBefore.get(memberId) ?? 0) + points);
      }
      totalsThrough.set(memberId, (totalsThrough.get(memberId) ?? 0) + points);
      if (other.id === week.id) weekPoints.set(memberId, points);
    }
  }

  const rankAtStart = rankTotals(totalsBefore);
  const rankAtEnd = rankTotals(totalsThrough);
  const end = rankAtEnd.get(userId) ?? { rank: memberIds.length, total: 0 };
  const start = rankAtStart.get(userId) ?? { rank: end.rank, total: 0 };

  const lines = buildReceiptLines(
    submissions.map(
      (row): ReceiptSubmissionInput => ({
        challengeId: row.challenge_id,
        challengeTitle: row.challenge_title,
        status: row.status,
        points: row.points,
      }),
    ),
    bonuses,
  );

  const presentAllWeek = memberRows
    .filter((row) => row.joined_at <= week.starts_at)
    .map((row) => row.id);

  const manOfTheMatchId = pickManOfTheMatch(weekPoints, memberIds);
  const woodenSpoonId = pickWoodenSpoon(weekPoints, presentAllWeek);

  return {
    week: {
      id: week.id,
      number: week.number,
      startsAt: week.starts_at,
      endsAt: week.ends_at,
      vetoesUsed,
    },
    club: { name: group.name, forfeit: group.forfeit },
    player: {
      user: userById.get(userId) ?? { id: userId, displayName: '', avatarEmoji: null },
      rank: end.rank,
      rankDelta: start.rank - end.rank,
      total: end.total,
    },
    lines,
    manOfTheMatch: manOfTheMatchId ? userById.get(manOfTheMatchId) ?? null : null,
    woodenSpoon: woodenSpoonId ? userById.get(woodenSpoonId) ?? null : null,
  };
}
