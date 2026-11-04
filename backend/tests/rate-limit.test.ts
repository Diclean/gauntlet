import { describe, expect, it } from 'vitest';
import { env } from 'cloudflare:test';
import {
  consumeRateLimit,
  evaluateBucket,
  refillTokens,
} from '../src/middleware/rate-limit';

describe('token bucket', () => {
  const bucket = { capacity: 10, refillPerSecond: 1 };

  it('allows a token and consumes it', () => {
    const state = evaluateBucket(10, 100, 100, bucket);
    expect(state.allowed).toBe(true);
    expect(state.tokens).toBe(9);
  });

  it('caps refill at capacity', () => {
    expect(refillTokens(9, 0, 10_000, bucket)).toBe(10);
  });

  it('refills at the configured rate', () => {
    expect(refillTokens(0, 100, 105, bucket)).toBe(5);
  });

  it('denies when empty and reports the wait', () => {
    const state = evaluateBucket(0, 100, 100, bucket);
    expect(state.allowed).toBe(false);
    expect(state.retryAfterSeconds).toBe(1);
  });

  it('denies forever-ish when there is no refill', () => {
    const state = evaluateBucket(0, 100, 200, { capacity: 10, refillPerSecond: 0 });
    expect(state.allowed).toBe(false);
    expect(state.retryAfterSeconds).toBe(60);
  });

  it('atomically allows exactly capacity concurrent debits', async () => {
    // Regression: the old SELECT-then-upsert let every concurrent request
    // observe the same balance and pass. With capacity 5, 20 simultaneous
    // calls may allow exactly 5.
    const key = `concurrent:${crypto.randomUUID()}`;
    const config = { capacity: 5, refillPerSecond: 0 };
    const states = await Promise.all(
      Array.from({ length: 20 }, () => consumeRateLimit(env.DB, key, config, 1_000)),
    );
    expect(states.filter((state) => state.allowed)).toHaveLength(5);

    const stored = await env.DB.prepare('SELECT tokens FROM rate_limits WHERE key = ?')
      .bind(key)
      .first<{ tokens: number }>();
    expect(stored?.tokens).toBe(0);
  });
});
