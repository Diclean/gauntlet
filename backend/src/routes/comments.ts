import { Hono } from 'hono';
import type { Context } from 'hono';
import type { AppEnv, GroupRow, ReportReason } from '../types';
import { nowSeconds } from '../lib/db';
import { badRequest, forbidden, notFound } from '../lib/errors';
import { requireAuth } from '../middleware/auth';
import { parseJsonBody } from '../middleware/validate';
import { rateLimit } from '../middleware/rate-limit';
import { runInBackground } from '../middleware/background';
import { countMembers, requireGroupMembership } from '../services/groups';
import { loadSubmissionContext, type SubmissionContext } from '../services/submissions';
import { getComment } from '../services/banter';
import {
  isBlocked,
  isHiddenForViewer,
  reportTarget,
} from '../services/moderation';
import { pushContentRemoved } from '../push';
import { z } from 'zod';

const app = new Hono<AppEnv>();
app.use('*', requireAuth);

const REPORT_REASONS = [
  'nudity',
  'violence',
  'harassment',
  'dangerous',
  'spam',
  'other',
] as const;

const reportSchema = z
  .object({
    reason: z.enum(REPORT_REASONS),
    note: z.string().trim().max(200).optional(),
  })
  .strict();

/**
 * Loads a comment and its submission context, then enforces club membership and
 * the same visibility rules as the submission (removed/reported/blocked).
 */
async function loadVisibleComment(
  c: Context<AppEnv>,
  commentId: string,
): Promise<{
  comment: { id: string; submission_id: string; user_id: string };
  submission: SubmissionContext;
  group: GroupRow;
}> {
  const comment = await getComment(c.env.DB, commentId);
  if (!comment) throw notFound('Comment not found');
  const submission = await loadSubmissionContext(c.env.DB, comment.submission_id);
  if (!submission) throw notFound('Comment not found');
  const group = await requireGroupMembership(c.env.DB, submission.groupId, c.get('user').id);

  const hiddenSubmission = await isHiddenForViewer(
    c.env.DB,
    {
      targetType: 'submission',
      targetId: submission.submission.id,
      ownerId: submission.submission.user_id,
      status: submission.submission.status,
    },
    c.get('user').id,
  );
  if (hiddenSubmission) throw notFound('Comment not found');
  if (await isBlocked(c.env.DB, c.get('user').id, comment.user_id)) {
    throw notFound('Comment not found');
  }

  return { comment, submission, group };
}

/** DELETE /comments/:id — the comment author or the club owner. */
app.delete('/:id', rateLimit({ bucket: 'comment-delete', capacity: 30, refillPerSecond: 30 / 300, by: 'user' }), async (c) => {
  const userId = c.get('user').id;
  const { comment, group } = await loadVisibleComment(c, c.req.param('id'));
  if (comment.user_id !== userId && group.owner_id !== userId) {
    throw forbidden('Only the author or the club owner can delete this comment');
  }
  await c.env.DB.prepare('DELETE FROM comments WHERE id = ?').bind(comment.id).run();
  return c.json({ ok: true });
});

/** POST /comments/:id/report — same threshold as proofs. */
app.post('/:id/report', rateLimit({ bucket: 'report', capacity: 30, refillPerSecond: 30 / 300, by: 'user' }), async (c) => {
  const body = await parseJsonBody(c, reportSchema);
  const userId = c.get('user').id;
  const { comment, submission, group } = await loadVisibleComment(c, c.req.param('id'));

  if (comment.user_id === userId) {
    throw badRequest('validation_error', 'You cannot report your own comment');
  }
  if (await isBlocked(c.env.DB, userId, comment.user_id)) {
    throw notFound('Comment not found');
  }
  // A block hides the comment above, so this is only reached for visible content.
  if (submission.submission.status === 'removed') {
    throw notFound('Comment not found');
  }

  const result = await reportTarget(c.env, {
    reporterId: userId,
    groupId: group.id,
    targetType: 'comment',
    targetId: comment.id,
    memberCount: await countMembers(c.env.DB, group.id),
    reason: body.reason as ReportReason,
    note: body.note && body.note.length > 0 ? body.note : null,
    now: nowSeconds(),
  });

  if (result.removed) {
    runInBackground(c, pushContentRemoved(c.env, group.owner_id, group.id, 'comment'));
  }

  return c.json({ ok: true });
});

export default app;
