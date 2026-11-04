import { beforeEach, describe, expect, it } from 'vitest';
import { env } from 'cloudflare:test';
import { runCron } from '../src/cron';
import { awardWeekEnd, ensureCurrentWeek } from '../src/services/weeks';
import { getGroupRow } from '../src/services/groups';
import { randomId } from '../src/lib/crypto';
import type { WeekRow } from '../src/types';
import {
  GROUP,
  NOW,
  U1,
  U2,
  insertChallenge,
  insertGroup,
  insertMember,
  insertSession,
  insertSubmission,
  insertUser,
  insertWeek,
  resetDb,
} from './fixtures';

const W1_START = 1_735_516_800; // Mon 2024-12-30 00:00 UTC
const W1_END = 1_736_121_599; // Sun 2025-01-05 23:59:59 UTC
const W1_DEADLINE = 1_736_164_800; // Mon 2025-01-06 12:00 UTC
const W2_START = 1_736_121_600; // Mon 2025-01-06 00:00 UTC
const W2_END = 1_736_726_399;
const W2_DEADLINE = 1_736_769_600;
const ROLLOVER_NOW = 1_736_730_000; // Mon 2025-01-13 01:00 UTC

async function insertWeekWithDates(
  id: string,
  startsAt: number,
  endsAt: number,
  voteDeadline: number,
  status: 'open' | 'closed',
): Promise<void> {
  await env.DB.prepare(
    `INSERT INTO weeks (id, group_id, starts_at, ends_at, vote_deadline, status, reminder_sent)
     VALUES (?, ?, ?, ?, ?, ?, 0)`,
  )
    .bind(id, GROUP, startsAt, endsAt, voteDeadline, status)
    .run();
}

beforeEach(async () => {
  await resetDb(env.DB);
  await insertUser(env.DB, U1, 'Alice');
  await insertUser(env.DB, U2, 'Bob');
  await insertSession(env.DB, U1, 'cron-token-1-0123456789abcdef');
});

describe('hourly cron rollover', () => {
  it('closes the previous week and creates exactly one current week, idempotently', async () => {
    await insertGroup(env.DB, GROUP, U1, 'ABC234');
    await insertMember(env.DB, GROUP, U1);
    await insertMember(env.DB, GROUP, U2);
    await insertWeekWithDates('w-old', 1_736_121_600, 1_736_726_399, 1_736_769_600, 'open');
    await insertChallenge(env.DB, 'w-old', 'old-challenge', 10);

    await runCron(env, ROLLOVER_NOW);

    const weeks = await env.DB.prepare(
      'SELECT * FROM weeks WHERE group_id = ? ORDER BY starts_at ASC',
    )
      .bind(GROUP)
      .all<WeekRow>();
    expect(weeks.results).toHaveLength(2);
    expect(weeks.results[0]!.status).toBe('closed');
    expect(weeks.results[1]!.status).toBe('open');
    expect(weeks.results[1]!.starts_at).toBe(ROLLOVER_NOW - (ROLLOVER_NOW % 86_400));
    expect(weeks.results[1]!.starts_at).toBe(1_736_726_400); // Mon 2025-01-13

    const challenges = await env.DB.prepare(
      'SELECT id FROM challenges WHERE week_id = ?',
    )
      .bind(weeks.results[1]!.id)
      .all<{ id: string }>();
    expect(challenges.results).toHaveLength(5);

    await runCron(env, ROLLOVER_NOW + 60);
    const again = await env.DB.prepare('SELECT id FROM weeks WHERE group_id = ?')
      .bind(GROUP)
      .all<{ id: string }>();
    expect(again.results).toHaveLength(2);
  });
});

describe('week recovery', () => {
  it('regenerates challenges when a week row exists but its challenge batch never landed', async () => {
    await insertGroup(env.DB, GROUP, U1, 'ABC234');
    await insertMember(env.DB, GROUP, U1);
    await insertWeek(env.DB, GROUP); // current Monday, but deliberately no challenges

    const group = await getGroupRow(env.DB, GROUP);
    expect(group).not.toBeNull();
    const created = await ensureCurrentWeek(env, group!, NOW);
    expect(created.created).toBe(true);
    expect(created.challenges).toHaveLength(5);

    const weeks = await env.DB.prepare('SELECT id FROM weeks WHERE group_id = ?')
      .bind(GROUP)
      .all<{ id: string }>();
    expect(weeks.results).toHaveLength(1);
  });
});

describe('deadline reminder', () => {
  it('marks the week reminder_sent exactly once on Sunday evening', async () => {
    const sunday18 = 1_736_704_800; // Sun 2025-01-12 18:00:00 UTC
    await insertGroup(env.DB, GROUP, U1, 'ABC234');
    await insertMember(env.DB, GROUP, U1);
    await insertWeekWithDates('w-current', 1_736_121_600, 1_736_726_399, 1_736_769_600, 'open');
    await insertChallenge(env.DB, 'w-current', 'c-current', 10);

    await runCron(env, sunday18);

    const week = await env.DB.prepare('SELECT reminder_sent FROM weeks WHERE id = ?')
      .bind('w-current')
      .first<{ reminder_sent: number }>();
    expect(week?.reminder_sent).toBe(1);

    // A second tick must not re-send (and must not fail).
    await runCron(env, sunday18 + 60);
    const again = await env.DB.prepare('SELECT reminder_sent FROM weeks WHERE id = ?')
      .bind('w-current')
      .first<{ reminder_sent: number }>();
    expect(again?.reminder_sent).toBe(1);
  });
});

describe('week-end awards', () => {
  it('awards the weekly winner and a 2-week streak exactly once', async () => {
    await insertGroup(env.DB, GROUP, U1, 'ABC234');
    await insertMember(env.DB, GROUP, U1);
    await insertMember(env.DB, GROUP, U2);
    await insertWeekWithDates('w1', W1_START, W1_END, W1_DEADLINE, 'closed');
    await insertWeekWithDates('w2', W2_START, W2_END, W2_DEADLINE, 'closed');
    await insertChallenge(env.DB, 'w1', 'c1', 10);
    await insertChallenge(env.DB, 'w2', 'c2', 10);
    await insertSubmission(env.DB, {
      id: 's1',
      challengeId: 'c1',
      userId: U1,
      mediaKey: 's1.jpg',
      status: 'accepted',
      eligibleVoters: 1,
    });
    await insertSubmission(env.DB, {
      id: 's2',
      challengeId: 'c2',
      userId: U1,
      mediaKey: 's2.jpg',
      status: 'accepted',
      eligibleVoters: 1,
    });

    for (const [weekId, submissionId] of [
      ['w1', 's1'],
      ['w2', 's2'],
    ] as const) {
      await env.DB.prepare(
        `INSERT INTO point_events
           (id, group_id, week_id, user_id, kind, points, submission_id, created_at)
         VALUES (?, ?, ?, ?, 'challenge', 10, ?, ?)`,
      )
        .bind(randomId(), GROUP, weekId, U1, submissionId, NOW)
        .run();
    }

    const group = await getGroupRow(env.DB, GROUP);
    expect(group).not.toBeNull();
    const week2: WeekRow = {
      id: 'w2',
      group_id: GROUP,
      starts_at: W2_START,
      ends_at: W2_END,
      vote_deadline: W2_DEADLINE,
      status: 'closed',
      reminder_sent: 0,
      number: 2,
    };

    await awardWeekEnd(env, group!, week2, W2_DEADLINE + 1);
    await awardWeekEnd(env, group!, week2, W2_DEADLINE + 120);

    const events = await env.DB.prepare(
      `SELECT kind, points FROM point_events
        WHERE week_id = 'w2' AND user_id = ? AND kind IN ('weekly_winner', 'streak')
        ORDER BY kind ASC`,
    )
      .bind(U1)
      .all<{ kind: string; points: number }>();
    expect(events.results).toEqual([
      { kind: 'streak', points: 10 },
      { kind: 'weekly_winner', points: 50 },
    ]);
  });
});
