import { Hono } from 'hono';
import { z } from 'zod';
import type { AppEnv } from '../types';
import { nowSeconds } from '../lib/db';
import { conflict, forbidden, notFound } from '../lib/errors';
import { requireAuth } from '../middleware/auth';
import { parseJsonBody } from '../middleware/validate';
import { rateLimit } from '../middleware/rate-limit';
import { runInBackground } from '../middleware/background';
import { requireGroupMembership } from '../services/groups';
import {
  loadSubmissionView,
  loadSubmissionContext,
  loadVoteCounts,
  requireSubmissionView,
} from '../services/submissions';
import {
  decideSubmission,
} from '../business/voting';
import { awardAcceptedSubmission } from '../services/weeks';
import { pushDecision } from '../push';

const app = new Hono<AppEnv>();
app.use('*', requireAuth);

const voteSchema = z.object({ approve: z.boolean() }).strict();

/** GET /submissions/:id — group members only. */
app.get('/:id', async (c) => {
  const context = await loadSubmissionContext(c.env.DB, c.req.param('id'));
  if (!context) throw notFound('Submission not found');
  await requireGroupMembership(c.env.DB, context.groupId, c.get('user').id);
  return c.json({ submission: await requireSubmissionView(c.env.DB, context.submission.id, c.get('user').id) });
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

export default app;
