import { Hono } from 'hono';
import type { AppEnv } from '../types';
import { first, nowSeconds } from '../lib/db';
import { badRequest, notFound } from '../lib/errors';
import { requireAuth } from '../middleware/auth';
import { rateLimit } from '../middleware/rate-limit';
import { blockUser, unblockUser } from '../services/moderation';

const app = new Hono<AppEnv>();
app.use('*', requireAuth);

/** POST /users/:id/block — one-way and silent. Idempotent. */
app.post('/:id/block', rateLimit({ bucket: 'block', capacity: 30, refillPerSecond: 30 / 300, by: 'user' }), async (c) => {
  const userId = c.get('user').id;
  const targetId = c.req.param('id');
  if (targetId === userId) throw badRequest('validation_error', 'You cannot block yourself');

  const target = await first<{ id: string }>(
    c.env.DB.prepare('SELECT id FROM users WHERE id = ?').bind(targetId),
  );
  if (!target) throw notFound('User not found');

  await blockUser(c.env.DB, userId, targetId, nowSeconds());
  return c.json({ ok: true });
});

/** DELETE /users/:id/block — lifts my block. Idempotent. */
app.delete('/:id/block', rateLimit({ bucket: 'unblock', capacity: 30, refillPerSecond: 30 / 300, by: 'user' }), async (c) => {
  const userId = c.get('user').id;
  const targetId = c.req.param('id');
  if (targetId === userId) throw badRequest('validation_error', 'You cannot block yourself');
  await unblockUser(c.env.DB, userId, targetId);
  return c.json({ ok: true });
});

export default app;
