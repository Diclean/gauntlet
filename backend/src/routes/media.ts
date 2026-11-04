import { Hono } from 'hono';
import type { AppEnv } from '../types';
import { first } from '../lib/db';
import { notFound } from '../lib/errors';
import { requireAuth } from '../middleware/auth';
import { requireGroupMembership } from '../services/groups';

const app = new Hono<AppEnv>();
app.use('*', requireAuth);

const KEY_PATTERN = /^[A-Za-z0-9._-]{1,128}$/u;

interface Range {
  start: number;
  end: number;
}

function parseRange(value: string, size: number): Range | null {
  const match = /^bytes=(\d*)-(\d*)$/u.exec(value.trim());
  if (!match) return null;
  const rawStart = match[1] ?? '';
  const rawEnd = match[2] ?? '';
  if (rawStart === '' && rawEnd === '') return null;
  if (size <= 0) return null;

  let start: number;
  let end: number;
  if (rawStart === '') {
    const suffixLength = Number(rawEnd);
    if (!Number.isInteger(suffixLength) || suffixLength <= 0) return null;
    start = Math.max(0, size - suffixLength);
    end = size - 1;
  } else {
    start = Number(rawStart);
    end = rawEnd === '' ? size - 1 : Number(rawEnd);
    if (!Number.isInteger(start) || !Number.isInteger(end)) return null;
    if (start > end || start >= size) return null;
    end = Math.min(end, size - 1);
  }
  return { start, end };
}

function baseHeaders(contentType: string, size: number, etag?: string): Headers {
  const headers = new Headers({
    'Content-Type': contentType,
    'Accept-Ranges': 'bytes',
    'Content-Length': String(size),
    'Cache-Control': 'private, no-store',
    'X-Content-Type-Options': 'nosniff',
  });
  if (etag) headers.set('ETag', etag);
  return headers;
}

/**
 * GET /media/:key — authenticated, membership-checked R2 streaming with
 * single-range support for video scrubbing. Media is never public.
 */
app.on(['GET', 'HEAD'], '/:key', async (c) => {
  const key = c.req.param('key');
  if (!KEY_PATTERN.test(key)) throw notFound('Media not found');

  const owner = await first<{ submission_id: string; group_id: string }>(
    c.env.DB.prepare(
      `SELECT s.id AS submission_id, w.group_id AS group_id
         FROM submissions s
         JOIN challenges c ON c.id = s.challenge_id
         JOIN weeks w ON w.id = c.week_id
        WHERE s.media_key = ?`,
    ).bind(key),
  );
  if (!owner) throw notFound('Media not found');

  // Non-members get 403, never bytes.
  await requireGroupMembership(c.env.DB, owner.group_id, c.get('user').id);

  const head = await c.env.MEDIA.head(key);
  if (!head) throw notFound('Media not found');

  const contentType = head.httpMetadata?.contentType ?? 'application/octet-stream';
  const totalSize = head.size;
  const rangeHeader = c.req.header('range');
  const method = c.req.method;

  if (rangeHeader) {
    const range = parseRange(rangeHeader, totalSize);
    if (!range) {
      return new Response(null, {
        status: 416,
        headers: {
          'Content-Range': `bytes */${totalSize}`,
          'Accept-Ranges': 'bytes',
          'Cache-Control': 'private, no-store',
        },
      });
    }

    const length = range.end - range.start + 1;
    const object = await c.env.MEDIA.get(key, {
      range: { offset: range.start, length },
    });
    if (!object) throw notFound('Media not found');

    const headers = baseHeaders(contentType, length, head.httpEtag);
    headers.set('Content-Range', `bytes ${range.start}-${range.end}/${totalSize}`);
    return new Response(method === 'HEAD' ? null : object.body, {
      status: 206,
      headers,
    });
  }

  const object = await c.env.MEDIA.get(key);
  if (!object) throw notFound('Media not found');

  return new Response(method === 'HEAD' ? null : object.body, {
    status: 200,
    headers: baseHeaders(contentType, totalSize, head.httpEtag),
  });
});

export default app;
