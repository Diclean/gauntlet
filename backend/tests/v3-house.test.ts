import { beforeEach, describe, expect, it } from 'vitest';
import { env } from 'cloudflare:test';
import { app } from '../src';
import { houseFixtureDeadline } from '../src/business/time';
import { getGroupRow } from '../src/services/groups';
import { createHouseFixture, getWeekRow } from '../src/services/fixtures';
import {
  CHALLENGE,
  GROUP,
  GROUP2,
  TOKEN_1,
  TOKEN_2,
  TOKEN_3,
  U1,
  U2,
  U3,
  WEEK,
  WEEK_START,
  auth,
  insertChallenge,
  insertGroup,
  insertMember,
  insertPointEvent,
  insertSession,
  insertUser,
  insertWeek,
  jsonAuth,
  resetDb,
} from './fixtures';

/** 6.7 house fixture: author rules, Wednesday deadline and one-per-week slot. */

const PREV_WEEK = 'cccccccc-cccc-4ccc-8ccc-ccccccccccc1';
const C2 = 'dddddddd-dddd-4ddd-8ddd-ddddddddddd2';

async function seed(): Promise<void> {
  await resetDb(env.DB);
  await insertUser(env.DB, U1, 'Alice', '🦊');
  await insertUser(env.DB, U2, 'Bob', '🐻');
  await insertUser(env.DB, U3, 'Outsider', '👀');
  await insertSession(env.DB, U1, TOKEN_1);
  await insertSession(env.DB, U2, TOKEN_2);
  await insertSession(env.DB, U3, TOKEN_3);

  await insertGroup(env.DB, GROUP, U1, 'ABC234');
  await insertMember(env.DB, GROUP, U1);
  await insertMember(env.DB, GROUP, U2);

  // Matchweek 1: Bob is Man of the Match (50 vs 10).
  await insertWeek(env.DB, GROUP, PREV_WEEK, 'closed', {
    startsAt: WEEK_START - 7 * 86_400,
    endsAt: WEEK_START - 1,
    voteDeadline: WEEK_START + 12 * 3_600,
    number: 1,
  });
  await insertPointEvent(env.DB, { weekId: PREV_WEEK, userId: U2, points: 50 });
  await insertPointEvent(env.DB, { weekId: PREV_WEEK, userId: U1, points: 10 });

  await insertWeek(env.DB, GROUP, WEEK, 'open', { number: 2 });
  await insertChallenge(env.DB, WEEK, CHALLENGE, 10);
  await insertChallenge(env.DB, WEEK, C2, 10);

  // A second, brand new club for the first-week owner rule.
  await insertGroup(env.DB, GROUP2, U1, 'NEW234', 'Fresh club');
  await insertMember(env.DB, GROUP2, U1);
  await insertMember(env.DB, GROUP2, U2);
}

beforeEach(seed);

describe('house fixture deadline math', () => {
  it('is Wednesday 23:59:59 group-local', () => {
    const monday = Date.UTC(2025, 0, 6) / 1000; // Mon 2025-01-06 00:00 UTC
    const wednesday = Date.UTC(2025, 0, 8, 23, 59, 59) / 1000;
    expect(houseFixtureDeadline(monday, 'UTC')).toBe(wednesday);
    // Europe/Paris is UTC+1 in January, so the deadline is 22:59:59 UTC.
    expect(houseFixtureDeadline(monday, 'Europe/Paris')).toBe(wednesday - 3_600);
  });
});

describe('house fixture author rules', () => {
  it('only lets the previous Man of the Match add it (not the owner)', async () => {
    const denied = await app.request(
      `/groups/${GROUP}/week/house-fixture`,
      {
        method: 'POST',
        headers: jsonAuth(TOKEN_1),
        body: JSON.stringify({
          title: 'Owner fixture',
          description: 'Should be denied.',
          difficulty: 'easy',
        }),
      },
      env,
    );
    expect(denied.status).toBe(403);

    const group = await getGroupRow(env.DB, GROUP);
    const week = await getWeekRow(env.DB, WEEK);
    expect(group).not.toBeNull();
    expect(week).not.toBeNull();

    const challenge = await createHouseFixture(env, {
      group: group!,
      week: week!,
      userId: U2,
      title: 'Sunday roast',
      description: 'Cook a roast for the club.',
      difficulty: 'medium',
      now: WEEK_START + 60,
    });
    expect(challenge.is_house).toBe(1);
    expect(challenge.created_by).toBe(U2);
    expect(challenge.position).toBe(1); // both fixture-inserted challenges share position 0
    expect(challenge.points).toBe(25);

    const stored = await env.DB.prepare(
      'SELECT is_house, created_by, position FROM challenges WHERE id = ?',
    )
      .bind(challenge.id)
      .first<{ is_house: number; created_by: string; position: number }>();
    expect(stored).toEqual({ is_house: 1, created_by: U2, position: 1 });

    const second = await app.request(
      `/groups/${GROUP}/week/house-fixture`,
      {
        method: 'POST',
        headers: jsonAuth(TOKEN_2),
        body: JSON.stringify({ title: 'Another one', difficulty: 'easy' }),
      },
      env,
    );
    expect(second.status).toBe(409);
    expect(await second.json()).toMatchObject({ error: { code: 'house_fixture_taken' } });
  });

  it('lets the owner add one in the club’s first week', async () => {
    const group = await getGroupRow(env.DB, GROUP2);
    const firstWeek = {
      id: 'first-week-id',
      group_id: GROUP2,
      starts_at: WEEK_START,
      ends_at: WEEK_START + 7 * 86_400 - 1,
      vote_deadline: WEEK_START + 7 * 86_400 + 12 * 3_600,
      status: 'open' as const,
      reminder_sent: 0,
      number: 1,
    };

    await expect(
      createHouseFixture(env, {
        group: group!,
        week: firstWeek,
        userId: U2,
        title: 'Not mine',
        description: null,
        difficulty: 'easy',
        now: WEEK_START + 60,
      }),
    ).rejects.toMatchObject({ status: 403 });

    const challenge = await createHouseFixture(env, {
      group: group!,
      week: firstWeek,
      userId: U1,
      title: 'First house fixture',
      description: 'Owner-written.',
      difficulty: 'hard',
      now: WEEK_START + 60,
    });
    expect(challenge.points).toBe(50);
    expect(challenge.created_by).toBe(U1);
  });

  it('closes the window after Wednesday 23:59:59 group-local', async () => {
    const group = await getGroupRow(env.DB, GROUP);
    const oldWeek = {
      id: 'old-week-id',
      group_id: GROUP,
      starts_at: WEEK_START - 28 * 86_400,
      ends_at: WEEK_START - 21 * 86_400 - 1,
      vote_deadline: WEEK_START - 21 * 86_400 + 12 * 3_600,
      status: 'closed' as const,
      reminder_sent: 0,
      number: 5,
    };

    await expect(
      createHouseFixture(env, {
        group: group!,
        week: oldWeek,
        userId: U1,
        title: 'Too late',
        description: null,
        difficulty: 'easy',
        now: WEEK_START - 14 * 86_400,
      }),
    ).rejects.toMatchObject({ code: 'house_fixture_closed', status: 409 });
  });
});

describe('GET /groups/:id/week houseFixture block', () => {
  it('returns availability, deadline and the existing author', async () => {
    const before = await app.request(`/groups/${GROUP}/week`, { headers: auth(TOKEN_1) }, env);
    expect(before.status).toBe(200);
    const beforeBody = (await before.json()) as {
      houseFixture: { allowed: boolean; deadline: number; author: unknown };
    };
    expect(beforeBody.houseFixture.deadline).toBe(houseFixtureDeadline(WEEK_START, 'UTC'));
    expect(beforeBody.houseFixture.author).toBeNull();
    expect(typeof beforeBody.houseFixture.allowed).toBe('boolean');

    const group = await getGroupRow(env.DB, GROUP);
    const week = await getWeekRow(env.DB, WEEK);
    const house = await createHouseFixture(env, {
      group: group!,
      week: week!,
      userId: U2,
      title: 'Table football derby',
      description: 'Best of three.',
      difficulty: 'easy',
      now: WEEK_START + 60,
    });

    const after = await app.request(`/groups/${GROUP}/week`, { headers: auth(TOKEN_1) }, env);
    const afterBody = (await after.json()) as {
      houseFixture: { allowed: boolean; author: { id: string } | null };
      challenges: Array<{ id: string; isHouse: boolean; createdBy: { id: string } | null }>;
    };
    expect(afterBody.houseFixture.allowed).toBe(false);
    expect(afterBody.houseFixture.author?.id).toBe(U2);
    const challenge = afterBody.challenges.find((item) => item.id === house.id);
    expect(challenge).toMatchObject({ isHouse: true, createdBy: { id: U2 } });
  });

  it('requires club membership', async () => {
    const outsider = await app.request(`/groups/${GROUP}/week`, { headers: auth(TOKEN_3) }, env);
    expect(outsider.status).toBe(403);
  });
});
