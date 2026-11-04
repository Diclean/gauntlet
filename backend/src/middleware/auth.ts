import type { MiddlewareHandler } from 'hono';
import { toPublicUser } from '../types';
import type { AppEnv } from '../types';
import { ApiError, unauthorized } from '../lib/errors';
import { findUserBySessionHash, hashSessionToken } from '../auth/session';
import { nowSeconds } from '../lib/db';

/** Every non-public endpoint uses this. Attaches the authenticated user + hash. */
export const requireAuth: MiddlewareHandler<AppEnv> = async (c, next) => {
  const header = c.req.header('authorization');
  if (!header) throw unauthorized();

  const match = /^Bearer\s+(\S+)$/i.exec(header.trim());
  if (!match?.[1]) throw unauthorized();

  const tokenHash = await hashSessionToken(match[1]);
  const user = await findUserBySessionHash(c.env.DB, tokenHash, nowSeconds());
  if (!user) throw unauthorized();

  c.set('user', toPublicUser(user));
  c.set('userRow', user);
  c.set('sessionTokenHash', tokenHash);

  // App Store 1.2 house-rules gate: every write except account management,
  // terms acceptance and logout (which must always work) requires acceptance.
  const method = c.req.method.toUpperCase();
  const isWrite = method !== 'GET' && method !== 'HEAD' && method !== 'OPTIONS';
  const termsExempt =
    c.req.path === '/me' ||
    c.req.path === '/me/accept-terms' ||
    c.req.path === '/auth/logout';
  if (isWrite && !termsExempt && !user.terms_accepted_at) {
    throw new ApiError(403, 'terms_required', 'Accept the house rules to continue');
  }

  await next();
};
