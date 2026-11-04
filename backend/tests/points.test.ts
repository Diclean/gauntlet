import { describe, expect, it } from 'vitest';
import {
  computeStreaks,
  firstAcceptedSubmission,
  firstFinishBonus,
  rankByPoints,
  streakBonus,
  weeklyWinnerIds,
  type AcceptedSubmissionRef,
  type WeekRef,
} from '../src/business/points';

function accepted(
  id: string,
  userId: string,
  decidedAt: number,
  createdAt = decidedAt,
): AcceptedSubmissionRef {
  return { id, userId, challengeId: 'c1', decidedAt, createdAt, points: 25 };
}

describe('first-to-finish bonus', () => {
  it('picks the earliest accepted submission', () => {
    const submissions = [accepted('s3', 'u3', 300), accepted('s1', 'u1', 100), accepted('s2', 'u2', 200)];
    expect(firstAcceptedSubmission(submissions)?.id).toBe('s1');
    expect(firstFinishBonus('s1', submissions)).toBe(10);
    expect(firstFinishBonus('s2', submissions)).toBe(0);
  });

  it('breaks decided_at ties deterministically by created_at then id', () => {
    const submissions = [accepted('s2', 'u2', 100, 50), accepted('s1', 'u1', 100, 40), accepted('s3', 'u3', 100, 50)];
    expect(firstAcceptedSubmission(submissions)?.id).toBe('s1');
    expect(firstFinishBonus('s3', submissions)).toBe(0);
  });

  it('has no bonus when nothing is accepted', () => {
    expect(firstAcceptedSubmission([])).toBeNull();
    expect(firstFinishBonus('s1', [])).toBe(0);
  });
});

describe('weekly winner', () => {
  it('awards every member tied for the highest weekly score', () => {
    const winners = weeklyWinnerIds([
      { userId: 'u1', points: 25 },
      { userId: 'u2', points: 50 },
      { userId: 'u3', points: 50 },
      { userId: 'u4', points: 10 },
    ]);
    expect(winners).toEqual(['u2', 'u3']);
  });

  it('sums multiple entries for the same member', () => {
    expect(
      weeklyWinnerIds([
        { userId: 'u1', points: 25 },
        { userId: 'u1', points: 25 },
        { userId: 'u2', points: 40 },
      ]),
    ).toEqual(['u1']);
  });

  it('has no winner when nobody scored', () => {
    expect(weeklyWinnerIds([])).toEqual([]);
    expect(weeklyWinnerIds([{ userId: 'u1', points: 0 }])).toEqual([]);
  });
});

describe('streak bonus', () => {
  it('is zero below two weeks', () => {
    expect(streakBonus(0)).toBe(0);
    expect(streakBonus(1)).toBe(0);
  });

  it('pays 5 per week, capped at 10 weeks', () => {
    expect(streakBonus(2)).toBe(10);
    expect(streakBonus(3)).toBe(15);
    expect(streakBonus(10)).toBe(50);
    expect(streakBonus(11)).toBe(50);
    expect(streakBonus(25)).toBe(50);
  });
});

describe('computeStreaks', () => {
  const weeks: WeekRef[] = [
    { id: 'w1', startsAt: 1_000 },
    { id: 'w2', startsAt: 1_000 + 7 * 86_400 },
    { id: 'w3', startsAt: 1_000 + 14 * 86_400 },
    { id: 'w4', startsAt: 1_000 + 21 * 86_400 },
  ];

  it('counts consecutive weeks ending at the current week', () => {
    const accepted = new Map<string, Set<string>>([
      ['w1', new Set(['alice', 'carol'])],
      ['w2', new Set(['alice', 'carol'])],
      ['w3', new Set(['alice'])],
      ['w4', new Set(['alice', 'bob'])],
    ]);
    const streaks = computeStreaks(weeks, accepted, 'w4', ['alice', 'bob', 'carol']);
    expect(streaks.get('alice')).toBe(4);
    expect(streaks.get('bob')).toBe(1);
    expect(streaks.get('carol')).toBe(0);
  });

  it('breaks on a missed week', () => {
    const accepted = new Map<string, Set<string>>([
      ['w1', new Set(['alice'])],
      ['w2', new Set(['alice'])],
      ['w4', new Set(['alice'])],
    ]);
    expect(computeStreaks(weeks, accepted, 'w4', ['alice']).get('alice')).toBe(1);
  });

  it('breaks when the week rows themselves have a gap', () => {
    const gapped: WeekRef[] = [
      { id: 'w1', startsAt: 1_000 },
      { id: 'w2', startsAt: 1_000 + 7 * 86_400 },
      { id: 'w3', startsAt: 1_000 + 21 * 86_400 },
    ];
    const accepted = new Map<string, Set<string>>([
      ['w1', new Set(['alice'])],
      ['w2', new Set(['alice'])],
      ['w3', new Set(['alice'])],
    ]);
    expect(computeStreaks(gapped, accepted, 'w3', ['alice']).get('alice')).toBe(1);
  });

  it('returns zeros for every member when the current week is missing', () => {
    const streaks = computeStreaks(weeks, new Map(), 'missing', ['alice', 'bob']);
    expect([...streaks.values()]).toEqual([0, 0]);
  });
});

describe('rankByPoints', () => {
  it('uses competition ranking with ties', () => {
    const ranked = rankByPoints([
      { user: 'a', points: 10 },
      { user: 'b', points: 30 },
      { user: 'c', points: 10 },
      { user: 'd', points: 20 },
    ]);
    expect(ranked.map((entry) => [entry.user, entry.rank])).toEqual([
      ['b', 1],
      ['d', 2],
      ['a', 3],
      ['c', 3],
    ]);
  });
});
