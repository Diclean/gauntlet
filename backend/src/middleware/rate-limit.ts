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

/**
 * Atomically refill + debit one token. The whole read-modify-write is a single
 * SQLite statement, so concurrent requests serialize on the row instead of all
 * observing the same pre-debit balance:
 *
 * - no row yet: INSERT a fresh bucket with `capacity - 1` tokens (allowed);
 * - existing row: DO UPDATE only when the refilled balance is >= 1, computing
 *   the refill and the debit in SQL and returning the post-debit balance.
 *
 * A conflicting insert takes the UPDATE branch, so the first-insert race is
 * safe too: exactly one statement can debit each token.
 */
export async function consumeRateLimit(
  db: D1Database,
  key: string,
  config: BucketConfig,
  now: number = nowSeconds(),
): Promise<BucketState> {
  const capacity = Math.max(1, config.capacity);
  const inserted = await db
    .prepare(
      `INSERT INTO rate_limits (key, tokens, updated_at) VALUES (?, ?, ?)
       ON CONFLICT(key) DO UPDATE SET
         tokens = MIN(?, MAX(0, rate_limits.tokens) + MAX(0, ? - rate_limits.updated_at) * ?) - 1,
         updated_at = MAX(rate_limits.updated_at, ?)
       WHERE MIN(?, MAX(0, rate_limits.tokens) + MAX(0, ? - rate_limits.updated_at) * ?) >= 1
       RETURNING tokens`,
    )
    .bind(
      key,
      capacity - 1,
      now,
      capacity,
      now,
      config.refillPerSecond,
      now,
      capacity,
      now,
      config.refillPerSecond,
    )
    .first<{ tokens: number }>();

  if (inserted) {
    return { allowed: true, tokens: inserted.tokens, retryAfterSeconds: 0 };
  }

  // Denied. This read only shapes Retry-After; the allow/deny decision above
  // was already made atomically.
  const row = await db
    .prepare('SELECT tokens, updated_at FROM rate_limits WHERE key = ?')
    .bind(key)
    .first<{ tokens: number; updated_at: number }>();
  const available = row ? refillTokens(row.tokens, row.updated_at, now, config) : 0;
  const retryAfterSeconds =
    config.refillPerSecond > 0
      ? Math.max(0, 1 - available) / config.refillPerSecond
      : 60;
  return { allowed: false, tokens: available, retryAfterSeconds };
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
      // Only Cloudflare's edge header is trusted. Clients can spoof
      // x-forwarded-for, so never consult it (fall back to one shared bucket).
      const ip = c.req.header('cf-connecting-ip') ?? 'unknown';
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
