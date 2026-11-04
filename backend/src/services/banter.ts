import type { CommentJson, PublicUser, ReactionJson } from '../types';
import { toPublicUser } from '../types';
import { all, first } from '../lib/db';

/**
 * Reactions + comments ("banter"). Emoji validation lives in the route schema;
 * this module only reads/writes and applies viewer-specific visibility (blocks).
 */

export const ALLOWED_REACTIONS = ['🔥', '😂', '🤡', '🐐', '😮', '👏'] as const;
export type AllowedReaction = (typeof ALLOWED_REACTIONS)[number];

export function isAllowedReaction(value: string): value is AllowedReaction {
  return (ALLOWED_REACTIONS as readonly string[]).includes(value);
}

/**
 * Reactions for a page of submissions, in fixed emoji order, zero-count
 * omitted. One query per 50 submissions.
 */
export async function loadReactions(
  db: D1Database,
  submissionIds: readonly string[],
  viewerId: string,
): Promise<Map<string, ReactionJson[]>> {
  const ids = [...new Set(submissionIds)];
  const result = new Map<string, ReactionJson[]>();
  if (ids.length === 0) return result;

  const bySubmission = new Map<string, Map<string, { count: number; mine: boolean }>>();
  const CHUNK = 50;
  for (let offset = 0; offset < ids.length; offset += CHUNK) {
    const chunk = ids.slice(offset, offset + CHUNK);
    const placeholders = chunk.map(() => '?').join(', ');
    const rows = await all<{ submission_id: string; emoji: string; count: number; mine: number }>(
      db
        .prepare(
          `SELECT submission_id, emoji, COUNT(*) AS count,
                  MAX(CASE WHEN user_id = ? THEN 1 ELSE 0 END) AS mine
             FROM reactions
            WHERE submission_id IN (${placeholders})
            GROUP BY submission_id, emoji`,
        )
        .bind(viewerId, ...chunk),
    );
    for (const row of rows) {
      let perEmoji = bySubmission.get(row.submission_id);
      if (!perEmoji) {
        perEmoji = new Map();
        bySubmission.set(row.submission_id, perEmoji);
      }
      perEmoji.set(row.emoji, { count: row.count, mine: row.mine > 0 });
    }
  }

  for (const id of ids) {
    const perEmoji = bySubmission.get(id);
    const reactions: ReactionJson[] = [];
    for (const emoji of ALLOWED_REACTIONS) {
      const entry = perEmoji?.get(emoji);
      if (!entry || entry.count <= 0) continue;
      reactions.push({ emoji, count: entry.count, mine: entry.mine });
    }
    result.set(id, reactions);
  }
  return result;
}

/** Comment counts visible to the viewer (blocked authors excluded). */
export async function loadCommentCounts(
  db: D1Database,
  submissionIds: readonly string[],
  viewerId: string,
): Promise<Map<string, number>> {
  const ids = [...new Set(submissionIds)];
  const result = new Map<string, number>();
  if (ids.length === 0) return result;

  const CHUNK = 50;
  for (let offset = 0; offset < ids.length; offset += CHUNK) {
    const chunk = ids.slice(offset, offset + CHUNK);
    const placeholders = chunk.map(() => '?').join(', ');
    const rows = await all<{ submission_id: string; count: number }>(
      db
        .prepare(
          `SELECT c.submission_id, COUNT(*) AS count
             FROM comments c
            WHERE c.submission_id IN (${placeholders})
              AND NOT EXISTS (
                SELECT 1 FROM blocks b
                 WHERE b.blocker_id = ? AND b.blocked_id = c.user_id
              )
              AND NOT EXISTS (
                SELECT 1 FROM reports r
                 WHERE r.reporter_id = ? AND r.target_type = 'comment'
                   AND r.target_id = c.id
              )
            GROUP BY c.submission_id`,
        )
        .bind(...chunk, viewerId, viewerId),
    );
    for (const row of rows) result.set(row.submission_id, row.count);
  }
  return result;
}

export async function toggleReaction(
  db: D1Database,
  submissionId: string,
  userId: string,
  emoji: AllowedReaction,
  now: number,
): Promise<void> {
  const existing = await first<{ one: number }>(
    db
      .prepare(
        'SELECT 1 AS one FROM reactions WHERE user_id = ? AND submission_id = ? AND emoji = ?',
      )
      .bind(userId, submissionId, emoji),
  );
  if (existing) {
    await db
      .prepare('DELETE FROM reactions WHERE user_id = ? AND submission_id = ? AND emoji = ?')
      .bind(userId, submissionId, emoji)
      .run();
    return;
  }
  await db
    .prepare(
      `INSERT INTO reactions (user_id, submission_id, emoji, created_at) VALUES (?, ?, ?, ?)
       ON CONFLICT(user_id, submission_id, emoji) DO NOTHING`,
    )
    .bind(userId, submissionId, emoji, now)
    .run();
}

interface CommentRow {
  id: string;
  submission_id: string;
  user_id: string;
  text: string;
  created_at: number;
  display_name: string;
  avatar_emoji: string | null;
}

const COMMENT_SELECT = `
  SELECT c.id, c.submission_id, c.user_id, c.text, c.created_at,
         u.display_name, u.avatar_emoji
    FROM comments c
    JOIN users u ON u.id = c.user_id
`;

function commentJson(row: CommentRow, ownerId: string, viewerId: string): CommentJson {
  const user: PublicUser = toPublicUser({
    id: row.user_id,
    apple_sub: '',
    display_name: row.display_name,
    avatar_emoji: row.avatar_emoji,
    created_at: 0,
    terms_accepted_at: null,
  });
  return {
    id: row.id,
    user,
    text: row.text,
    createdAt: row.created_at,
    canDelete: row.user_id === viewerId || ownerId === viewerId,
  };
}

/** Comments oldest first, hiding authors the viewer blocked. */
export async function listComments(
  db: D1Database,
  submissionId: string,
  viewerId: string,
  ownerId: string,
): Promise<CommentJson[]> {
  const rows = await all<CommentRow>(
    db
      .prepare(
        `${COMMENT_SELECT}
          WHERE c.submission_id = ?
            AND NOT EXISTS (
              SELECT 1 FROM blocks b
               WHERE b.blocker_id = ? AND b.blocked_id = c.user_id
            )
            AND NOT EXISTS (
              SELECT 1 FROM reports r
               WHERE r.reporter_id = ? AND r.target_type = 'comment'
                 AND r.target_id = c.id
            )
          ORDER BY c.created_at ASC, c.rowid ASC`,
      )
      .bind(submissionId, viewerId, viewerId),
  );
  return rows.map((row) => commentJson(row, ownerId, viewerId));
}

export async function getComment(
  db: D1Database,
  commentId: string,
): Promise<{ id: string; submission_id: string; user_id: string } | null> {
  return await first<{ id: string; submission_id: string; user_id: string }>(
    db
      .prepare('SELECT id, submission_id, user_id FROM comments WHERE id = ?')
      .bind(commentId),
  );
}

export async function insertComment(
  db: D1Database,
  params: {
    submissionId: string;
    userId: string;
    text: string;
    now: number;
    ownerId: string;
  },
): Promise<CommentJson> {
  const id = crypto.randomUUID();
  await db
    .prepare(
      'INSERT INTO comments (id, submission_id, user_id, text, created_at) VALUES (?, ?, ?, ?, ?)',
    )
    .bind(id, params.submissionId, params.userId, params.text, params.now)
    .run();
  const row = await first<CommentRow>(
    db.prepare(`${COMMENT_SELECT} WHERE c.id = ?`).bind(id),
  );
  if (!row) throw new Error('comment_missing_after_insert');
  return commentJson(row, params.ownerId, params.userId);
}
