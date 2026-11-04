import { sha256Hex } from '../src/lib/crypto';
import { startOfLocalWeek } from '../src/business/time';

/** Integration-test fixtures are anchored to the real clock so open-week checks pass. */
export const NOW = Math.floor(Date.now() / 1000);
export const WEEK_START = startOfLocalWeek(NOW, 'UTC'); // current Monday 00:00 UTC
export const WEEK_END = WEEK_START + 7 * 86_400 - 1; // Sunday 23:59:59 UTC
export const VOTE_DEADLINE = WEEK_START + 7 * 86_400 + 12 * 3_600;

export const U1 = '11111111-1111-4111-8111-111111111111';
export const U2 = '22222222-2222-4222-8222-222222222222';
export const U3 = '33333333-3333-4333-8333-333333333333';
export const GROUP = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
export const GROUP2 = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
export const WEEK = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';
export const CHALLENGE = 'dddddddd-dddd-4ddd-8ddd-dddddddddddd';
export const SUBMISSION = 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee';
export const MEDIA_KEY = 'media-test.jpg';

export const TOKEN_1 = 'token-for-user-1-0123456789abcdef';
export const TOKEN_2 = 'token-for-user-2-0123456789abcdef';
export const TOKEN_3 = 'token-for-user-3-0123456789abcdef';

const TABLES = [
  'used_nonces',
  'reactions',
  'comments',
  'banter_pushes',
  'reports',
  'blocks',
  'group_bans',
  'vetoes',
  'captains',
  'notification_prefs',
  'votes',
  'point_events',
  'monthly_award_runs',
  'monthly_awards',
  'submissions',
  'challenges',
  'weeks',
  'group_members',
  'groups',
  'devices',
  'sessions',
  'users',
  'rate_limits',
] as const;

export async function resetDb(db: D1Database): Promise<void> {
  for (const table of TABLES) {
    await db.prepare(`DELETE FROM ${table}`).run();
  }
}

export async function insertUser(
  db: D1Database,
  id: string,
  name: string,
  emoji: string | null = null,
  options: { terms?: boolean } = {},
): Promise<void> {
  // Fixtures accept the house rules by default; pass {terms:false} to test the gate.
  const termsAcceptedAt = options.terms === false ? null : NOW - 9_000;
  await db
    .prepare(
      `INSERT INTO users
         (id, apple_sub, display_name, avatar_emoji, created_at, terms_accepted_at)
       VALUES (?, ?, ?, ?, ?, ?)`,
    )
    .bind(id, `apple-${id}`, name, emoji, NOW - 10_000, termsAcceptedAt)
    .run();
}

export async function insertSession(
  db: D1Database,
  userId: string,
  token: string,
): Promise<void> {
  const tokenHash = await sha256Hex(token);
  await db
    .prepare(
      'INSERT INTO sessions (token_hash, user_id, expires_at, created_at) VALUES (?, ?, ?, ?)',
    )
    .bind(tokenHash, userId, NOW + 3_600, NOW)
    .run();
}

export async function insertGroup(
  db: D1Database,
  id: string,
  ownerId: string,
  inviteCode: string,
  name = 'Test group',
  forfeit = 'Buys the round 🍺',
  timezone = 'UTC',
): Promise<void> {
  await db
    .prepare(
      `INSERT INTO groups
         (id, name, owner_id, invite_code, challenges_per_week, theme, language, timezone, forfeit, created_at)
       VALUES (?, ?, ?, ?, 5, NULL, 'en', ?, ?, ?)`,
    )
    .bind(id, name, ownerId, inviteCode, timezone, forfeit, NOW - 5_000)
    .run();
}

export async function insertMember(
  db: D1Database,
  groupId: string,
  userId: string,
  joinedAt = NOW - 4_000,
): Promise<void> {
  await db
    .prepare('INSERT INTO group_members (group_id, user_id, joined_at) VALUES (?, ?, ?)')
    .bind(groupId, userId, joinedAt)
    .run();
}

export async function insertWeek(
  db: D1Database,
  groupId: string,
  id = WEEK,
  status: 'open' | 'closed' = 'open',
  options: {
    startsAt?: number;
    endsAt?: number;
    voteDeadline?: number;
    number?: number;
  } = {},
): Promise<void> {
  const startsAt = options.startsAt ?? WEEK_START;
  await db
    .prepare(
      `INSERT INTO weeks (id, group_id, starts_at, ends_at, vote_deadline, status, reminder_sent, number)
       VALUES (?, ?, ?, ?, ?, ?, 0, ?)`,
    )
    .bind(
      id,
      groupId,
      startsAt,
      options.endsAt ?? startsAt + 7 * 86_400 - 1,
      options.voteDeadline ?? VOTE_DEADLINE,
      status,
      options.number ?? 1,
    )
    .run();
}

export async function insertChallenge(
  db: D1Database,
  weekId: string,
  id = CHALLENGE,
  points = 10,
): Promise<void> {
  await db
    .prepare(
      `INSERT INTO challenges (id, week_id, title, description, difficulty, points, position)
       VALUES (?, ?, 'Test challenge', 'Do the test thing.', 'easy', ?, 0)`,
    )
    .bind(id, weekId, points)
    .run();
}

export async function insertSubmission(
  db: D1Database,
  options: {
    id?: string;
    challengeId?: string;
    userId?: string;
    mediaKey?: string;
    status?: 'pending' | 'accepted' | 'rejected' | 'expired' | 'removed';
    eligibleVoters?: number;
    createdAt?: number;
  } = {},
): Promise<void> {
  const id = options.id ?? SUBMISSION;
  await db
    .prepare(
      `INSERT INTO submissions
         (id, challenge_id, user_id, media_key, media_type, caption, status,
          eligible_voters, created_at, decided_at)
       VALUES (?, ?, ?, ?, 'photo', NULL, ?, ?, ?, NULL)`,
    )
    .bind(
      id,
      options.challengeId ?? CHALLENGE,
      options.userId ?? U1,
      options.mediaKey ?? MEDIA_KEY,
      options.status ?? 'pending',
      options.eligibleVoters ?? 1,
      options.createdAt ?? NOW - 1_000,
    )
    .run();
}

export async function insertPointEvent(
  db: D1Database,
  options: {
    id?: string;
    groupId?: string;
    weekId: string;
    userId: string;
    kind?:
      | 'challenge'
      | 'first_bonus'
      | 'weekly_winner'
      | 'streak'
      | 'monthly_award'
      | 'captain';
    points: number;
    submissionId?: string | null;
    createdAt?: number;
  },
): Promise<void> {
  await db
    .prepare(
      `INSERT INTO point_events
         (id, group_id, week_id, user_id, kind, points, submission_id, created_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
    )
    .bind(
      options.id ?? crypto.randomUUID(),
      options.groupId ?? GROUP,
      options.weekId,
      options.userId,
      options.kind ?? 'challenge',
      options.points,
      options.submissionId ?? null,
      options.createdAt ?? NOW,
    )
    .run();
}

export async function insertMonthlyAward(
  db: D1Database,
  options: {
    id?: string;
    groupId?: string;
    month: string;
    award:
      | 'player_of_the_month'
      | 'golden_boot'
      | 'toughest_ref'
      | 'comeback_kid'
      | 'first_to_score'
      | 'wooden_spoon';
    userId: string;
    value?: number;
    createdAt?: number;
  },
): Promise<void> {
  await db
    .prepare(
      `INSERT INTO monthly_awards
         (id, group_id, month, award, user_id, value, created_at)
       VALUES (?, ?, ?, ?, ?, ?, ?)`,
    )
    .bind(
      options.id ?? crypto.randomUUID(),
      options.groupId ?? GROUP,
      options.month,
      options.award,
      options.userId,
      options.value ?? 0,
      options.createdAt ?? NOW,
    )
    .run();
}

export function auth(token: string): Record<string, string> {
  return { Authorization: `Bearer ${token}` };
}

export function jsonAuth(token: string): Record<string, string> {
  return { ...auth(token), 'Content-Type': 'application/json' };
}
