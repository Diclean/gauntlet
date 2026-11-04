import { Hono } from 'hono';
import type { AppEnv } from '../types';
import { first, nowSeconds } from '../lib/db';
import { randomId } from '../lib/crypto';
import { ApiError, badRequest, conflict, notFound, payloadTooLarge } from '../lib/errors';
import { requireAuth } from '../middleware/auth';
import { rateLimit } from '../middleware/rate-limit';
import { runInBackground } from '../middleware/background';
import { requireGroupMembership } from '../services/groups';
import { loadSubmissionView } from '../services/submissions';
import { pushNewSubmission } from '../push';

const app = new Hono<AppEnv>();
app.use('*', requireAuth);

const PHOTO_MAX_BYTES = 10 * 1024 * 1024;
const VIDEO_MAX_BYTES = 50 * 1024 * 1024;
const FORM_OVERHEAD_BYTES = 1024 * 1024;

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
        `SELECT c.id, c.title, c.points, c.week_id,
                w.group_id, w.starts_at, w.ends_at, w.vote_deadline,
                w.status AS week_status
           FROM challenges c
           JOIN weeks w ON w.id = c.week_id
          WHERE c.id = ?`,
      ).bind(c.req.param('id')),
    );
    if (!challenge) throw notFound('Challenge not found');

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

    const contentLength = Number(c.req.header('content-length') ?? '');
    if (Number.isFinite(contentLength) && contentLength > VIDEO_MAX_BYTES + FORM_OVERHEAD_BYTES) {
      throw payloadTooLarge('Upload is too large');
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
      await c.env.MEDIA.delete(mediaKey).catch(() => undefined);
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

export default app;
