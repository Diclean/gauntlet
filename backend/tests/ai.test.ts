import { describe, expect, it, vi } from 'vitest';
import type { Env } from '../src/types';
import {
  buildChallengePrompt,
  fallbackChallenges,
  generateChallenges,
  parseChallengesPayload,
} from '../src/deepseek';
import { DIFFICULTY_POINTS } from '../src/business/points';

const envWithKey = (key: string | undefined = 'test-key'): Env =>
  ({ DEEPSEEK_API_KEY: key, APPLE_BUNDLE_ID: 'com.mathys.dares' }) as unknown as Env;

function deepseekResponse(challenges: unknown, status = 200): Response {
  return new Response(
    JSON.stringify({ choices: [{ message: { content: JSON.stringify({ challenges }) } }] }),
    { status, headers: { 'content-type': 'application/json' } },
  );
}

const validDrafts = [
  { title: 'Dare one', description: 'Do one.', difficulty: 'easy' },
  { title: 'Dare two', description: 'Do two.', difficulty: 'medium' },
  { title: 'Dare three', description: 'Do three.', difficulty: 'hard' },
  { title: 'Dare four', description: 'Do four.', difficulty: 'easy' },
  { title: 'Dare five', description: 'Do five.', difficulty: 'medium' },
];

describe('AI output validation', () => {
  it('clamps title/description, lowercases difficulty and de-duplicates', () => {
    const parsed = parseChallengesPayload(
      {
        challenges: [
          { title: `  ${'T'.repeat(200)}  `, description: 'D'.repeat(500), difficulty: 'HARD' },
          { title: 'Dare one', description: 'ok', difficulty: 'easy', extra: 'ignored' },
          { title: 'DARE ONE', description: 'duplicate', difficulty: 'medium' },
          { title: 'Bad', description: 'nope', difficulty: 'impossible' },
        ],
      },
      5,
    );
    expect(parsed).not.toBeNull();
    expect(parsed!.length).toBe(2);
    expect(parsed![0]!.title.length).toBe(80);
    expect(parsed![0]!.description.length).toBe(300);
    expect(parsed![0]!.difficulty).toBe('hard');
    expect(parsed![1]!.title).toBe('Dare one');
    expect(parsed![1]).not.toHaveProperty('extra');
  });

  it('accepts a bare array and rejects unusable roots', () => {
    expect(parseChallengesPayload([{ title: 'A', difficulty: 'easy' }], 1)?.length).toBe(1);
    expect(parseChallengesPayload({ nope: true }, 3)).toBeNull();
    expect(parseChallengesPayload('not json', 3)).toBeNull();
    expect(parseChallengesPayload({ challenges: 'nope' }, 3)).toBeNull();
  });

  it('requires exactly N items from the fallback pool', () => {
    for (const count of [3, 5, 10]) {
      const pool = fallbackChallenges(count, 'en');
      expect(pool.length).toBe(count);
      expect(new Set(pool.map((challenge) => challenge.title)).size).toBe(count);
      for (const challenge of pool) expect(DIFFICULTY_POINTS[challenge.difficulty]).toBeTruthy();
    }
  });

  it('falls back in French when the group language is fr', () => {
    const pool = fallbackChallenges(3, 'fr');
    expect(pool.length).toBe(3);
    expect(pool.some((challenge) => /Rejoue|pâtes|Apprends/iu.test(challenge.title))).toBe(true);
  });

  it('avoids previous titles in the fallback when possible', () => {
    const previous = fallbackChallenges(5, 'en').map((challenge) => challenge.title);
    const next = fallbackChallenges(5, 'en', previous);
    expect(next.length).toBe(5);
    for (const challenge of next) expect(previous).not.toContain(challenge.title);
  });

  it('always requests exactly N and includes theme/language/previous titles', () => {
    const prompt = buildChallengePrompt({
      count: 7,
      theme: 'food',
      language: 'fr',
      timezone: 'Europe/Paris',
      previousTitles: ['Old dare'],
    });
    expect(prompt).toContain('exactly 7');
    expect(prompt).toContain('French');
    expect(prompt).toContain('food');
    expect(prompt).toContain('Europe/Paris');
    expect(prompt).toContain('Old dare');
  });
});

describe('DeepSeek generation + fallback', () => {
  it('uses validated DeepSeek output when available', async () => {
    const fetchImpl = vi.fn(async () => deepseekResponse(validDrafts)) as unknown as typeof fetch;
    const result = await generateChallenges({
      env: envWithKey(),
      count: 5,
      theme: null,
      language: 'en',
      timezone: 'UTC',
      previousTitles: [],
      fetchImpl,
    });
    expect(result.source).toBe('deepseek');
    expect(result.challenges.map((challenge) => challenge.title)).toEqual(
      validDrafts.map((draft) => draft.title),
    );
  });

  it('tops up a short but valid AI response from the fallback pool', async () => {
    const fetchImpl = vi.fn(async () =>
      deepseekResponse([{ title: 'Only one', description: 'One.', difficulty: 'easy' }]),
    ) as unknown as typeof fetch;
    const result = await generateChallenges({
      env: envWithKey(),
      count: 5,
      theme: null,
      language: 'en',
      timezone: 'UTC',
      previousTitles: [],
      fetchImpl,
    });
    expect(result.source).toBe('deepseek');
    expect(result.challenges.length).toBe(5);
    expect(result.challenges[0]!.title).toBe('Only one');
  });

  it('falls back when the model returns invalid JSON', async () => {
    const fetchImpl = vi.fn(async () => {
      return new Response(
        JSON.stringify({ choices: [{ message: { content: 'not json at all' } }] }),
        { status: 200 },
      );
    }) as unknown as typeof fetch;
    const result = await generateChallenges({
      env: envWithKey(),
      count: 4,
      theme: 'outdoors',
      language: 'en',
      timezone: 'UTC',
      previousTitles: [],
      fetchImpl,
    });
    expect(result.source).toBe('fallback');
    expect(result.challenges.length).toBe(4);
  });

  it('falls back when every item is invalid', async () => {
    const fetchImpl = vi.fn(async () =>
      deepseekResponse([{ title: '', description: 'x', difficulty: 'extreme' }]),
    ) as unknown as typeof fetch;
    const result = await generateChallenges({
      env: envWithKey(),
      count: 3,
      theme: null,
      language: 'en',
      timezone: 'UTC',
      previousTitles: [],
      fetchImpl,
    });
    expect(result.source).toBe('fallback');
    expect(result.challenges.length).toBe(3);
  });

  it('falls back on HTTP errors and network failures', async () => {
    const failing = vi.fn(async () => new Response('nope', { status: 500 })) as unknown as typeof fetch;
    const thrown = vi.fn(async () => {
      throw new Error('network down');
    }) as unknown as typeof fetch;

    for (const fetchImpl of [failing, thrown]) {
      const result = await generateChallenges({
        env: envWithKey(),
        count: 2,
        theme: null,
        language: 'en',
        timezone: 'UTC',
        previousTitles: [],
        fetchImpl,
      });
      expect(result.source).toBe('fallback');
      expect(result.challenges.length).toBe(2);
    }
  });

  it('falls back without calling the network when the API key is missing', async () => {
    const fetchImpl = vi.fn() as unknown as typeof fetch;
    const result = await generateChallenges({
      env: { APPLE_BUNDLE_ID: 'com.mathys.dares' } as unknown as Env,
      count: 3,
      theme: null,
      language: 'en',
      timezone: 'UTC',
      previousTitles: [],
      fetchImpl,
    });
    expect(result.source).toBe('fallback');
    expect(result.challenges.length).toBe(3);
    expect(fetchImpl).not.toHaveBeenCalled();
  });
});
