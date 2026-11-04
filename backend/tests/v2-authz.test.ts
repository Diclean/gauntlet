import { beforeEach, describe, expect, it } from 'vitest';
import { env } from 'cloudflare:test';
import { app } from '../src';
import {
  CHALLENGE,
  GROUP,
  TOKEN_1,
  TOKEN_2,
  TOKEN_3,
  U1,
  U2,
  U3,
  WEEK,
  auth,
  insertChallenge,
  insertGroup,
  insertMember,
  insertMonthlyAward,
  insertPointEvent,
  insertSession,
  insertUser,
  insertWeek,
  jsonAuth,
  resetDb,
} from './fixtures';

/** v2 authorization, forfeit PATCH, awards reads and trophy cabinet. */

const JAN_W1 = 1_736_121_600; // Mon 2025-01-06
const JAN_W2 = 1_736_726_400; // Mon 2025-01-13

async function seed(): Promise<void> {
  await resetDb(env.DB);
  await insertUser(env.DB, U1, 'Alice', '🦊');
  await insertUser(env.DB, U2, 'Bob', '🐻');
  await insertUser(env.DB, U3, 'Mallory', '🐍');
  await insertSession(env.DB, U1, TOKEN_1);
  await insertSession(env.DB, U2, TOKEN_2);
  await insertSession(env.DB, U3, TOKEN_3);

  await insertGroup(env.DB, GROUP, U1, 'ABC234', 'Dares FC');
  await insertMember(env.DB, GROUP, U1);
  await insertMember(env.DB, GROUP, U2);
  await insertWeek(env.DB, GROUP, WEEK, 'open', { number: 1 });
  await insertChallenge(env.DB, WEEK, CHALLENGE, 10);

  // Closed January weeks so the awards read path can compute nominees.
  await insertWeek(env.DB, GROUP, 'jan-w1', 'closed', {
    startsAt: JAN_W1,
    endsAt: JAN_W1 + 7 * 86_400 - 1,
    voteDeadline: JAN_W1 + 7 * 86_400 + 12 * 3_600,
    number: 2,
  });
  await insertWeek(env.DB, GROUP, 'jan-w2', 'closed', {
    startsAt: JAN_W2,
    endsAt: JAN_W2 + 7 * 86_400 - 1,
    voteDeadline: JAN_W2 + 7 * 86_400 + 12 * 3_600,
    number: 3,
  });
  await insertPointEvent(env.DB, { weekId: 'jan-w1', userId: U1, points: 60 });
  await insertPointEvent(env.DB, { weekId: 'jan-w1', userId: U2, points: 20 });
  await insertPointEvent(env.DB, { weekId: 'jan-w2', userId: U1, points: 50 });

  await insertMonthlyAward(env.DB, {
    month: '2025-01',
    award: 'wooden_spoon',
    userId: U2,
    value: 0,
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
    value: 120,
  });
}

beforeEach(seed);

describe('club forfeit', () => {
  it('returns the default and lets only the owner edit it', async () => {
    const before = await app.request(`/groups/${GROUP}`, { headers: auth(TOKEN_1) }, env);
    expect(before.status).toBe(200);
    const beforeBody = (await before.json()) as { group: { forfeit: string } };
    expect(beforeBody.group.forfeit).toBe('Buys the round 🍺');

    const memberPatch = await app.request(
      `/groups/${GROUP}`,
      {
        method: 'PATCH',
        headers: jsonAuth(TOKEN_2),
        body: JSON.stringify({ forfeit: 'Kit duty 🧺' }),
      },
      env,
    );
    expect(memberPatch.status).toBe(403);

    const outsiderPatch = await app.request(
      `/groups/${GROUP}`,
      {
        method: 'PATCH',
        headers: jsonAuth(TOKEN_3),
        body: JSON.stringify({ forfeit: 'Kit duty 🧺' }),
      },
      env,
    );
    expect(outsiderPatch.status).toBe(403);

    const tooLong = await app.request(
      `/groups/${GROUP}`,
      {
        method: 'PATCH',
        headers: jsonAuth(TOKEN_1),
        body: JSON.stringify({ forfeit: 'x'.repeat(61) }),
      },
      env,
    );
    expect(tooLong.status).toBe(400);

    const empty = await app.request(
      `/groups/${GROUP}`,
      {
        method: 'PATCH',
        headers: jsonAuth(TOKEN_1),
        body: JSON.stringify({ forfeit: '   ' }),
      },
      env,
    );
    expect(empty.status).toBe(400);

    const ownerPatch = await app.request(
      `/groups/${GROUP}`,
      {
        method: 'PATCH',
        headers: jsonAuth(TOKEN_1),
        body: JSON.stringify({ forfeit: '  Kit duty 🧺  ' }),
      },
      env,
    );
    expect(ownerPatch.status).toBe(200);
    const patched = (await ownerPatch.json()) as { group: { forfeit: string } };
    expect(patched.group.forfeit).toBe('Kit duty 🧺');

    const after = await app.request(`/groups/${GROUP}`, { headers: auth(TOKEN_2) }, env);
    expect(((await after.json()) as { group: { forfeit: string } }).group.forfeit).toBe(
      'Kit duty 🧺',
    );
  });
});

describe('v2 endpoint authorization', () => {
  const paths = [
    `/groups/${GROUP}/stats/race`,
    `/groups/${GROUP}/weeks`,
    `/groups/${GROUP}/weeks/${WEEK}/receipt`,
    `/groups/${GROUP}/awards`,
    `/groups/${GROUP}/awards/months`,
  ];

  it('rejects non-members with 403 on every new group endpoint', async () => {
    for (const path of paths) {
      const response = await app.request(path, { headers: auth(TOKEN_3) }, env);
      expect(response.status, path).toBe(403);
      expect(await response.json()).toMatchObject({ error: { code: 'forbidden' } });
    }
  });

  it('requires auth on every new endpoint, including /me/trophies', async () => {
    for (const path of [...paths, '/me/trophies']) {
      const response = await app.request(path, {}, env);
      expect(response.status, path).toBe(401);
    }
  });

  it('lets members read the new group endpoints', async () => {
    for (const path of paths) {
      const response = await app.request(path, { headers: auth(TOKEN_2) }, env);
      expect(response.status, path).toBe(200);
    }
  });

  it('lists only closed weeks as past receipts', async () => {
    const response = await app.request(
      `/groups/${GROUP}/weeks?limit=10`,
      { headers: auth(TOKEN_2) },
      env,
    );
    expect(response.status).toBe(200);
    const body = (await response.json()) as {
      weeks: Array<{ id: string; number: number }>;
    };
    expect(body.weeks).toEqual([
      expect.objectContaining({ id: 'jan-w2', number: 3 }),
      expect.objectContaining({ id: 'jan-w1', number: 2 }),
    ]);
  });
});

describe('awards reads', () => {
  it('returns the latest month in ceremony order with winners', async () => {
    const response = await app.request(`/groups/${GROUP}/awards`, { headers: auth(TOKEN_1) }, env);
    expect(response.status).toBe(200);
    const body = (await response.json()) as {
      month: string;
      awards: Array<{
        award: string;
        winners: Array<{ id: string }>;
        value: number;
        nominees: Array<{ user: { id: string }; value: number }>;
      }>;
    };
    expect(body.month).toBe('2025-01');
    expect(body.awards.map((award) => award.award)).toEqual([
      'wooden_spoon',
      'golden_boot',
      'player_of_the_month',
    ]);
    expect(body.awards[0]!.winners[0]!.id).toBe(U2);
    expect(body.awards[2]).toMatchObject({ value: 120 });
    expect(body.awards[2]!.winners[0]!.id).toBe(U1);
    expect(body.awards[2]!.nominees).toEqual([
      { user: expect.objectContaining({ id: U1 }), value: 110 },
      { user: expect.objectContaining({ id: U2 }), value: 20 },
    ]);

    const empty = await app.request(
      `/groups/${GROUP}/awards?month=2024-12`,
      { headers: auth(TOKEN_1) },
      env,
    );
    expect(empty.status).toBe(200);
    expect(await empty.json()).toEqual({ month: '2024-12', awards: [] });

    const invalid = await app.request(
      `/groups/${GROUP}/awards?month=2025-13`,
      { headers: auth(TOKEN_1) },
      env,
    );
    expect(invalid.status).toBe(400);
  });

  it('lists award months newest first and builds the trophy cabinet', async () => {
    await insertMonthlyAward(env.DB, {
      month: '2024-12',
      award: 'golden_boot',
      userId: U1,
      value: 3,
    });

    const months = await app.request(
      `/groups/${GROUP}/awards/months`,
      { headers: auth(TOKEN_1) },
      env,
    );
    expect(months.status).toBe(200);
    expect(await months.json()).toEqual({ months: ['2025-01', '2024-12'] });

    const trophies = await app.request('/me/trophies', { headers: auth(TOKEN_1) }, env);
    expect(trophies.status).toBe(200);
    const body = (await trophies.json()) as {
      trophies: Array<{ groupId: string; groupName: string; month: string; award: string }>;
    };
    expect(body.trophies).toHaveLength(3);
    expect(body.trophies.map((trophy) => `${trophy.month}:${trophy.award}`).sort()).toEqual([
      '2024-12:golden_boot',
      '2025-01:golden_boot',
      '2025-01:player_of_the_month',
    ]);
    expect(body.trophies[0]).toMatchObject({ groupId: GROUP, groupName: 'Dares FC' });

    const nobody = await app.request('/me/trophies', { headers: auth(TOKEN_3) }, env);
    expect(nobody.status).toBe(200);
    expect(await nobody.json()).toEqual({ trophies: [] });
  });
});

describe('account deletion with awards', () => {
  it('removes the deleted user’s monthly awards and keeps the group for the next owner', async () => {
    const response = await app.request('/me', { method: 'DELETE', headers: auth(TOKEN_1) }, env);
    expect(response.status).toBe(200);

    const awards = await env.DB.prepare(
      'SELECT user_id FROM monthly_awards WHERE user_id = ?',
    )
      .bind(U1)
      .all<{ user_id: string }>();
    expect(awards.results).toHaveLength(0);

    const group = await env.DB.prepare('SELECT owner_id FROM groups WHERE id = ?')
      .bind(GROUP)
      .first<{ owner_id: string }>();
    expect(group?.owner_id).toBe(U2);

    const remaining = await env.DB.prepare(
      'SELECT user_id FROM monthly_awards WHERE group_id = ?',
    )
      .bind(GROUP)
      .all<{ user_id: string }>();
    expect(remaining.results).toEqual([{ user_id: U2 }]);
  });
});
