import { beforeEach, describe, expect, it } from 'vitest';
import { env } from 'cloudflare:test';
import { runCron } from '../src/cron';
import { computeMonthlyAwards } from '../src/business/awards';
import { maybeRunMonthlyAwards, runMonthlyAwards } from '../src/services/awards';
import { getGroupRow } from '../src/services/groups';
import { ensureCurrentWeek } from '../src/services/weeks';
import {
  GROUP,
  NOW,
  U1,
  U2,
  U3,
  insertChallenge,
  insertGroup,
  insertMember,
  insertPointEvent,
  insertSubmission,
  insertUser,
  insertWeek,
  resetDb,
} from './fixtures';

/** Monthly awards: pure rules (ties, empty months) + idempotent cron. */

const JOINED = 1_733_011_200; // Sun 2024-12-01 00:00 UTC
const DEC_WEEK = 1_735_516_800; // Mon 2024-12-30 00:00 UTC
const JAN_W1 = 1_736_121_600; // Mon 2025-01-06
const JAN_W2 = 1_736_726_400; // Mon 2025-01-13
const JAN_W3 = 1_737_331_200; // Mon 2025-01-20
const JAN_W4 = 1_737_936_000; // Mon 2025-01-27
const CRON_NOW = 1_738_609_200; // Mon 2025-02-03 19:00 UTC (first Monday of Feb)
const FEB_1_1900 = 1_738_436_400; // Sat 2025-02-01 19:00 UTC (not the first Monday)
const WEEK_SECONDS = 7 * 86_400;
const VOTE_GRACE_SECONDS = 12 * 3_600;

const OCT_W1 = 1_759_708_800; // Mon 2025-10-06 00:00 UTC
const OCT_LAST = 1_761_523_200; // Mon 2025-10-27 00:00 UTC (ends Sun 2025-11-02)
const NOV_3_1900 = 1_762_196_400; // Mon 2025-11-03 19:00 UTC (first Monday of Nov)
const NOV_1_1900 = 1_762_023_600; // Sat 2025-11-01 19:00 UTC (not the first Monday)
const NOV_3 = 1_762_128_000; // Mon 2025-11-03 00:00 UTC

async function insertWeekAt(
  id: string,
  startsAt: number,
  number: number,
  status: 'open' | 'closed' = 'closed',
): Promise<void> {
  await insertWeek(env.DB, GROUP, id, status, {
    startsAt,
    endsAt: startsAt + WEEK_SECONDS - 1,
    voteDeadline: startsAt + WEEK_SECONDS + VOTE_GRACE_SECONDS,
    number,
  });
}

async function seedJanuary(): Promise<void> {
  await resetDb(env.DB);
  await insertUser(env.DB, U1, 'Alice');
  await insertUser(env.DB, U2, 'Bob');
  await insertUser(env.DB, U3, 'Mallory');
  await insertGroup(env.DB, GROUP, U1, 'ABC234', 'Dares FC');
  for (const user of [U1, U2, U3]) await insertMember(env.DB, GROUP, user, JOINED);

  await insertWeekAt('w-dec', DEC_WEEK, 1);
  await insertWeekAt('w-jan1', JAN_W1, 2);
  await insertWeekAt('w-jan2', JAN_W2, 3);
  await insertWeekAt('w-jan3', JAN_W3, 4);
  await insertWeekAt('w-jan4', JAN_W4, 5);

  await insertChallenge(env.DB, 'w-jan1', 'c1', 50);
  await insertChallenge(env.DB, 'w-jan2', 'c2', 50);
  await insertChallenge(env.DB, 'w-jan3', 'c3', 30);

  await insertSubmission(env.DB, { id: 's1', challengeId: 'c1', userId: U1, status: 'accepted' });
  await insertSubmission(env.DB, { id: 's2', challengeId: 'c2', userId: U1, status: 'accepted' });
  await insertSubmission(env.DB, { id: 's3', challengeId: 'c3', userId: U2, status: 'accepted' });
  for (const id of ['s4', 's5', 's6']) {
    await insertSubmission(env.DB, { id, challengeId: 'c3', userId: U3, status: 'rejected' });
  }
  await env.DB.prepare(
    `INSERT INTO votes (submission_id, voter_id, approve, created_at)
     VALUES ('s4', ?, 0, ?), ('s5', ?, 0, ?), ('s6', ?, 0, ?), ('s4', ?, 0, ?)`,
  )
    .bind(U1, CRON_NOW, U1, CRON_NOW, U1, CRON_NOW, U2, CRON_NOW)
    .run();

  // December baseline: U2 leads all-time, U1 is second.
  await insertPointEvent(env.DB, {
    weekId: 'w-dec',
    userId: U1,
    points: 50,
    submissionId: 'dec-s1',
  });
  await insertPointEvent(env.DB, {
    weekId: 'w-dec',
    userId: U2,
    points: 80,
    submissionId: 'dec-s2',
  });

  // January: U1 120 points, U2 40 points, U3 0.
  await insertPointEvent(env.DB, {
    weekId: 'w-jan1',
    userId: U1,
    points: 50,
    submissionId: 's1',
  });
  await insertPointEvent(env.DB, {
    weekId: 'w-jan1',
    userId: U1,
    kind: 'first_bonus',
    points: 10,
    submissionId: 's1',
  });
  await insertPointEvent(env.DB, {
    weekId: 'w-jan2',
    userId: U1,
    points: 50,
    submissionId: 's2',
  });
  await insertPointEvent(env.DB, {
    weekId: 'w-jan2',
    userId: U1,
    kind: 'first_bonus',
    points: 10,
    submissionId: 's2',
  });
  await insertPointEvent(env.DB, {
    weekId: 'w-jan3',
    userId: U2,
    points: 30,
    submissionId: 's3',
  });
  await insertPointEvent(env.DB, {
    weekId: 'w-jan3',
    userId: U2,
    kind: 'first_bonus',
    points: 10,
    submissionId: 's3',
  });
}

describe('monthly award rules', () => {
  it('awards every tied member and picks nominees by metric', () => {
    const awards = computeMonthlyAwards({
      month: '2025-01',
      memberIds: [U1, U2, U3],
      presentAllMonth: new Set([U1, U2, U3]),
      points: new Map([
        [U1, 100],
        [U2, 100],
        [U3, 10],
      ]),
      acceptedSubmissions: new Map([
        [U1, 2],
        [U2, 2],
        [U3, 1],
      ]),
      rejectedSubmissions: new Map([[U3, 3]]),
      rejectionVotes: new Map([
        [U1, 3],
        [U2, 3],
        [U3, 0],
      ]),
      firstBonuses: new Map([
        [U1, 1],
        [U2, 1],
      ]),
      pointsByWeek: new Map([
        [U1, new Map([['w-jan1', 60]])],
        [U2, new Map([['w-jan2', 40]])],
      ]),
      rankAtStart: new Map([
        [U3, 1],
        [U1, 2],
        [U2, 2],
      ]),
      rankAtEnd: new Map([
        [U1, 1],
        [U2, 1],
        [U3, 3],
      ]),
    });

    const byAward = new Map(awards.map((award) => [award.award, award]));
    expect([...byAward.keys()]).toEqual([
      'wooden_spoon',
      'comeback_kid',
      'toughest_ref',
      'first_to_score',
      'golden_boot',
      'player_of_the_month',
    ]);

    for (const award of [
      'comeback_kid',
      'toughest_ref',
      'first_to_score',
      'golden_boot',
      'player_of_the_month',
    ] as const) {
      expect(byAward.get(award)!.winners.map((winner) => winner.userId).sort()).toEqual(
        [U1, U2].sort(),
      );
    }

    expect(byAward.get('wooden_spoon')!.winners).toEqual([{ userId: U3, value: 10 }]);
    expect(byAward.get('player_of_the_month')!.nominees.map((nominee) => nominee.value)).toEqual([
      100, 100, 10,
    ]);
    expect(byAward.get('wooden_spoon')!.nominees.map((nominee) => nominee.userId)).toEqual([
      U3,
      U1,
      U2,
    ]);
  });

  it('never lets 0 activity win except the Wooden Spoon', () => {
    const awards = computeMonthlyAwards({
      month: '2025-01',
      memberIds: [U1],
      presentAllMonth: new Set([U1]),
      points: new Map(),
      acceptedSubmissions: new Map(),
      rejectedSubmissions: new Map(),
      rejectionVotes: new Map(),
      firstBonuses: new Map(),
      pointsByWeek: new Map(),
      rankAtStart: new Map([[U1, 1]]),
      rankAtEnd: new Map([[U1, 1]]),
    });
    expect(awards.map((award) => award.award)).toEqual(['wooden_spoon']);
  });
});

describe('matchweek numbering', () => {
  it('starts at 1 and assigns max+1 to each newly generated week', async () => {
    await resetDb(env.DB);
    await insertUser(env.DB, U1, 'Alice');
    await insertGroup(env.DB, GROUP, U1, 'ABC234');
    await insertMember(env.DB, GROUP, U1, NOW - 1_000);

    const group = await getGroupRow(env.DB, GROUP);
    expect(group).not.toBeNull();
    const first = await ensureCurrentWeek(env, group!, NOW);
    expect(first.week.number).toBe(1);

    const second = await ensureCurrentWeek(env, group!, NOW + 7 * 86_400);
    expect(second.week.number).toBe(2);

    // Re-reading the same week does not allocate a new number.
    const firstAgain = await ensureCurrentWeek(env, group!, NOW + 60);
    expect(firstAgain.week.number).toBe(1);
  });
});

describe('monthly awards cron', () => {
  beforeEach(seedJanuary);

  it('stores the previous month once at the first Monday 19:00, with every award and a +50 ledger entry', async () => {
    const group = await getGroupRow(env.DB, GROUP);
    expect(group).not.toBeNull();

    // 18:59 is too early; the next tick (19:00) is Awards night.
    expect(await maybeRunMonthlyAwards(env, group!, CRON_NOW - 60)).toBeNull();
    const before = await env.DB.prepare(
      'SELECT group_id FROM monthly_award_runs WHERE group_id = ?',
    )
      .bind(GROUP)
      .all<{ group_id: string }>();
    expect(before.results).toHaveLength(0);

    const first = await maybeRunMonthlyAwards(env, group!, CRON_NOW);
    expect(first).toEqual({ month: '2025-01', recorded: true, awards: 6, pushed: true });

    const stored = await env.DB.prepare(
      `SELECT award, user_id, value FROM monthly_awards
        WHERE group_id = ? AND month = '2025-01'
        ORDER BY award ASC`,
    )
      .bind(GROUP)
      .all<{ award: string; user_id: string; value: number }>();

    expect(stored.results).toHaveLength(6);
    expect(
      Object.fromEntries(stored.results.map((row) => [row.award, [row.user_id, row.value]])),
    ).toEqual({
      comeback_kid: [U1, 1],
      first_to_score: [U1, 2],
      golden_boot: [U1, 2],
      player_of_the_month: [U1, 120],
      toughest_ref: [U1, 3],
      wooden_spoon: [U3, 0],
    });

    const ledger = await env.DB.prepare(
      `SELECT week_id, user_id, points FROM point_events
        WHERE group_id = ? AND kind = 'monthly_award'`,
    )
      .bind(GROUP)
      .all<{ week_id: string; user_id: string; points: number }>();
    expect(ledger.results).toEqual([{ week_id: 'w-jan4', user_id: U1, points: 50 }]);

    const runs = await env.DB.prepare(
      'SELECT group_id, month, ran_at FROM monthly_award_runs WHERE group_id = ?',
    )
      .bind(GROUP)
      .all<{ group_id: string; month: string; ran_at: number }>();
    expect(runs.results).toEqual([{ group_id: GROUP, month: '2025-01', ran_at: CRON_NOW }]);

    // Change the data so a later recomputation would pick a different winner
    // (U2 gets 500 more January points) — the run guard must keep it a no-op.
    await insertPointEvent(env.DB, {
      weekId: 'w-jan4',
      userId: U2,
      points: 500,
      submissionId: 'late-change',
    });

    const second = await maybeRunMonthlyAwards(env, group!, CRON_NOW + 3_600);
    expect(second).toEqual({ month: '2025-01', recorded: false, awards: 0, pushed: false });
    const third = await maybeRunMonthlyAwards(env, group!, CRON_NOW + 7_200);
    expect(third).toEqual({ month: '2025-01', recorded: false, awards: 0, pushed: false });

    const storedAgain = await env.DB.prepare(
      `SELECT award, user_id, value FROM monthly_awards
        WHERE group_id = ? AND month = '2025-01'
        ORDER BY award ASC`,
    )
      .bind(GROUP)
      .all<{ award: string; user_id: string; value: number }>();
    expect(storedAgain.results).toEqual(stored.results);

    const ledgerAgain = await env.DB.prepare(
      `SELECT id FROM point_events WHERE group_id = ? AND kind = 'monthly_award'`,
    )
      .bind(GROUP)
      .all<{ id: string }>();
    expect(ledgerAgain.results).toHaveLength(1);

    const runsAgain = await env.DB.prepare(
      'SELECT group_id, month, ran_at FROM monthly_award_runs WHERE group_id = ?',
    )
      .bind(GROUP)
      .all<{ group_id: string; month: string; ran_at: number }>();
    expect(runsAgain.results).toEqual(runs.results);
  });

  it('does nothing on the 1st when it is not the first Monday', async () => {
    const group = await getGroupRow(env.DB, GROUP);
    expect(group).not.toBeNull();

    expect(await maybeRunMonthlyAwards(env, group!, FEB_1_1900)).toBeNull();

    const runs = await env.DB.prepare(
      'SELECT group_id FROM monthly_award_runs WHERE group_id = ?',
    )
      .bind(GROUP)
      .all<{ group_id: string }>();
    expect(runs.results).toHaveLength(0);
    const awards = await env.DB.prepare(
      'SELECT id FROM monthly_awards WHERE group_id = ?',
    )
      .bind(GROUP)
      .all<{ id: string }>();
    expect(awards.results).toHaveLength(0);
  });

  it('counts the Oct 27 - Nov 2 week in October', async () => {
    await resetDb(env.DB);
    await insertUser(env.DB, U1, 'Alice');
    await insertUser(env.DB, U2, 'Bob');
    await insertGroup(env.DB, GROUP, U1, 'ABC234', 'Dares FC');
    await insertMember(env.DB, GROUP, U1, JOINED);
    await insertMember(env.DB, GROUP, U2, JOINED);

    // October 2025: the last week starts Mon Oct 27 and ends Sun Nov 2, with
    // its vote deadline on Mon Nov 3 12:00 — before Awards night at 19:00.
    await insertWeekAt('w-oct1', OCT_W1, 1);
    await insertWeekAt('w-oct-last', OCT_LAST, 2);
    await insertWeekAt('w-nov3', NOV_3, 3, 'open');

    // Weekly-winner ledger rows (not challenge/first_bonus) keep the cron's
    // week-finalization step from changing the totals under test.
    await insertPointEvent(env.DB, {
      weekId: 'w-oct1',
      userId: U1,
      kind: 'weekly_winner',
      points: 25,
    });
    await insertPointEvent(env.DB, {
      weekId: 'w-oct-last',
      userId: U2,
      kind: 'weekly_winner',
      points: 50,
    });

    await runCron(env, NOV_3_1900);

    const stored = await env.DB.prepare(
      `SELECT award, user_id, value FROM monthly_awards
        WHERE group_id = ? AND month = '2025-10'
        ORDER BY award ASC`,
    )
      .bind(GROUP)
      .all<{ award: string; user_id: string; value: number }>();
    expect(
      Object.fromEntries(stored.results.map((row) => [row.award, [row.user_id, row.value]])),
    ).toEqual({
      // Without the Oct 27 week, U1 would win the month 25-0.
      player_of_the_month: [U2, 50],
      wooden_spoon: [U1, 25],
    });

    const ledger = await env.DB.prepare(
      `SELECT week_id, user_id, points FROM point_events
        WHERE group_id = ? AND kind = 'monthly_award'`,
    )
      .bind(GROUP)
      .all<{ week_id: string; user_id: string; points: number }>();
    expect(ledger.results).toEqual([
      { week_id: 'w-oct-last', user_id: U2, points: 50 },
    ]);

    const runs = await env.DB.prepare(
      'SELECT month, ran_at FROM monthly_award_runs WHERE group_id = ?',
    )
      .bind(GROUP)
      .all<{ month: string; ran_at: number }>();
    expect(runs.results).toEqual([{ month: '2025-10', ran_at: NOV_3_1900 }]);
  });

  it('records a zero-award month once and sends no push', async () => {
    await resetDb(env.DB);
    await insertUser(env.DB, U1, 'Alice');
    await insertGroup(env.DB, GROUP, U1, 'ABC234', 'Dares FC');
    // Joined after October: nobody is eligible for the Wooden Spoon, and there
    // is no activity for any other award.
    await insertMember(env.DB, GROUP, U1, 1_761_955_200); // Sat 2025-11-01
    await insertWeekAt('w-oct1', OCT_W1, 1);

    const group = await getGroupRow(env.DB, GROUP);
    expect(group).not.toBeNull();

    const tick = await maybeRunMonthlyAwards(env, group!, NOV_3_1900);
    expect(tick).toEqual({ month: '2025-10', recorded: true, awards: 0, pushed: false });

    const runs = await env.DB.prepare(
      'SELECT month, ran_at FROM monthly_award_runs WHERE group_id = ?',
    )
      .bind(GROUP)
      .all<{ month: string; ran_at: number }>();
    expect(runs.results).toEqual([{ month: '2025-10', ran_at: NOV_3_1900 }]);

    const awards = await env.DB.prepare(
      'SELECT id FROM monthly_awards WHERE group_id = ?',
    )
      .bind(GROUP)
      .all<{ id: string }>();
    expect(awards.results).toHaveLength(0);
    const ledger = await env.DB.prepare(
      "SELECT id FROM point_events WHERE group_id = ? AND kind = 'monthly_award'",
    )
      .bind(GROUP)
      .all<{ id: string }>();
    expect(ledger.results).toHaveLength(0);

    const again = await maybeRunMonthlyAwards(env, group!, NOV_3_1900 + 3_600);
    expect(again).toEqual({ month: '2025-10', recorded: false, awards: 0, pushed: false });
  });

  it('skips a month with no closed weeks', async () => {
    await resetDb(env.DB);
    await insertUser(env.DB, U1, 'Alice');
    await insertGroup(env.DB, GROUP, U1, 'ABC234');
    await insertMember(env.DB, GROUP, U1, JOINED);
    // Only a December closed week: January has nothing to celebrate.
    await insertWeekAt('w-dec', DEC_WEEK, 1);

    const group = await getGroupRow(env.DB, GROUP);
    expect(group).not.toBeNull();
    const run = await runMonthlyAwards(env, group!, '2025-01', CRON_NOW);
    expect(run).toBeNull();

    await runCron(env, CRON_NOW);
    const awards = await env.DB.prepare(
      'SELECT id FROM monthly_awards WHERE group_id = ?',
    )
      .bind(GROUP)
      .all<{ id: string }>();
    expect(awards.results).toHaveLength(0);
    const ledger = await env.DB.prepare(
      "SELECT id FROM point_events WHERE group_id = ? AND kind = 'monthly_award'",
    )
      .bind(GROUP)
      .all<{ id: string }>();
    expect(ledger.results).toHaveLength(0);
    const runs = await env.DB.prepare(
      'SELECT group_id FROM monthly_award_runs WHERE group_id = ?',
    )
      .bind(GROUP)
      .all<{ group_id: string }>();
    expect(runs.results).toHaveLength(0);
  });
});
