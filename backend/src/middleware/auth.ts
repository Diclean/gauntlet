import type { MiddlewareHandler } from 'hono';
import { toPublicUser } from '../types';
import type { AppEnv } from '../types';
import { unauthorized } from '../lib/errors';
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
  await next();
};
