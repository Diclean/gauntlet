import { describe, expect, it } from 'vitest';
import { evaluateBucket, refillTokens } from '../src/middleware/rate-limit';

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
});
