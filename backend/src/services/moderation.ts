import type { Env, PublicUser, ReportReason } from '../types';
import { toPublicUser } from '../types';
import { all, first } from '../lib/db';
import { conflict } from '../lib/errors';
import { deleteSubmissionMedia } from './media';

/**
 * Report + block moderation.
 *
 * Reports hide a target for their reporter immediately and, once enough
 * distinct members reported it, remove it for everyone. Blocks are one-way and
 * silent: the blocker no longer sees the blocked member's content, but voting
 * thresholds (`eligible_voters`) are never recalculated.
 */

export type ReportTargetType = 'submission' | 'comment';

/** `max(2, ceil(memberCount / 3))` distinct reporters remove a target. */
export function reportRemovalThreshold(memberCount: number): number {
  return Math.max(2, Math.ceil(Math.max(0, memberCount) / 3));
}

export async function isBlocked(
  db: D1Database,
  blockerId: string,
  blockedId: string,
): Promise<boolean> {
  const row = await first<{ one: number }>(
    db
      .prepare('SELECT 1 AS one FROM blocks WHERE blocker_id = ? AND blocked_id = ?')
      .bind(blockerId, blockedId),
  );
  return row !== null;
}

export async function blockUser(
  db: D1Database,
  blockerId: string,
  blockedId: string,
  now: number,
): Promise<void> {
  await db
    .prepare(
      `INSERT INTO blocks (blocker_id, blocked_id, created_at) VALUES (?, ?, ?)
       ON CONFLICT(blocker_id, blocked_id) DO NOTHING`,
    )
    .bind(blockerId, blockedId, now)
    .run();
}

export async function unblockUser(
  db: D1Database,
  blockerId: string,
  blockedId: string,
): Promise<void> {
  await db
    .prepare('DELETE FROM blocks WHERE blocker_id = ? AND blocked_id = ?')
    .bind(blockerId, blockedId)
    .run();
}

export async function listBlockedUsers(db: D1Database, userId: string): Promise<PublicUser[]> {
  const rows = await all<{
    id: string;
    display_name: string;
    avatar_emoji: string | null;
  }>(
    db
      .prepare(
        `SELECT u.id, u.display_name, u.avatar_emoji
           FROM blocks b
           JOIN users u ON u.id = b.blocked_id
          WHERE b.blocker_id = ?
          ORDER BY b.created_at DESC, u.id ASC`,
      )
      .bind(userId),
  );
  return rows.map((row) =>
    toPublicUser({
      id: row.id,
      apple_sub: '',
      display_name: row.display_name,
      avatar_emoji: row.avatar_emoji,
      created_at: 0,
      terms_accepted_at: null,
    }),
  );
}

export async function hasReported(
  db: D1Database,
  reporterId: string,
  targetType: ReportTargetType,
  targetId: string,
): Promise<boolean> {
  const row = await first<{ one: number }>(
    db
      .prepare(
        `SELECT 1 AS one FROM reports
          WHERE reporter_id = ? AND target_type = ? AND target_id = ?`,
      )
      .bind(reporterId, targetType, targetId),
  );
  return row !== null;
}

/**
 * A submission/comment is hidden for a viewer when they reported it, its author
 * is blocked by the viewer, or it was removed for everyone (the submitter still
 * sees their own removed submission).
 */
export async function isHiddenForViewer(
  db: D1Database,
  target: {
    targetType: ReportTargetType;
    targetId: string;
    ownerId: string;
    status?: string | null;
  },
  viewerId: string,
): Promise<boolean> {
  if (target.targetType === 'submission' && target.status === 'removed') {
    // Removed content is only ever shown to its own submitter.
    return target.ownerId !== viewerId;
  }
  if (await hasReported(db, viewerId, target.targetType, target.targetId)) return true;
  if (target.ownerId === viewerId) return false;
  return await isBlocked(db, viewerId, target.ownerId);
}

export async function countDistinctReporters(
  db: D1Database,
  targetType: ReportTargetType,
  targetId: string,
): Promise<number> {
  const row = await first<{ count: number }>(
    db
      .prepare(
        `SELECT COUNT(DISTINCT reporter_id) AS count FROM reports
          WHERE target_type = ? AND target_id = ?`,
      )
      .bind(targetType, targetId),
  );
  return row?.count ?? 0;
}

/** Removes a submission's ledger rows (challenge, first_bonus, captain). */
export async function deleteSubmissionPoints(db: D1Database, submissionId: string): Promise<void> {
  await db.prepare('DELETE FROM point_events WHERE submission_id = ?').bind(submissionId).run();
}

export interface ReportResult {
  /** True when this report pushed the target over the removal threshold. */
  removed: boolean;
}

/**
 * Records a report. Throws `already_reported` on a duplicate. Callers validate
 * ownership/visibility first; this function only enforces the threshold.
 */
export async function reportTarget(
  env: Env,
  params: {
    reporterId: string;
    groupId: string;
    targetType: ReportTargetType;
    targetId: string;
    memberCount: number;
    reason: ReportReason;
    note: string | null;
    now: number;
  },
): Promise<ReportResult> {
  if (await hasReported(env.DB, params.reporterId, params.targetType, params.targetId)) {
    throw conflict('already_reported', 'You already reported this');
  }

  try {
    await env.DB.prepare(
      `INSERT INTO reports
         (id, reporter_id, target_type, target_id, group_id, reason, note, created_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
    )
      .bind(
        crypto.randomUUID(),
        params.reporterId,
        params.targetType,
        params.targetId,
        params.groupId,
        params.reason,
        params.note,
        params.now,
      )
      .run();
  } catch (error) {
    if (error instanceof Error && /unique|constraint/iu.test(error.message)) {
      throw conflict('already_reported', 'You already reported this');
    }
    throw error;
  }

  const reporters = await countDistinctReporters(env.DB, params.targetType, params.targetId);
  if (reporters < reportRemovalThreshold(params.memberCount)) return { removed: false };

  if (params.targetType === 'submission') {
    const updated = await env.DB.prepare(
      `UPDATE submissions SET status = 'removed'
        WHERE id = ? AND status <> 'removed'`,
    )
      .bind(params.targetId)
      .run();
    if ((updated.meta.changes ?? 0) === 0) return { removed: false };
    await deleteSubmissionPoints(env.DB, params.targetId);
    const media = await first<{ media_key: string }>(
      env.DB.prepare('SELECT media_key FROM submissions WHERE id = ?').bind(params.targetId),
    );
    if (media) await deleteSubmissionMedia(env, media.media_key);
    return { removed: true };
  }

  const deleted = await env.DB.prepare('DELETE FROM comments WHERE id = ?')
    .bind(params.targetId)
    .run();
  return { removed: (deleted.meta.changes ?? 0) > 0 };
}
