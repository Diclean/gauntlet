import { Hono } from 'hono';
import type { AppEnv } from '../types';
import { first, nowSeconds } from '../lib/db';
import { randomId } from '../lib/crypto';
import {
  ApiError,
  badRequest,
  conflict,
  lengthRequired,
  notFound,
  payloadTooLarge,
  quotaExceeded,
} from '../lib/errors';
import { requireAuth } from '../middleware/auth';
import { rateLimit } from '../middleware/rate-limit';
import { runInBackground } from '../middleware/background';
import { countMembers, getGroupRow, requireGroupMembership } from '../services/groups';
import { loadSubmissionView } from '../services/submissions';
import { deleteSubmissionMedia } from '../services/media';
import {
  getChallengeRow,
  getWeekRow,
  toggleVeto,
} from '../services/fixtures';
import { challengeWithMyStatus } from '../services/weeks';
import { pushFixtureVetoed, pushNewSubmission } from '../push';

const app = new Hono<AppEnv>();
app.use('*', requireAuth);

const PHOTO_MAX_BYTES = 10 * 1024 * 1024;
const VIDEO_MAX_BYTES = 50 * 1024 * 1024;
const FORM_OVERHEAD_BYTES = 1024 * 1024;
/** Rolling 24h upload cap per member, independent of the short-burst bucket. */
const UPLOAD_QUOTA_PER_DAY = 30;
const UPLOAD_QUOTA_WINDOW_SECONDS = 24 * 60 * 60;

const PHOTO_TYPES: Record<string, string> = {
  'image/jpeg': 'jpg',
  'image/jpg': 'jpg',
  'image/heic': 'heic',
  'image/heif': 'heif',
};

const VIDEO_TYPES: Record<string, string> = {
  'video/mp4': 'mp4',
  'video/quicktime': 'mov',
};

interface ChallengeContextRow {
  id: string;
  title: string;
  points: number;
  week_id: string;
  group_id: string;
  starts_at: number;
  ends_at: number;
  vote_deadline: number;
  week_status: 'open' | 'closed';
  vetoed_at: number | null;
}

/**
 * POST /challenges/:id/submissions — multipart/form-data upload.
 * Fields: media (file), mediaType (photo|video), caption (optional).
 * Enforces camera-proof MIME allowlists + size limits server-side, stores under
 * a random UUID key, and records eligible_voters = memberCount - 1.
 */
app.post(
  '/:id/submissions',
  rateLimit({ bucket: 'submit', capacity: 20, refillPerSecond: 20 / 300, by: 'user' }),
  async (c) => {
    const userId = c.get('user').id;
    const now = nowSeconds();

    const challenge = await first<ChallengeContextRow>(
      c.env.DB.prepare(
        `SELECT c.id, c.title, c.points, c.week_id, c.vetoed_at,
                w.group_id, w.starts_at, w.ends_at, w.vote_deadline,
                w.status AS week_status
           FROM challenges c
           JOIN weeks w ON w.id = c.week_id
          WHERE c.id = ?`,
      ).bind(c.req.param('id')),
    );
    if (!challenge || challenge.vetoed_at !== null) throw notFound('Challenge not found');

    await requireGroupMembership(c.env.DB, challenge.group_id, userId);

    if (challenge.week_status !== 'open' || now < challenge.starts_at || now > challenge.ends_at) {
      throw conflict('week_closed', 'Submissions are closed for this week');
    }

    const existing = await first<{ status: string }>(
      c.env.DB.prepare(
        `SELECT status FROM submissions
          WHERE challenge_id = ? AND user_id = ? AND status IN ('pending', 'accepted')
          LIMIT 1`,
      ).bind(challenge.id, userId),
    );
    if (existing?.status === 'accepted') {
      throw conflict('already_accepted', 'This challenge is already completed');
    }
    if (existing?.status === 'pending') {
      throw conflict('submission_pending', 'A proof is already waiting for votes');
    }

    // Multpart bodies must declare their length up front: without a numeric
    // Content-Length we cannot reject an oversized upload before buffering the
    // whole form in memory. The post-buffer `media.size` check stays below.
    const rawContentLength = c.req.header('content-length');
    if (rawContentLength === undefined || !/^\d+$/u.test(rawContentLength)) {
      throw lengthRequired('A numeric Content-Length header is required for uploads');
    }
    const contentLength = Number(rawContentLength);
    if (contentLength > VIDEO_MAX_BYTES + FORM_OVERHEAD_BYTES) {
      throw payloadTooLarge('Upload is too large');
    }

    const recentUploads = await first<{ count: number; oldest: number | null }>(
      c.env.DB.prepare(
        `SELECT COUNT(*) AS count, MIN(created_at) AS oldest
           FROM submissions
          WHERE user_id = ? AND created_at > ?`,
      ).bind(userId, now - UPLOAD_QUOTA_WINDOW_SECONDS),
    );
    if ((recentUploads?.count ?? 0) >= UPLOAD_QUOTA_PER_DAY) {
      const retryAfter = (recentUploads?.oldest ?? now) + UPLOAD_QUOTA_WINDOW_SECONDS - now;
      throw quotaExceeded(
        'upload_quota',
        'You have reached the daily upload limit',
        retryAfter,
      );
    }

    let form: FormData;
    try {
      form = await c.req.formData();
    } catch {
      throw badRequest('invalid_multipart', 'Expected multipart/form-data');
    }

    const allowedFields = new Set(['media', 'mediaType', 'caption']);
    for (const key of form.keys()) {
      if (!allowedFields.has(key)) throw badRequest('validation_error', `Unknown field: ${key}`);
    }

    const media = form.get('media');
    const mediaTypeValue = form.get('mediaType');
    const captionValue = form.get('caption');

    if (!(media instanceof File)) {
      throw badRequest('validation_error', 'media: a camera photo or video file is required');
    }
    if (mediaTypeValue !== 'photo' && mediaTypeValue !== 'video') {
      throw badRequest('validation_error', 'mediaType: must be "photo" or "video"');
    }
    if (captionValue !== null && typeof captionValue !== 'string') {
      throw badRequest('validation_error', 'caption: must be text');
    }

    const caption = typeof captionValue === 'string' ? captionValue.trim() : '';
    if (caption.length > 200) {
      throw badRequest('validation_error', 'caption: must be at most 200 characters');
    }

    const mime = (media.type || '').toLowerCase();
    const typeMap = mediaTypeValue === 'photo' ? PHOTO_TYPES : VIDEO_TYPES;
    const extension = typeMap[mime];
    if (!extension) {
      throw new ApiError(
        415,
        'unsupported_media_type',
        mediaTypeValue === 'photo'
          ? 'Photos must be JPEG or HEIC'
          : 'Videos must be MP4 or MOV',
      );
    }

    const maxBytes = mediaTypeValue === 'photo' ? PHOTO_MAX_BYTES : VIDEO_MAX_BYTES;
    if (media.size <= 0) throw badRequest('validation_error', 'media: file is empty');
    if (media.size > maxBytes) {
      throw payloadTooLarge(
        mediaTypeValue === 'photo'
          ? 'Photo must be at most 10 MB'
          : 'Video must be at most 50 MB (and at most 30 seconds)',
      );
    }

    const members = await first<{ count: number }>(
      c.env.DB.prepare('SELECT COUNT(*) AS count FROM group_members WHERE group_id = ?').bind(
        challenge.group_id,
      ),
    );
    const eligibleVoters = Math.max(0, (members?.count ?? 1) - 1);

    const submissionId = randomId();
    const mediaKey = `${submissionId}.${extension}`;

    const buffer = await media.arrayBuffer();
    if (buffer.byteLength > maxBytes) throw payloadTooLarge('Upload is too large');

    await c.env.MEDIA.put(mediaKey, buffer, {
      httpMetadata: { contentType: mime },
    });

    try {
      await c.env.DB.prepare(
        `INSERT INTO submissions
           (id, challenge_id, user_id, media_key, media_type, caption, status,
            eligible_voters, created_at, decided_at)
         VALUES (?, ?, ?, ?, ?, ?, 'pending', ?, ?, NULL)`,
      )
        .bind(
          submissionId,
          challenge.id,
          userId,
          mediaKey,
          mediaTypeValue,
          caption.length > 0 ? caption : null,
          eligibleVoters,
          now,
        )
        .run();
    } catch (error) {
      await deleteSubmissionMedia(c.env, mediaKey);
      if (error instanceof Error && /unique|constraint/iu.test(error.message)) {
        throw conflict('submission_pending', 'A proof is already waiting for votes');
      }
      throw error;
    }

    const submission = await loadSubmissionView(c.env.DB, submissionId, userId);
    if (!submission) throw new Error('submission_missing_after_insert');

    runInBackground(
      c,
      pushNewSubmission(c.env, challenge.group_id, userId, challenge.title, submissionId),
    );

    return c.json({ submission }, 201);
  },
);

/**
 * POST /challenges/:id/veto — toggle my veto on a current-week fixture. At the
 * threshold the fixture is replaced in place (max twice per club per week).
 */
app.post('/:id/veto', rateLimit({ bucket: 'veto', capacity: 30, refillPerSecond: 30 / 300, by: 'user' }), async (c) => {
  const userId = c.get('user').id;
  const now = nowSeconds();

  const challenge = await getChallengeRow(c.env.DB, c.req.param('id'));
  if (!challenge || challenge.vetoed_at !== null) throw notFound('Challenge not found');

  const week = await getWeekRow(c.env.DB, challenge.week_id);
  if (!week) throw notFound('Challenge not found');
  const group = await getGroupRow(c.env.DB, week.group_id);
  if (!group) throw notFound('Challenge not found');
  await requireGroupMembership(c.env.DB, group.id, userId);

  if (week.status !== 'open' || now < week.starts_at || now > week.ends_at) {
    throw conflict('week_closed', 'Vetoes are only open during the current week');
  }

  const memberCount = await countMembers(c.env.DB, group.id);
  const result = await toggleVeto(c.env, {
    challenge,
    week,
    group,
    userId,
    memberCount,
    now,
  });

  const json = await challengeWithMyStatus(
    c.env.DB,
    result.challengeId,
    userId,
    memberCount,
    now,
  );
  if (!json) throw new Error('challenge_missing_after_veto');

  if (result.replaced) {
    runInBackground(c, pushFixtureVetoed(c.env, group.id, challenge.position));
  }

  return c.json({ challenge: json, replaced: result.replaced });
});

export default app;
