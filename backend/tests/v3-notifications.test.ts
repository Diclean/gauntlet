import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { env } from 'cloudflare:test';
import { app } from '../src';
import type { Env } from '../src/types';
import { clearApnsJwtCache, pushNewWeek, sendPushToUsers } from '../src/push';
import {
  GROUP,
  TOKEN_1,
  TOKEN_2,
  U1,
  U2,
  auth,
  insertGroup,
  insertMember,
  insertSession,
  insertUser,
  jsonAuth,
  resetDb,
} from './fixtures';

/** 6.4 notification preferences, including enforcement in the push sender. */

function toStandardBase64(bytes: Uint8Array): string {
  let binary = '';
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary);
}

async function makeP8(): Promise<string> {
  const pair = (await crypto.subtle.generateKey(
    { name: 'ECDSA', namedCurve: 'P-256' },
    true,
    ['sign', 'verify'],
  )) as CryptoKeyPair;
  const exported = await crypto.subtle.exportKey('pkcs8', pair.privateKey);
  const pkcs8 = new Uint8Array(exported as ArrayBuffer);
  return `-----BEGIN PRIVATE KEY-----\n${toStandardBase64(pkcs8)}\n-----END PRIVATE KEY-----`;
}

async function insertDevice(userId: string, token: string): Promise<void> {
  await env.DB.prepare(
    'INSERT INTO devices (id, user_id, apns_token, created_at) VALUES (?, ?, ?, ?)',
  )
    .bind(crypto.randomUUID(), userId, token, Math.floor(Date.now() / 1000))
    .run();
}

async function seed(): Promise<void> {
  await resetDb(env.DB);
  await insertUser(env.DB, U1, 'Alice', '🦊');
  await insertUser(env.DB, U2, 'Bob', '🐻');
  await insertSession(env.DB, U1, TOKEN_1);
  await insertSession(env.DB, U2, TOKEN_2);
  await insertGroup(env.DB, GROUP, U1, 'ABC234');
  await insertMember(env.DB, GROUP, U1);
  await insertMember(env.DB, GROUP, U2);
}

beforeEach(async () => {
  await seed();
  clearApnsJwtCache();
});

afterEach(() => {
  vi.unstubAllGlobals();
});

describe('notification preferences API', () => {
  it('defaults every category to on and merges partial PATCHes', async () => {
    const defaults = await app.request('/me/notification-prefs', { headers: auth(TOKEN_1) }, env);
    expect(defaults.status).toBe(200);
    expect(await defaults.json()).toEqual({
      newWeek: true,
      voteNeeded: true,
      result: true,
      deadline: true,
      awards: true,
      banter: true,
    });

    const patch = await app.request(
      '/me/notification-prefs',
      {
        method: 'PATCH',
        headers: jsonAuth(TOKEN_1),
        body: JSON.stringify({ banter: false, awards: false }),
      },
      env,
    );
    expect(patch.status).toBe(200);
    expect(await patch.json()).toEqual({
      newWeek: true,
      voteNeeded: true,
      result: true,
      deadline: true,
      awards: false,
      banter: false,
    });

    const read = await app.request('/me/notification-prefs', { headers: auth(TOKEN_1) }, env);
    expect(await read.json()).toMatchObject({ awards: false, banter: false });

    const empty = await app.request(
      '/me/notification-prefs',
      { method: 'PATCH', headers: jsonAuth(TOKEN_1), body: JSON.stringify({}) },
      env,
    );
    expect(empty.status).toBe(400);

    const unknown = await app.request(
      '/me/notification-prefs',
      {
        method: 'PATCH',
        headers: jsonAuth(TOKEN_1),
        body: JSON.stringify({ surprise: false }),
      },
      env,
    );
    expect(unknown.status).toBe(400);
  });
});

describe('push preference enforcement', () => {
  it('suppresses new-week pushes for members who muted the category', async () => {
    await insertDevice(U1, 'device-token-alice');
    await insertDevice(U2, 'device-token-bob');

    const p8 = await makeP8();
    const pushEnv = {
      ...env,
      APNS_KEY_P8: p8,
      APNS_KEY_ID: 'apns-key-id',
      APNS_TEAM_ID: 'apns-team-id',
      APNS_BASE_URL: 'https://apns.test',
    } as unknown as Env;

    const fetchMock = vi.fn(async () => new Response('', { status: 200 }));
    vi.stubGlobal('fetch', fetchMock);

    await app.request(
      '/me/notification-prefs',
      {
        method: 'PATCH',
        headers: jsonAuth(TOKEN_2),
        body: JSON.stringify({ newWeek: false, banter: false }),
      },
      env,
    );

    await pushNewWeek(pushEnv, GROUP, 5);
    expect(fetchMock).toHaveBeenCalledTimes(1);
    const firstUrl = String((fetchMock.mock.calls[0] as unknown[])[0]);
    expect(firstUrl).toContain('device-token-alice');

    // Banter is muted for Bob too.
    await sendPushToUsers(
      pushEnv,
      [U2],
      { title: 'Banter', body: 'hi', groupId: GROUP },
      'banter',
    );
    expect(fetchMock).toHaveBeenCalledTimes(1);

    // Unmuting newWeek lets Bob through again.
    await app.request(
      '/me/notification-prefs',
      {
        method: 'PATCH',
        headers: jsonAuth(TOKEN_2),
        body: JSON.stringify({ newWeek: true }),
      },
      env,
    );
    await pushNewWeek(pushEnv, GROUP, 5);
    expect(fetchMock).toHaveBeenCalledTimes(3);
    const urls = fetchMock.mock.calls.map((call) => String((call as unknown[])[0]));
    expect(urls.some((url) => url.includes('device-token-bob'))).toBe(true);
  });
});
