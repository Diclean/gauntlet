import { Hono } from 'hono';
import { z } from 'zod';
import type { AppEnv, UserRow } from '../types';
import { toPublicUser } from '../types';
import { first, nowSeconds } from '../lib/db';
import { randomId } from '../lib/crypto';
import { createSession } from '../auth/session';
import { verifyAppleIdentityToken } from '../auth/apple';
import { parseJsonBody } from '../middleware/validate';
import { rateLimit } from '../middleware/rate-limit';

const app = new Hono<AppEnv>();

const appleSignInSchema = z
  .object({
    identityToken: z.string().min(20).max(20_000),
    nonce: z.string().min(8).max(256),
    displayName: z.string().trim().min(1).max(40).optional(),
  })
  .strict();

/**
 * POST /auth/apple — verifies Apple's identity token (JWKS, iss, aud, exp,
 * nonce) then issues our own opaque session token, stored hashed.
 */
app.post(
  '/apple',
  rateLimit({ bucket: 'auth', capacity: 10, refillPerSecond: 10 / 60, by: 'ip' }),
  async (c) => {
    const body = await parseJsonBody(c, appleSignInSchema);
    const claims = await verifyAppleIdentityToken(c.env, body.identityToken, body.nonce);
    const now = nowSeconds();

    await c.env.DB.prepare(
      `INSERT INTO users (id, apple_sub, display_name, avatar_emoji, created_at)
       VALUES (?, ?, ?, NULL, ?)
       ON CONFLICT(apple_sub) DO NOTHING`,
    )
      .bind(randomId(), claims.sub, body.displayName ?? 'Player', now)
      .run();

    const user = await first<UserRow>(
      c.env.DB.prepare('SELECT * FROM users WHERE apple_sub = ?').bind(claims.sub),
    );
    if (!user) throw new Error('user_upsert_failed');

    const session = await createSession(c.env.DB, user.id, now);
    return c.json({ token: session.token, user: toPublicUser(user) });
  },
);

export default app;
