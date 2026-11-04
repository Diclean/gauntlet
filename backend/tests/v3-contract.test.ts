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
  insertSession,
  insertUser,
  insertWeek,
  jsonAuth,
  resetDb,
} from './fixtures';

/** SPEC §6.9 contract additions: group preview, ban list, Week.vetoesUsed. */

const PUBLIC_BASE = 'https://dares.example.workers.dev';

const U4 = '44444444-4444-4444-8444-444444444444';
const TOKEN_4 = 'token-for-user-4-0123456789abcdef';
const U5 = '55555555-5555-4555-8555-555555555555';
const TOKEN_5 = 'token-for-user-5-0123456789abcdef';

const C2 = 'dddddddd-dddd-4ddd-8ddd-ddddddddddd2';

async function seed(): Promise<void> {
  await resetDb(env.DB);
  await insertUser(env.DB, U1, 'Alice', '🦊');
  await insertUser(env.DB, U2, 'Bob', '🐻');
  await insertUser(env.DB, U3, 'Cara', '🐧');
  await insertUser(env.DB, U4, 'Dan', '🐢');
  await insertUser(env.DB, U5, 'Eve', '🦉', { terms: false });
  await insertSession(env.DB, U1, TOKEN_1);
  await insertSession(env.DB, U2, TOKEN_2);
  await insertSession(env.DB, U3, TOKEN_3);
  await insertSession(env.DB, U4, TOKEN_4);
  await insertSession(env.DB, U5, TOKEN_5);

  await insertGroup(env.DB, GROUP, U1, 'ABC234');
  await insertMember(env.DB, GROUP, U1);
  await insertMember(env.DB, GROUP, U2);
  await insertMember(env.DB, GROUP, U3);
  await insertWeek(env.DB, GROUP, WEEK);
  await insertChallenge(env.DB, WEEK, CHALLENGE, 25);
  await insertChallenge(env.DB, WEEK, C2, 10);
}

beforeEach(seed);

function preview(code: string, token = TOKEN_2) {
  return app.request(`/groups/preview/${code}`, { headers: auth(token) }, env);
}

function veto(token: string, challengeId: string) {
  return app.request(
    `/challenges/${challengeId}/veto`,
    { method: 'POST', headers: auth(token) },
    env,
  );
}

describe('GET /groups/preview/:code', () => {
  it('returns the same Group JSON as GET /groups/:id, including memberCount and inviteUrl', async () => {
    const response = await preview('abc234', TOKEN_2);
    expect(response.status).toBe(200);
    const body = (await response.json()) as {
      group: {
        id: string;
        inviteCode: string;
        memberCount: number;
        inviteUrl: string;
      };
    };
    expect(body.group.memberCount).toBe(3);
    expect(body.group.inviteCode).toBe('ABC234');
    expect(body.group.inviteUrl).toBe(`${PUBLIC_BASE}/join/ABC234`);

    const single = await app.request(`/groups/${GROUP}`, { headers: auth(TOKEN_2) }, env);
    expect(single.status).toBe(200);
    const singleBody = (await single.json()) as { group: unknown };
    expect(body.group).toEqual(singleBody.group);

    // Preview is for invited users too, not just existing members.
    const outsider = await preview('ABC234', TOKEN_4);
    expect(outsider.status).toBe(200);
    expect(((await outsider.json()) as { group: { memberCount: number } }).group.memberCount).toBe(3);
  });

  it('does not require terms acceptance (GET is exempt), unlike writes', async () => {
    const response = await preview('ABC234', TOKEN_5);
    expect(response.status).toBe(200);

    const write = await app.request(
      '/groups',
      {
        method: 'POST',
        headers: jsonAuth(TOKEN_5),
        body: JSON.stringify({ name: 'Eve FC', timezone: 'UTC' }),
      },
      env,
    );
    expect(write.status).toBe(403);
    expect(await write.json()).toMatchObject({ error: { code: 'terms_required' } });
  });

  it('returns 404 not_found for unknown, malformed and banned codes', async () => {
    for (const code of ['ZZZZZZ', 'abc', 'AAA111']) {
      const response = await preview(code);
      expect(response.status, code).toBe(404);
      expect(await response.json()).toMatchObject({ error: { code: 'not_found' } });
    }

    await env.DB.prepare(
      'INSERT INTO group_bans (group_id, user_id, created_at) VALUES (?, ?, ?)',
    )
      .bind(GROUP, U2, Math.floor(Date.now() / 1000))
      .run();
    const banned = await preview('ABC234', TOKEN_2);
    expect(banned.status).toBe(404);
    expect(await banned.json()).toMatchObject({ error: { code: 'not_found' } });

    // The ban only hides the club from the banned caller.
    expect((await preview('ABC234', TOKEN_1)).status).toBe(200);
  });

  it('requires auth and shares the join user + IP rate-limit buckets', async () => {
    const unauthenticated = await app.request('/groups/preview/ABC234', {}, env);
    expect(unauthenticated.status).toBe(401);

    expect((await preview('ABC234', TOKEN_4)).status).toBe(200);
    const keys = await env.DB.prepare(
      "SELECT key FROM rate_limits WHERE key LIKE 'group-join%' ORDER BY key",
    ).all<{ key: string }>();
    expect(keys.results.map((row) => row.key)).toEqual(
      expect.arrayContaining([`group-join:${U4}`, expect.stringMatching(/^group-join-ip:/)]),
    );

    // Draining the user bucket blocks the next preview.
    await env.DB.prepare('UPDATE rate_limits SET tokens = 0 WHERE key = ?')
      .bind(`group-join:${U4}`)
      .run();
    const userLimited = await preview('ABC234', TOKEN_4);
    expect(userLimited.status).toBe(429);
    expect(await userLimited.json()).toMatchObject({ error: { code: 'rate_limited' } });

    // Refilling the user bucket exposes the shared IP bucket.
    await env.DB.prepare('UPDATE rate_limits SET tokens = 10 WHERE key = ?')
      .bind(`group-join:${U4}`)
      .run();
    const ipKey = keys.results.find((row) => row.key.startsWith('group-join-ip:'))!.key;
    await env.DB.prepare('UPDATE rate_limits SET tokens = 0 WHERE key = ?').bind(ipKey).run();
    const ipLimited = await preview('ABC234', TOKEN_4);
    expect(ipLimited.status).toBe(429);
    expect(await ipLimited.json()).toMatchObject({ error: { code: 'rate_limited' } });
  });
});

describe('GET /groups/:id/bans', () => {
  it('returns banned users with bannedAt, newest first, for the owner', async () => {
    const now = Math.floor(Date.now() / 1000);
    await env.DB.batch([
      env.DB.prepare(
        'INSERT INTO group_bans (group_id, user_id, created_at) VALUES (?, ?, ?)',
      ).bind(GROUP, U2, now - 1_000),
      env.DB.prepare(
        'INSERT INTO group_bans (group_id, user_id, created_at) VALUES (?, ?, ?)',
      ).bind(GROUP, U4, now - 100),
    ]);

    const response = await app.request(`/groups/${GROUP}/bans`, { headers: auth(TOKEN_1) }, env);
    expect(response.status).toBe(200);
    const body = (await response.json()) as {
      users: Array<{ id: string; displayName: string; avatarEmoji: string | null; bannedAt: number }>;
    };
    expect(body.users).toEqual([
      { id: U4, displayName: 'Dan', avatarEmoji: '🐢', bannedAt: now - 100 },
      { id: U2, displayName: 'Bob', avatarEmoji: '🐻', bannedAt: now - 1_000 },
    ]);
    // Never leak private user fields.
    expect(Object.keys(body.users[0]!).sort()).toEqual(
      ['avatarEmoji', 'bannedAt', 'displayName', 'id'].sort(),
    );
  });

  it('is owner only and requires auth', async () => {
    const unauthenticated = await app.request(`/groups/${GROUP}/bans`, {}, env);
    expect(unauthenticated.status).toBe(401);

    for (const token of [TOKEN_2, TOKEN_4]) {
      const response = await app.request(`/groups/${GROUP}/bans`, { headers: auth(token) }, env);
      expect(response.status, token).toBe(403);
      expect(await response.json()).toMatchObject({ error: { code: 'forbidden' } });
    }
  });
});

describe('Week.vetoesUsed', () => {
  it('starts at 0 and increments after a replacement', async () => {
    const before = await app.request(`/groups/${GROUP}/week`, { headers: auth(TOKEN_1) }, env);
    expect(before.status).toBe(200);
    expect(((await before.json()) as { week: { vetoesUsed: number } }).week.vetoesUsed).toBe(0);

    expect((await veto(TOKEN_2, CHALLENGE)).status).toBe(200);
    const one = await veto(TOKEN_3, CHALLENGE);
    expect(one.status).toBe(200);
    expect(((await one.json()) as { replaced: boolean }).replaced).toBe(true);

    const after = await app.request(`/groups/${GROUP}/week`, { headers: auth(TOKEN_1) }, env);
    expect(((await after.json()) as { week: { vetoesUsed: number } }).week.vetoesUsed).toBe(1);
  });

  it('is included on the weeks list', async () => {
    expect((await veto(TOKEN_2, CHALLENGE)).status).toBe(200);
    expect((await veto(TOKEN_3, CHALLENGE)).status).toBe(200);
    await env.DB.prepare("UPDATE weeks SET status = 'closed' WHERE id = ?").bind(WEEK).run();

    const response = await app.request(`/groups/${GROUP}/weeks`, { headers: auth(TOKEN_1) }, env);
    expect(response.status).toBe(200);
    const body = (await response.json()) as { weeks: Array<{ id: string; vetoesUsed: number }> };
    expect(body.weeks.find((week) => week.id === WEEK)?.vetoesUsed).toBe(1);
  });

  it('is included on the receipt week', async () => {
    expect((await veto(TOKEN_2, CHALLENGE)).status).toBe(200);
    expect((await veto(TOKEN_3, CHALLENGE)).status).toBe(200);

    const response = await app.request(
      `/groups/${GROUP}/weeks/${WEEK}/receipt`,
      { headers: auth(TOKEN_1) },
      env,
    );
    expect(response.status).toBe(200);
    const body = (await response.json()) as { week: { id: string; vetoesUsed: number } };
    expect(body.week).toMatchObject({ id: WEEK, vetoesUsed: 1 });
  });
});
