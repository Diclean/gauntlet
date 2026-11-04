import { beforeEach, describe, expect, it } from 'vitest';
import { env } from 'cloudflare:test';
import { app } from '../src';
import { playerOfTheMonthStats } from '../src/business/awards';
import {
  GROUP,
  TOKEN_1,
  TOKEN_2,
  U1,
  U2,
  auth,
  insertChallenge,
  insertGroup,
  insertMember,
  insertMonthlyAward,
  insertPointEvent,
  insertSession,
  insertSubmission,
  insertUser,
  insertWeek,
  resetDb,
} from './fixtures';

/** Player of the Month stats on the awards read path. */

const JOINED = 1_733_011_200; // Sun 2024-12-01 00:00 UTC
const JAN_W1 = 1_736_121_600; // Mon 2025-01-06
const JAN_W2 = 1_736_726_400; // Mon 2025-01-13
const WEEK_SECONDS = 7 * 86_400;
const VOTE_GRACE_SECONDS = 12 * 3_600;

async function insertWeekAt(id: string, startsAt: number, number: number): Promise<void> {
  await insertWeek(env.DB, GROUP, id, 'closed', {
    startsAt,
    endsAt: startsAt + WEEK_SECONDS - 1,
    voteDeadline: startsAt + WEEK_SECONDS + VOTE_GRACE_SECONDS,
    number,
  });
}

async function seed(): Promise<void> {
  await resetDb(env.DB);
  await insertUser(env.DB, U1, 'Alice', '🦊');
  await insertUser(env.DB, U2, 'Bob', '🐻');
  await insertSession(env.DB, U1, TOKEN_1);
  await insertSession(env.DB, U2, TOKEN_2);

  await insertGroup(env.DB, GROUP, U1, 'ABC234', 'Dares FC');
  await insertMember(env.DB, GROUP, U1, JOINED);
  await insertMember(env.DB, GROUP, U2, JOINED);

  await insertWeekAt('jan-w1', JAN_W1, 1);
  await insertWeekAt('jan-w2', JAN_W2, 2);
  await insertChallenge(env.DB, 'jan-w1', 'jan-c1', 50);
  await insertChallenge(env.DB, 'jan-w2', 'jan-c2', 30);

  // Goals: Alice 2, Bob 1. Red cards: Alice 2, Bob 1.
  await insertSubmission(env.DB, {
    id: 'jan-s1',
    challengeId: 'jan-c1',
    userId: U1,
    status: 'accepted',
  });
  await insertSubmission(env.DB, {
    id: 'jan-s2',
    challengeId: 'jan-c2',
    userId: U1,
    status: 'accepted',
  });
  await insertSubmission(env.DB, {
    id: 'jan-s3',
    challengeId: 'jan-c2',
    userId: U2,
    status: 'accepted',
  });
  await insertSubmission(env.DB, {
    id: 'jan-s4',
    challengeId: 'jan-c1',
    userId: U1,
    status: 'rejected',
  });
  await insertSubmission(env.DB, {
    id: 'jan-s5',
    challengeId: 'jan-c2',
    userId: U1,
    status: 'rejected',
  });
  await insertSubmission(env.DB, {
    id: 'jan-s6',
    challengeId: 'jan-c1',
    userId: U2,
    status: 'rejected',
  });

  // Alice: 60 points in week 1, 40 in week 2, plus the +50 monthly bonus on
  // week 2 that must not inflate `points` or `bestWeek`.
  await insertPointEvent(env.DB, {
    weekId: 'jan-w1',
    userId: U1,
    points: 50,
    submissionId: 'jan-s1',
  });
  await insertPointEvent(env.DB, {
    weekId: 'jan-w1',
    userId: U1,
    kind: 'first_bonus',
    points: 10,
    submissionId: 'jan-s1',
  });
  await insertPointEvent(env.DB, {
    weekId: 'jan-w2',
    userId: U1,
    points: 30,
    submissionId: 'jan-s2',
  });
  await insertPointEvent(env.DB, {
    weekId: 'jan-w2',
    userId: U1,
    kind: 'first_bonus',
    points: 10,
    submissionId: 'jan-s2',
  });
  await insertPointEvent(env.DB, {
    weekId: 'jan-w2',
    userId: U1,
    kind: 'monthly_award',
    points: 50,
  });

  // Bob: 25 points in the month.
  await insertPointEvent(env.DB, {
    weekId: 'jan-w1',
    userId: U2,
    points: 20,
    submissionId: 'jan-s3',
  });
  await insertPointEvent(env.DB, {
    weekId: 'jan-w2',
    userId: U2,
    kind: 'first_bonus',
    points: 5,
    submissionId: 'jan-s3',
  });

  await insertMonthlyAward(env.DB, {
    month: '2025-01',
    award: 'golden_boot',
    userId: U1,
    value: 2,
  });
  await insertMonthlyAward(env.DB, {
    month: '2025-01',
    award: 'player_of_the_month',
    userId: U1,
    value: 100,
  });
  await insertMonthlyAward(env.DB, {
    month: '2025-01',
    award: 'wooden_spoon',
    userId: U2,
    value: 25,
  });
}

beforeEach(seed);

describe('playerOfTheMonthStats', () => {
  it('reads every stat from the month aggregates, best week included', () => {
    const stats = playerOfTheMonthStats(
      {
        month: '2025-01',
        memberIds: [U1, U2],
        presentAllMonth: new Set([U1, U2]),
        points: new Map([
          [U1, 100],
          [U2, 25],
        ]),
        acceptedSubmissions: new Map([
          [U1, 2],
          [U2, 1],
        ]),
        rejectedSubmissions: new Map([
          [U1, 2],
          [U2, 1],
        ]),
        rejectionVotes: new Map(),
        firstBonuses: new Map([
          [U1, 2],
          [U2, 1],
        ]),
        pointsByWeek: new Map([
          [
            U1,
            new Map([
              ['jan-w1', 60],
              ['jan-w2', 40],
            ]),
          ],
          [U2, new Map([['jan-w1', 20]])],
        ]),
        rankAtStart: new Map([[U1, 1]]),
        rankAtEnd: new Map([[U1, 1]]),
      },
      U1,
    );

    expect(stats).toEqual({
      points: 100,
      goals: 2,
      redCards: 2,
      firstToScore: 2,
      bestWeek: 60,
    });
  });

  it('returns zeroes for a member with no activity', () => {
    const stats = playerOfTheMonthStats(
      {
        month: '2025-01',
        memberIds: [U1],
        presentAllMonth: new Set([U1]),
        points: new Map(),
        acceptedSubmissions: new Map(),
        rejectedSubmissions: new Map(),
        rejectionVotes: new Map(),
        firstBonuses: new Map(),
        pointsByWeek: new Map(),
        rankAtStart: new Map(),
        rankAtEnd: new Map(),
      },
      U1,
    );

    expect(stats).toEqual({
      points: 0,
      goals: 0,
      redCards: 0,
      firstToScore: 0,
      bestWeek: 0,
    });
  });
});

describe('GET /groups/:id/awards stats', () => {
  it('returns the seeded month stats on Player of the Month only', async () => {
    const response = await app.request(
      `/groups/${GROUP}/awards?month=2025-01`,
      { headers: auth(TOKEN_1) },
      env,
    );
    expect(response.status).toBe(200);

    const body = (await response.json()) as {
      month: string;
      awards: Array<{
        award: string;
        value: number;
        stats?: Record<string, number>;
      }>;
    };

    expect(body.month).toBe('2025-01');
    const player = body.awards.find((award) => award.award === 'player_of_the_month')!;
    expect(player.value).toBe(100);
    expect(player.stats).toEqual({
      points: 100,
      goals: 2,
      redCards: 2,
      firstToScore: 2,
      bestWeek: 60,
    });

    const others = body.awards.filter((award) => award.award !== 'player_of_the_month');
    expect(others.length).toBeGreaterThan(0);
    for (const award of others) {
      expect(award).not.toHaveProperty('stats');
    }
  });
});
