import { Hono } from 'hono';
import { z } from 'zod';
import type { AppEnv, ReportReason } from '../types';
import { nowSeconds } from '../lib/db';
import { badRequest, conflict, forbidden, notFound } from '../lib/errors';
import { requireAuth } from '../middleware/auth';
import { parseJsonBody } from '../middleware/validate';
import { rateLimit } from '../middleware/rate-limit';
import { runInBackground } from '../middleware/background';
import { countMembers, requireGroupMembership } from '../services/groups';
import {
  loadSubmissionView,
  loadSubmissionContext,
  loadVoteCounts,
  requireSubmissionView,
} from '../services/submissions';
import {
  ALLOWED_REACTIONS,
  insertComment,
  listComments,
  toggleReaction,
} from '../services/banter';
import { isBlocked, isHiddenForViewer, reportTarget } from '../services/moderation';
import { deleteSubmissionMedia } from '../services/media';
import { decideSubmission } from '../business/voting';
import { awardAcceptedSubmission } from '../services/weeks';
import { pushBanter, pushContentRemoved, pushDecision } from '../push';

const app = new Hono<AppEnv>();
app.use('*', requireAuth);

const voteSchema = z.object({ approve: z.boolean() }).strict();

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

const reactionSchema = z.object({ emoji: z.enum(ALLOWED_REACTIONS) }).strict();

const commentSchema = z.object({ text: z.string().trim().min(1).max(280) }).strict();

/** 404 for content that was removed or is hidden from this viewer. */
async function assertVisible(
  db: D1Database,
  context: { submission: { id: string; user_id: string; status: string } },
  viewerId: string,
): Promise<void> {
  const hidden = await isHiddenForViewer(
    db,
    {
      targetType: 'submission',
      targetId: context.submission.id,
      ownerId: context.submission.user_id,
      status: context.submission.status,
    },
    viewerId,
  );
  if (hidden) throw notFound('Submission not found');
}

/** GET /submissions/:id — group members only. */
app.get('/:id', async (c) => {
  const context = await loadSubmissionContext(c.env.DB, c.req.param('id'));
  if (!context) throw notFound('Submission not found');
  await requireGroupMembership(c.env.DB, context.groupId, c.get('user').id);
  await assertVisible(c.env.DB, context, c.get('user').id);
  return c.json({
    submission: await requireSubmissionView(c.env.DB, context.submission.id, c.get('user').id),
  });
});

/**
 * POST /submissions/:id/vote — one vote per member, changeable while pending.
 * Every vote re-evaluates both thresholds; the first one reached decides.
 */
app.post('/:id/vote', rateLimit({ bucket: 'vote', capacity: 120, refillPerSecond: 2, by: 'user' }), async (c) => {
  const body = await parseJsonBody(c, voteSchema);
  const userId = c.get('user').id;
  const now = nowSeconds();

  const context = await loadSubmissionContext(c.env.DB, c.req.param('id'));
  if (!context) throw notFound('Submission not found');
  await requireGroupMembership(c.env.DB, context.groupId, userId);
  await assertVisible(c.env.DB, context, userId);

  if (context.submission.user_id === userId) {
    throw forbidden('You cannot vote on your own submission');
  }
  if (now > context.week.vote_deadline) {
    throw conflict('voting_closed', 'Voting is closed for this week');
  }
  if (context.submission.status !== 'pending') {
    throw conflict('submission_decided', `Submission is ${context.submission.status}`);
  }

  await c.env.DB.prepare(
    `INSERT INTO votes (submission_id, voter_id, approve, created_at)
     VALUES (?, ?, ?, ?)
     ON CONFLICT(submission_id, voter_id)
     DO UPDATE SET approve = excluded.approve, created_at = excluded.created_at`,
  )
    .bind(context.submission.id, userId, body.approve ? 1 : 0, now)
    .run();

  const counts = await loadVoteCounts(c.env.DB, context.submission.id);
  const decision = decideSubmission({
    approvals: counts.approvals,
    rejections: counts.rejections,
    eligibleVoters: context.submission.eligible_voters,
  });

  if (decision !== 'pending') {
    const update = await c.env.DB.prepare(
      "UPDATE submissions SET status = ?, decided_at = ? WHERE id = ? AND status = 'pending'",
    )
      .bind(decision, now, context.submission.id)
      .run();

    if ((update.meta.changes ?? 0) > 0) {
      if (decision === 'accepted') {
        const awarded = await awardAcceptedSubmission(c.env, {
          groupId: context.groupId,
          weekId: context.week.id,
          submission: context.submission,
          challengePoints: context.challengePoints,
          now,
        });
        runInBackground(
          c,
          pushDecision(c.env, context.groupId, context.submission.user_id, context.submission.id, true, awarded),
        );
      } else {
        // A rejected proof is no longer viewable by anyone: drop its R2 object
        // only after the status change committed.
        await deleteSubmissionMedia(c.env, context.submission.media_key);
        runInBackground(
          c,
          pushDecision(c.env, context.groupId, context.submission.user_id, context.submission.id, false, 0),
        );
      }
    }
  }

  const submission = await loadSubmissionView(c.env.DB, context.submission.id, userId);
  if (!submission) throw new Error('submission_missing_after_vote');
  return c.json({ submission });
});

/** DELETE /submissions/:id — submitter only, any status. Removes media + rows. */
app.delete('/:id', rateLimit({ bucket: 'submission-delete', capacity: 30, refillPerSecond: 30 / 300, by: 'user' }), async (c) => {
  const userId = c.get('user').id;
  const context = await loadSubmissionContext(c.env.DB, c.req.param('id'));
  if (!context) throw notFound('Submission not found');
  await requireGroupMembership(c.env.DB, context.groupId, userId);
  if (context.submission.user_id !== userId) {
    throw forbidden('Only the submitter can delete this proof');
  }

  await c.env.DB.batch([
    c.env.DB.prepare('DELETE FROM votes WHERE submission_id = ?').bind(context.submission.id),
    c.env.DB.prepare('DELETE FROM reactions WHERE submission_id = ?').bind(context.submission.id),
    c.env.DB.prepare(
      `DELETE FROM reports
        WHERE target_type = 'comment'
          AND target_id IN (SELECT id FROM comments WHERE submission_id = ?)`,
    ).bind(context.submission.id),
    c.env.DB.prepare('DELETE FROM comments WHERE submission_id = ?').bind(context.submission.id),
    c.env.DB.prepare('DELETE FROM banter_pushes WHERE submission_id = ?').bind(context.submission.id),
    c.env.DB.prepare('DELETE FROM reports WHERE target_type = ? AND target_id = ?').bind(
      'submission',
      context.submission.id,
    ),
    c.env.DB.prepare('DELETE FROM point_events WHERE submission_id = ?').bind(context.submission.id),
    c.env.DB.prepare('DELETE FROM submissions WHERE id = ?').bind(context.submission.id),
  ]);

  // After the row is gone: best-effort R2 cleanup through the one media helper.
  await deleteSubmissionMedia(c.env, context.submission.media_key);

  return c.json({ ok: true });
});

/** POST /submissions/:id/report — hide for me now, remove for all at threshold. */
app.post('/:id/report', rateLimit({ bucket: 'report', capacity: 30, refillPerSecond: 30 / 300, by: 'user' }), async (c) => {
  const body = await parseJsonBody(c, reportSchema);
  const userId = c.get('user').id;
  const now = nowSeconds();

  const context = await loadSubmissionContext(c.env.DB, c.req.param('id'));
  if (!context) throw notFound('Submission not found');
  const group = await requireGroupMembership(c.env.DB, context.groupId, userId);

  if (context.submission.user_id === userId) {
    throw badRequest('validation_error', 'You cannot report your own proof');
  }
  if (
    context.submission.status === 'removed' ||
    (await isBlocked(c.env.DB, userId, context.submission.user_id))
  ) {
    throw notFound('Submission not found');
  }

  const result = await reportTarget(c.env, {
    reporterId: userId,
    groupId: context.groupId,
    targetType: 'submission',
    targetId: context.submission.id,
    memberCount: await countMembers(c.env.DB, context.groupId),
    reason: body.reason as ReportReason,
    note: body.note && body.note.length > 0 ? body.note : null,
    now,
  });

  if (result.removed) {
    runInBackground(c, pushContentRemoved(c.env, group.owner_id, group.id, 'submission'));
  }

  return c.json({ ok: true });
});

/** POST /submissions/:id/reactions — toggle one of the six allowed emojis. */
app.post('/:id/reactions', rateLimit({ bucket: 'reaction', capacity: 60, refillPerSecond: 1, by: 'user' }), async (c) => {
  const body = await parseJsonBody(c, reactionSchema);
  const userId = c.get('user').id;
  const now = nowSeconds();

  const context = await loadSubmissionContext(c.env.DB, c.req.param('id'));
  if (!context) throw notFound('Submission not found');
  await requireGroupMembership(c.env.DB, context.groupId, userId);
  await assertVisible(c.env.DB, context, userId);

  await toggleReaction(c.env.DB, context.submission.id, userId, body.emoji, now);

  if (context.submission.user_id !== userId) {
    runInBackground(
      c,
      pushBanter(c.env, {
        groupId: context.groupId,
        submissionId: context.submission.id,
        recipientId: context.submission.user_id,
        actorId: userId,
        title: 'New reaction',
        body: `${c.get('user').displayName} reacted ${body.emoji} to your proof.`,
      }),
    );
  }

  const submission = await loadSubmissionView(c.env.DB, context.submission.id, userId);
  if (!submission) throw new Error('submission_missing_after_reaction');
  return c.json({ submission });
});

/** GET /submissions/:id/comments — oldest first, blocked authors hidden. */
app.get('/:id/comments', async (c) => {
  const userId = c.get('user').id;
  const context = await loadSubmissionContext(c.env.DB, c.req.param('id'));
  if (!context) throw notFound('Submission not found');
  const group = await requireGroupMembership(c.env.DB, context.groupId, userId);
  await assertVisible(c.env.DB, context, userId);

  return c.json({
    comments: await listComments(c.env.DB, context.submission.id, userId, group.owner_id),
  });
});

/** POST /submissions/:id/comments — 1-280 chars, trimmed. */
app.post('/:id/comments', rateLimit({ bucket: 'comment', capacity: 60, refillPerSecond: 1, by: 'user' }), async (c) => {
  const body = await parseJsonBody(c, commentSchema);
  const userId = c.get('user').id;
  const now = nowSeconds();

  const context = await loadSubmissionContext(c.env.DB, c.req.param('id'));
  if (!context) throw notFound('Submission not found');
  const group = await requireGroupMembership(c.env.DB, context.groupId, userId);
  await assertVisible(c.env.DB, context, userId);

  const comment = await insertComment(c.env.DB, {
    submissionId: context.submission.id,
    userId,
    text: body.text,
    now,
    ownerId: group.owner_id,
  });

  if (context.submission.user_id !== userId) {
    runInBackground(
      c,
      pushBanter(c.env, {
        groupId: context.groupId,
        submissionId: context.submission.id,
        recipientId: context.submission.user_id,
        actorId: userId,
        title: 'New comment',
        body: `${c.get('user').displayName}: ${body.text.slice(0, 120)}`,
      }),
    );
  }

  return c.json({ comment }, 201);
});

export default app;
