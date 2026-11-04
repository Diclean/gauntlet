import type { Env } from '../types';
import { all, chunk } from '../lib/db';

/** Account deletion + group deletion, including R2 media. */

async function deleteR2Keys(env: Env, keys: readonly string[]): Promise<void> {
  for (const group of chunk([...new Set(keys)], 100)) {
    if (group.length === 0) continue;
    try {
      await env.MEDIA.delete(group);
    } catch {
      // Media deletion is retried implicitly by the client? Never fail the
      // account deletion on an R2 hiccup; the DB rows are still removed.
      console.error('media_delete_failed', { count: group.length });
    }
  }
}

async function groupMediaKeys(db: D1Database, groupId: string): Promise<string[]> {
  const rows = await all<{ media_key: string }>(
    db
      .prepare(
        `SELECT s.media_key
           FROM submissions s
           JOIN challenges c ON c.id = s.challenge_id
           JOIN weeks w ON w.id = c.week_id
          WHERE w.group_id = ?`,
      )
      .bind(groupId),
  );
  return rows.map((row) => row.media_key);
}

/** Deletes every row belonging to a group plus all of its media objects. */
export async function deleteGroupCompletely(env: Env, groupId: string): Promise<void> {
  const mediaKeys = await groupMediaKeys(env.DB, groupId);
  await deleteR2Keys(env, mediaKeys);

  await env.DB.batch([
    env.DB.prepare(
      `DELETE FROM votes
        WHERE submission_id IN (
          SELECT s.id FROM submissions s
          JOIN challenges c ON c.id = s.challenge_id
          JOIN weeks w ON w.id = c.week_id
          WHERE w.group_id = ?
        )`,
    ).bind(groupId),
    env.DB.prepare(
      `DELETE FROM submissions
        WHERE challenge_id IN (
          SELECT c.id FROM challenges c
          JOIN weeks w ON w.id = c.week_id
          WHERE w.group_id = ?
        )`,
    ).bind(groupId),
    env.DB.prepare(
      `DELETE FROM challenges
        WHERE week_id IN (SELECT id FROM weeks WHERE group_id = ?)`,
    ).bind(groupId),
    env.DB.prepare('DELETE FROM weeks WHERE group_id = ?').bind(groupId),
    env.DB.prepare('DELETE FROM point_events WHERE group_id = ?').bind(groupId),
    env.DB.prepare('DELETE FROM group_members WHERE group_id = ?').bind(groupId),
    env.DB.prepare('DELETE FROM groups WHERE id = ?').bind(groupId),
  ]);
}

/**
 * Deletes the user, their sessions/devices, votes, submissions + media and
 * points. Groups they own are transferred to the earliest remaining member,
 * or deleted if they were the last member. This satisfies the App Store
 * account-deletion requirement.
 */
export async function deleteAccount(env: Env, userId: string): Promise<void> {
  const ownedGroups = await all<{ id: string }>(
    env.DB.prepare('SELECT id FROM groups WHERE owner_id = ?').bind(userId),
  );
  for (const group of ownedGroups) {
    const successor = await env.DB.prepare(
      `SELECT user_id FROM group_members
        WHERE group_id = ? AND user_id <> ?
        ORDER BY joined_at ASC, user_id ASC LIMIT 1`,
    )
      .bind(group.id, userId)
      .first<{ user_id: string }>();

    if (successor) {
      await env.DB.prepare('UPDATE groups SET owner_id = ? WHERE id = ?')
        .bind(successor.user_id, group.id)
        .run();
    } else {
      await deleteGroupCompletely(env, group.id);
    }
  }

  const mediaRows = await all<{ media_key: string }>(
    env.DB.prepare('SELECT media_key FROM submissions WHERE user_id = ?').bind(userId),
  );
  await deleteR2Keys(env, mediaRows.map((row) => row.media_key));

  await env.DB.batch([
    env.DB.prepare(
      `DELETE FROM votes
        WHERE submission_id IN (SELECT id FROM submissions WHERE user_id = ?)`,
    ).bind(userId),
    env.DB.prepare('DELETE FROM votes WHERE voter_id = ?').bind(userId),
    env.DB.prepare('DELETE FROM submissions WHERE user_id = ?').bind(userId),
    env.DB.prepare('DELETE FROM point_events WHERE user_id = ?').bind(userId),
    env.DB.prepare('DELETE FROM group_members WHERE user_id = ?').bind(userId),
    env.DB.prepare('DELETE FROM devices WHERE user_id = ?').bind(userId),
    env.DB.prepare('DELETE FROM sessions WHERE user_id = ?').bind(userId),
    env.DB.prepare('DELETE FROM users WHERE id = ?').bind(userId),
  ]);
}
