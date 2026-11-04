import { Hono } from 'hono';
import { z } from 'zod';
import type { AppEnv } from '../types';
import { randomId } from '../lib/crypto';
import { nowSeconds } from '../lib/db';
import { requireAuth } from '../middleware/auth';
import { parseJsonBody } from '../middleware/validate';
import { rateLimit } from '../middleware/rate-limit';

const app = new Hono<AppEnv>();
app.use('*', requireAuth);

const deviceSchema = z
  .object({
    apnsToken: z
      .string()
      .trim()
      .min(16)
      .max(200)
      .regex(/^[A-Za-z0-9]+$/u, 'APNs token must be alphanumeric'),
  })
  .strict();

/** POST /devices — registers (or re-binds) a device token for this user. */
app.post(
  '/',
  rateLimit({ bucket: 'devices', capacity: 20, refillPerSecond: 20 / 60, by: 'user' }),
  async (c) => {
    const body = await parseJsonBody(c, deviceSchema);
    const token = body.apnsToken.toLowerCase();
    const now = nowSeconds();

    await c.env.DB.prepare(
      `INSERT INTO devices (id, user_id, apns_token, created_at)
       VALUES (?, ?, ?, ?)
       ON CONFLICT(apns_token) DO UPDATE SET user_id = excluded.user_id`,
    )
      .bind(randomId(), c.get('user').id, token, now)
      .run();

    return c.json({ ok: true });
  },
);

export default app;
