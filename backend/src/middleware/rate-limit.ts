import type { MiddlewareHandler } from 'hono';
import type { AppEnv } from '../types';
import { tooManyRequests } from '../lib/errors';
import { sha256Hex } from '../lib/crypto';
import { nowSeconds } from '../lib/db';

/**
 * D1-backed token bucket. Keys are route-scoped and, for IPs, hashed so raw
 * addresses are never stored or logged.
 */

export interface BucketConfig {
  capacity: number;
  /** Tokens added per second. */
  refillPerSecond: number;
}

export interface BucketState {
  allowed: boolean;
  tokens: number;
  retryAfterSeconds: number;
}

export function refillTokens(
  tokens: number,
  updatedAt: number,
  now: number,
  config: BucketConfig,
): number {
  const elapsed = Math.max(0, now - updatedAt);
  return Math.min(config.capacity, Math.max(0, tokens) + elapsed * config.refillPerSecond);
}

export function evaluateBucket(
  tokens: number,
  updatedAt: number,
  now: number,
  config: BucketConfig,
): BucketState {
  const available = refillTokens(tokens, updatedAt, now, config);
  if (available >= 1) {
    return { allowed: true, tokens: available - 1, retryAfterSeconds: 0 };
  }
  const missing = 1 - available;
  const retryAfterSeconds = config.refillPerSecond > 0 ? missing / config.refillPerSecond : 60;
  return { allowed: false, tokens: available, retryAfterSeconds };
}

export async function consumeRateLimit(
  db: D1Database,
  key: string,
  config: BucketConfig,
  now: number = nowSeconds(),
): Promise<BucketState> {
  const row = await db
    .prepare('SELECT tokens, updated_at FROM rate_limits WHERE key = ?')
    .bind(key)
    .first<{ tokens: number; updated_at: number }>();

  const state = evaluateBucket(row?.tokens ?? config.capacity, row?.updated_at ?? now, now, config);
  const updatedAt = row ? Math.max(row.updated_at, now) : now;

  await db
    .prepare(
      `INSERT INTO rate_limits (key, tokens, updated_at) VALUES (?, ?, ?)
       ON CONFLICT(key) DO UPDATE SET tokens = excluded.tokens, updated_at = excluded.updated_at`,
    )
    .bind(key, state.tokens, updatedAt)
    .run();

  return state;
}

export interface RateLimitOptions extends BucketConfig {
  bucket: string;
  by: 'user' | 'ip';
}

export function rateLimit(options: RateLimitOptions): MiddlewareHandler<AppEnv> {
  return async (c, next) => {
    let identity: string;
    if (options.by === 'user') {
      identity = c.get('user').id;
    } else {
      const ip =
        c.req.header('cf-connecting-ip') ??
        c.req.header('x-forwarded-for')?.split(',')[0]?.trim() ??
        'unknown';
      identity = (await sha256Hex(ip)).slice(0, 24);
    }

    const state = await consumeRateLimit(
      c.env.DB,
      `${options.bucket}:${identity}`,
      options,
      nowSeconds(),
    );
    if (!state.allowed) {
      throw tooManyRequests('Too many requests, slow down a little', state.retryAfterSeconds);
    }
    await next();
  };
}
