import type {
  BannedUserJson,
  GroupJson,
  GroupMemberRow,
  GroupRow,
  MemberJson,
  WeekJson,
  WeekRow,
} from '../types';
import { toPublicUser } from '../types';
import { all, first } from '../lib/db';
import { forbidden, notFound } from '../lib/errors';

/** Group lookup, membership authorization and camelCase serialization. */

const INVITE_ALPHABET = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ23456789';
const MAX_MEMBERS = 30;

export const GROUP_MAX_MEMBERS = MAX_MEMBERS;

/** Default, display-only club forfeit (SPEC §5). */
export const DEFAULT_FORFEIT = 'Buys the round 🍺';
export const MAX_FORFEIT_LENGTH = 60;

export function generateInviteCode(): string {
  let code = '';
  while (code.length < 6) {
    const bytes = crypto.getRandomValues(new Uint8Array(8));
    for (const byte of bytes) {
      // Rejection sampling keeps the alphabet uniform (34 * 7 = 238).
      if (byte >= 238) continue;
      code += INVITE_ALPHABET[byte % INVITE_ALPHABET.length]!;
      if (code.length === 6) break;
    }
  }
  return code;
}

export async function getGroupRow(db: D1Database, groupId: string): Promise<GroupRow | null> {
  return await first<GroupRow>(db.prepare('SELECT * FROM groups WHERE id = ?').bind(groupId));
}

export async function getMembership(
  db: D1Database,
  groupId: string,
  userId: string,
): Promise<GroupMemberRow | null> {
  return await first<GroupMemberRow>(
    db
      .prepare('SELECT * FROM group_members WHERE group_id = ? AND user_id = ?')
      .bind(groupId, userId),
  );
}

/**
 * Authorization gate for every group-scoped route. A missing group is 404; an
 * existing group the caller is not in is 403 (never leak its contents).
 */
export async function requireGroupMembership(
  db: D1Database,
  groupId: string,
  userId: string,
): Promise<GroupRow> {
  const group = await getGroupRow(db, groupId);
  if (!group) throw notFound('Group not found');
  const membership = await getMembership(db, groupId, userId);
  if (!membership) throw forbidden('You are not a member of this group');
  return group;
}

export async function requireGroupOwnership(
  db: D1Database,
  groupId: string,
  userId: string,
): Promise<GroupRow> {
  const group = await requireGroupMembership(db, groupId, userId);
  if (group.owner_id !== userId) throw forbidden('Only the group owner can do that');
  return group;
}

export async function countMembers(db: D1Database, groupId: string): Promise<number> {
  const row = await first<{ count: number }>(
    db.prepare('SELECT COUNT(*) AS count FROM group_members WHERE group_id = ?').bind(groupId),
  );
  return row?.count ?? 0;
}

export function inviteUrlFor(inviteCode: string, publicBaseUrl?: string): string {
  const base = (publicBaseUrl ?? '').trim().replace(/\/+$/u, '');
  return `${base}/join/${inviteCode}`;
}

export async function groupJson(
  db: D1Database,
  group: GroupRow,
  publicBaseUrl?: string,
): Promise<GroupJson> {
  return groupJsonWithCount(group, await countMembers(db, group.id), publicBaseUrl);
}

export function groupJsonWithCount(
  group: GroupRow,
  memberCount: number,
  publicBaseUrl?: string,
): GroupJson {
  return {
    id: group.id,
    name: group.name,
    inviteCode: group.invite_code,
    challengesPerWeek: group.challenges_per_week,
    theme: group.theme,
    language: group.language,
    timezone: group.timezone,
    ownerId: group.owner_id,
    memberCount,
    forfeit: group.forfeit ?? DEFAULT_FORFEIT,
    inviteUrl: inviteUrlFor(group.invite_code, publicBaseUrl),
  };
}

export async function listMembers(db: D1Database, groupId: string): Promise<MemberJson[]> {
  const rows = await all<{
    id: string;
    apple_sub: string;
    display_name: string;
    avatar_emoji: string | null;
    created_at: number;
    joined_at: number;
  }>(
    db
      .prepare(
        `SELECT u.*, gm.joined_at
           FROM group_members gm
           JOIN users u ON u.id = gm.user_id
          WHERE gm.group_id = ?
          ORDER BY gm.joined_at ASC, u.id ASC`,
      )
      .bind(groupId),
  );
  return rows.map((row) => ({
    user: toPublicUser(row),
    joinedAt: row.joined_at,
  }));
}

/** Club members banned (removed) by the owner, newest ban first. */
export async function listBans(db: D1Database, groupId: string): Promise<BannedUserJson[]> {
  const rows = await all<{
    id: string;
    display_name: string;
    avatar_emoji: string | null;
    banned_at: number;
  }>(
    db
      .prepare(
        `SELECT u.id, u.display_name, u.avatar_emoji, b.created_at AS banned_at
           FROM group_bans b
           JOIN users u ON u.id = b.user_id
          WHERE b.group_id = ?
          ORDER BY b.created_at DESC, u.id ASC`,
      )
      .bind(groupId),
  );
  return rows.map((row) => ({
    ...toPublicUser({
      id: row.id,
      apple_sub: '',
      display_name: row.display_name,
      avatar_emoji: row.avatar_emoji,
      created_at: 0,
    }),
    bannedAt: row.banned_at,
  }));
}

/**
 * Fixtures this club already replaced this week. A replacement marks the old
 * challenge with `replaced_by`, so the count is also the veto limit counter.
 */
export async function countWeekReplacements(
  db: D1Database,
  weekId: string,
): Promise<number> {
  const row = await first<{ count: number }>(
    db
      .prepare(
        'SELECT COUNT(*) AS count FROM challenges WHERE week_id = ? AND replaced_by IS NOT NULL',
      )
      .bind(weekId),
  );
  return row?.count ?? 0;
}

/** Batched `countWeekReplacements` for the weeks list. */
export async function replacementsForWeeks(
  db: D1Database,
  weekIds: readonly string[],
): Promise<Map<string, number>> {
  if (weekIds.length === 0) return new Map();
  const placeholders = weekIds.map(() => '?').join(', ');
  const rows = await all<{ week_id: string; count: number }>(
    db
      .prepare(
        `SELECT week_id, COUNT(*) AS count FROM challenges
          WHERE week_id IN (${placeholders}) AND replaced_by IS NOT NULL
          GROUP BY week_id`,
      )
      .bind(...weekIds),
  );
  return new Map(rows.map((row) => [row.week_id, row.count]));
}

export function weekJson(
  week: WeekRow,
  myCaptainChallengeId: string | null,
  vetoesUsed: number,
): WeekJson {
  return {
    id: week.id,
    number: week.number,
    startsAt: week.starts_at,
    endsAt: week.ends_at,
    voteDeadline: week.vote_deadline,
    status: week.status,
    myCaptainChallengeId,
    vetoesUsed,
  };
}

/** The caller's captain fixture per week, for `Week.myCaptainChallengeId`. */
export async function captainMapForWeeks(
  db: D1Database,
  weekIds: readonly string[],
  userId: string,
): Promise<Map<string, string>> {
  if (weekIds.length === 0) return new Map();
  const placeholders = weekIds.map(() => '?').join(', ');
  const rows = await all<{ week_id: string; challenge_id: string }>(
    db
      .prepare(
        `SELECT week_id, challenge_id FROM captains
          WHERE user_id = ? AND week_id IN (${placeholders})`,
      )
      .bind(userId, ...weekIds),
  );
  return new Map(rows.map((row) => [row.week_id, row.challenge_id]));
}
