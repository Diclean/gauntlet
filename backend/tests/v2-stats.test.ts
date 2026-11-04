import { beforeEach, describe, expect, it } from 'vitest';
import { env } from 'cloudflare:test';
import { app } from '../src';
import { buildRaceSeries, computeRaceMe } from '../src/business/race';
import {
  buildReceiptLines,
  pickManOfTheMatch,
  pickWoodenSpoon,
  rankTotals,
} from '../src/business/receipt';
import {
  GROUP,
  GROUP2,
  TOKEN_1,
  TOKEN_2,
  TOKEN_3,
  U1,
  U2,
  U3,
  auth,
  insertChallenge,
  insertGroup,
  insertMember,
  insertPointEvent,
  insertSession,
  insertSubmission,
  insertUser,
  insertWeek,
  resetDb,
} from './fixtures';

/** Title race + full-time receipt: pure shapes and the real endpoints. */

const JOINED = 1_733_011_200; // Sun 2024-12-01 00:00 UTC
const W0 = 1_736_121_600; // Mon 2025-01-06
const W1 = 1_736_726_400; // Mon 2025-01-13
const W2 = 1_737_331_200; // Mon 2025-01-20
const JOINED_MID = 1_736_812_800; // Tue 2025-01-14 00:00 UTC

const OUTSIDER = '44444444-4444-4444-8444-444444444444';
const TOKEN_4 = 'token-for-user-4-0123456789abcdef';

async function insertWeekAt(
  id: string,
  startsAt: number,
  number: number,
  status: 'open' | 'closed' = 'closed',
  groupId = GROUP,
): Promise<void> {
  await insertWeek(env.DB, groupId, id, status, {
    startsAt,
    endsAt: startsAt + 7 * 86_400 - 1,
    voteDeadline: startsAt + 7 * 86_400 + 12 * 3_600,
    number,
  });
}

async function seedUsersAndSessions(): Promise<void> {
  await insertUser(env.DB, U1, 'Alice', '🦊');
  await insertUser(env.DB, U2, 'Bob', '🐻');
  await insertUser(env.DB, U3, 'Mallory', '🐍');
  await insertSession(env.DB, U1, TOKEN_1);
  await insertSession(env.DB, U2, TOKEN_2);
  await insertSession(env.DB, U3, TOKEN_3);
}

describe('title race math', () => {
  it('aligns every series with the week list and zero-fills late joiners', () => {
    const result = buildRaceSeries(
      [
        { id: 'w1', number: 1, startsAt: 100 },
        { id: 'w2', number: 2, startsAt: 200 },
        { id: 'w3', number: 3, startsAt: 300 },
      ],
      [
        { user: { id: U1, displayName: 'Alice', avatarEmoji: null }, joinedAt: 50 },
        { user: { id: U2, displayName: 'Bob', avatarEmoji: null }, joinedAt: 250 },
      ],
      [
        { weekId: 'w1', userId: U1, points: 10 },
        { weekId: 'w2', userId: U1, points: 5 },
        { weekId: 'w3', userId: U2, points: 7 },
      ],
    );

    expect(result.weeks.map((week) => week.number)).toEqual([1, 2, 3]);
    const byUser = new Map(result.series.map((series) => [series.user.id, series]));
    expect(byUser.get(U1)!.perWeek).toEqual([10, 5, 0]);
    expect(byUser.get(U1)!.cumulative).toEqual([10, 15, 15]);
    expect(byUser.get(U2)!.perWeek).toEqual([0, 0, 7]);
    expect(byUser.get(U2)!.cumulative).toEqual([0, 0, 7]);

    const me = computeRaceMe(result, U2, 0);
    expect(me).toEqual({ bestWeek: { number: 3, points: 7 }, avgPerWeek: 2, streak: 0 });
  });
});

describe('race endpoint', () => {
  beforeEach(async () => {
    await resetDb(env.DB);
    await seedUsersAndSessions();
    await insertGroup(env.DB, GROUP, U1, 'ABC234', 'Dares FC');
    await insertMember(env.DB, GROUP, U1, JOINED);
    await insertMember(env.DB, GROUP, U2, JOINED_MID);

    await insertWeekAt('w1', W0, 1, 'closed');
    await insertWeekAt('w2', W1, 2, 'closed');
    await insertWeekAt('w3', W2, 3, 'open');

    await insertPointEvent(env.DB, { weekId: 'w1', userId: U1, points: 10 });
    await insertPointEvent(env.DB, { weekId: 'w2', userId: U1, points: 20 });
    await insertPointEvent(env.DB, { weekId: 'w2', userId: U2, points: 5 });
    await insertPointEvent(env.DB, { weekId: 'w3', userId: U2, points: 7 });

    await insertChallenge(env.DB, 'w3', 'c-race', 10);
    await insertSubmission(env.DB, {
      id: 's-race',
      challengeId: 'c-race',
      userId: U2,
      status: 'accepted',
    });
  });

  it('returns aligned cumulative series and my summary to members', async () => {
    const response = await app.request(
      `/groups/${GROUP}/stats/race`,
      { headers: auth(TOKEN_2) },
      env,
    );
    expect(response.status).toBe(200);
    const body = (await response.json()) as {
      weeks: Array<{ id: string; number: number; startsAt: number }>;
      series: Array<{
        user: { id: string };
        cumulative: number[];
        perWeek: number[];
      }>;
      me: { bestWeek: { number: number; points: number }; avgPerWeek: number; streak: number };
    };

    expect(body.weeks.map((week) => week.number)).toEqual([1, 2, 3]);
    const byUser = new Map(body.series.map((series) => [series.user.id, series]));
    expect(byUser.get(U1)!.cumulative).toEqual([10, 30, 30]);
    expect(byUser.get(U1)!.perWeek).toEqual([10, 20, 0]);
    expect(byUser.get(U2)!.cumulative).toEqual([0, 5, 12]);
    expect(byUser.get(U2)!.perWeek).toEqual([0, 5, 7]);
    expect(body.me).toEqual({ bestWeek: { number: 3, points: 7 }, avgPerWeek: 4, streak: 1 });
  });

  it('blocks non-members with 403', async () => {
    const response = await app.request(
      `/groups/${GROUP}/stats/race`,
      { headers: auth(TOKEN_3) },
      env,
    );
    expect(response.status).toBe(403);
  });
});

describe('receipt lines math', () => {
  it('strikes rejected lines, keeps one line per challenge and aggregates bonuses', () => {
    const lines = buildReceiptLines(
      [
        {
          challengeId: 'c1',
          challengeTitle: 'Score a Panenka',
          status: 'rejected',
          points: 25,
        },
        {
          challengeId: 'c1',
          challengeTitle: 'Score a Panenka',
          status: 'accepted',
          points: 25,
        },
        {
          challengeId: 'c2',
          challengeTitle: 'Club badge',
          status: 'rejected',
          points: 10,
        },
        {
          challengeId: 'c3',
          challengeTitle: 'Ref a match',
          status: 'expired',
          points: 50,
        },
        {
          challengeId: 'c4',
          challengeTitle: 'Quiz night',
          status: 'pending',
          points: 10,
        },
      ],
      [
        { kind: 'first_bonus', points: 10 },
        { kind: 'first_bonus', points: 10 },
        { kind: 'weekly_winner', points: 50 },
      ],
    );

    expect(lines).toEqual([
      { label: 'Score a Panenka', points: 25, struck: false },
      { label: 'Club badge · VAR: NO GOAL', points: 0, struck: true },
      { label: 'Ref a match · VAR: NO GOAL', points: 0, struck: true },
      { label: 'Quiz night', points: 0, struck: false },
      { label: 'First to finish', points: 20, struck: false },
      { label: 'Weekly winner', points: 50, struck: false },
    ]);
  });

  it('ranks ties equally and picks deterministic match/spoon recipients', () => {
    const ranks = rankTotals(
      new Map([
        ['a', 10],
        ['b', 10],
        ['c', 5],
      ]),
    );
    expect(ranks.get('a')).toEqual({ rank: 1, total: 10 });
    expect(ranks.get('b')).toEqual({ rank: 1, total: 10 });
    expect(ranks.get('c')).toEqual({ rank: 3, total: 5 });

    expect(pickManOfTheMatch(new Map([['a', 5], ['b', 5]]), ['b', 'a'])).toBe('a');
    expect(pickWoodenSpoon(new Map([['a', 5], ['b', 5]]), ['b', 'a'])).toBe('a');
    expect(pickWoodenSpoon(new Map([['a', 5]]), ['a'])).toBeNull();
  });
});

describe('receipt endpoint', () => {
  beforeEach(async () => {
    await resetDb(env.DB);
    await seedUsersAndSessions();
    await insertUser(env.DB, OUTSIDER, 'Outsider');
    await insertSession(env.DB, OUTSIDER, TOKEN_4);
    await insertGroup(env.DB, GROUP, U1, 'ABC234', 'Dares FC', 'Kit duty 🧺');
    await insertGroup(env.DB, GROUP2, U2, 'XYZ789', 'Other club');
    await insertMember(env.DB, GROUP, U1, JOINED);
    await insertMember(env.DB, GROUP, U2, JOINED);
    await insertMember(env.DB, GROUP, U3, JOINED);
    await insertMember(env.DB, GROUP2, U2, JOINED);

    await insertWeekAt('w0', W0, 1);
    await insertWeekAt('w1', W1, 2);
    await insertWeekAt('other-w', W1, 1, 'closed', GROUP2);

    await insertChallenge(env.DB, 'w0', 'c0', 50);
    await insertChallenge(env.DB, 'w1', 'c1', 50);
    await insertChallenge(env.DB, 'w1', 'c2', 10);
    await insertChallenge(env.DB, 'w1', 'c3', 50);
    await insertChallenge(env.DB, 'w1', 'c4', 10);

    await insertSubmission(env.DB, { id: 's1', challengeId: 'c1', userId: U1, status: 'accepted' });
    await insertSubmission(env.DB, { id: 's2', challengeId: 'c2', userId: U1, status: 'rejected' });
    await insertSubmission(env.DB, { id: 's3', challengeId: 'c3', userId: U2, status: 'accepted' });
    await insertSubmission(env.DB, { id: 's4', challengeId: 'c4', userId: U1, status: 'pending' });

    // Before the receipt week: U2 leads, U1 is second.
    await insertPointEvent(env.DB, { weekId: 'w0', userId: U2, points: 100 });
    await insertPointEvent(env.DB, { weekId: 'w0', userId: U1, points: 50 });

    // Receipt week: U1 110, U2 50.
    await insertPointEvent(env.DB, {
      weekId: 'w1',
      userId: U1,
      points: 50,
      submissionId: 's1',
    });
    await insertPointEvent(env.DB, {
      weekId: 'w1',
      userId: U1,
      kind: 'first_bonus',
      points: 10,
      submissionId: 's1',
    });
    await insertPointEvent(env.DB, {
      weekId: 'w1',
      userId: U1,
      kind: 'weekly_winner',
      points: 50,
    });
    await insertPointEvent(env.DB, {
      weekId: 'w1',
      userId: U2,
      points: 50,
      submissionId: 's3',
    });
  });

  it('returns lines, bonuses, rank delta and match/spoon picks', async () => {
    const response = await app.request(
      `/groups/${GROUP}/weeks/w1/receipt`,
      { headers: auth(TOKEN_1) },
      env,
    );
    expect(response.status).toBe(200);
    const body = (await response.json()) as {
      week: { id: string; number: number; startsAt: number; endsAt: number };
      club: { name: string; forfeit: string };
      player: { user: { id: string }; rank: number; rankDelta: number; total: number };
      lines: Array<{ label: string; points: number; struck: boolean }>;
      manOfTheMatch: { id: string } | null;
      woodenSpoon: { id: string } | null;
    };

    expect(body.week).toMatchObject({ id: 'w1', number: 2, startsAt: W1 });
    expect(body.club).toEqual({ name: 'Dares FC', forfeit: 'Kit duty 🧺' });
    expect(body.player).toMatchObject({ rank: 1, rankDelta: 1, total: 160 });
    expect(body.player.user.id).toBe(U1);
    expect(body.lines).toEqual([
      { label: 'Test challenge', points: 50, struck: false },
      { label: 'Test challenge · VAR: NO GOAL', points: 0, struck: true },
      { label: 'Test challenge', points: 0, struck: false },
      { label: 'First to finish', points: 10, struck: false },
      { label: 'Weekly winner', points: 50, struck: false },
    ]);
    expect(body.manOfTheMatch?.id).toBe(U1);
    expect(body.woodenSpoon?.id).toBe(U3);
  });

  it('lists weeks newest first with matchweek numbers and rejects bad limits', async () => {
    const response = await app.request(
      `/groups/${GROUP}/weeks?limit=1`,
      { headers: auth(TOKEN_1) },
      env,
    );
    expect(response.status).toBe(200);
    const body = (await response.json()) as {
      weeks: Array<{ id: string; number: number }>;
    };
    expect(body.weeks).toEqual([expect.objectContaining({ id: 'w1', number: 2 })]);

    const bad = await app.request(
      `/groups/${GROUP}/weeks?limit=0`,
      { headers: auth(TOKEN_1) },
      env,
    );
    expect(bad.status).toBe(400);
  });

  it('blocks non-members and cross-group week ids', async () => {
    const outsider = await app.request(
      `/groups/${GROUP}/weeks/w1/receipt`,
      { headers: auth(TOKEN_4) },
      env,
    );
    expect(outsider.status).toBe(403);

    const crossGroup = await app.request(
      `/groups/${GROUP}/weeks/other-w/receipt`,
      { headers: auth(TOKEN_1) },
      env,
    );
    expect(crossGroup.status).toBe(404);
  });
});
