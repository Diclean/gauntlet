import { beforeEach, describe, expect, it } from 'vitest';
import { env } from 'cloudflare:test';
import { app } from '../src';
import {
  CHALLENGE,
  GROUP,
  TOKEN_1,
  U1,
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

/** 6.1 App Store 1.2 house-rules acceptance gate. */

async function seed(): Promise<void> {
  await resetDb(env.DB);
  await insertUser(env.DB, U1, 'Alice', '🦊', { terms: false });
  await insertSession(env.DB, U1, TOKEN_1);
  await insertGroup(env.DB, GROUP, U1, 'ABC234');
  await insertMember(env.DB, GROUP, U1);
  await insertWeek(env.DB, GROUP, WEEK);
  await insertChallenge(env.DB, WEEK, CHALLENGE);
}

beforeEach(seed);

describe('terms acceptance gate', () => {
  it('exposes termsAccepted on /me and gates every write except account management', async () => {
    const me = await app.request('/me', { headers: auth(TOKEN_1) }, env);
    expect(me.status).toBe(200);
    const meBody = (await me.json()) as { user: { termsAccepted: boolean } };
    expect(meBody.user.termsAccepted).toBe(false);

    // Writes are blocked with the dedicated 403 code.
    const blocked = await app.request(
      '/groups',
      {
        method: 'POST',
        headers: jsonAuth(TOKEN_1),
        body: JSON.stringify({ name: 'Nope', timezone: 'UTC' }),
      },
      env,
    );
    expect(blocked.status).toBe(403);
    expect(await blocked.json()).toMatchObject({ error: { code: 'terms_required' } });

    const prefs = await app.request(
      '/me/notification-prefs',
      {
        method: 'PATCH',
        headers: jsonAuth(TOKEN_1),
        body: JSON.stringify({ banter: false }),
      },
      env,
    );
    expect(prefs.status).toBe(403);
    expect(await prefs.json()).toMatchObject({ error: { code: 'terms_required' } });

    // PATCH /me stays available before acceptance.
    const rename = await app.request(
      '/me',
      {
        method: 'PATCH',
        headers: jsonAuth(TOKEN_1),
        body: JSON.stringify({ displayName: 'Alice A.' }),
      },
      env,
    );
    expect(rename.status).toBe(200);
    expect(await rename.json()).toMatchObject({ user: { displayName: 'Alice A.' } });

    const accept = await app.request(
      '/me/accept-terms',
      { method: 'POST', headers: auth(TOKEN_1) },
      env,
    );
    expect(accept.status).toBe(200);
    const accepted = (await accept.json()) as { user: { termsAccepted: boolean } };
    expect(accepted.user.termsAccepted).toBe(true);

    const row = await env.DB.prepare('SELECT terms_accepted_at FROM users WHERE id = ?')
      .bind(U1)
      .first<{ terms_accepted_at: number | null }>();
    expect(row?.terms_accepted_at).toBeGreaterThan(0);

    // The same write now succeeds.
    const created = await app.request(
      '/groups',
      {
        method: 'POST',
        headers: jsonAuth(TOKEN_1),
        body: JSON.stringify({ name: 'House rules club', challengesPerWeek: 3, timezone: 'UTC' }),
      },
      env,
    );
    expect(created.status).toBe(201);
  });

  it('keeps acceptance idempotent', async () => {
    const first = await app.request(
      '/me/accept-terms',
      { method: 'POST', headers: auth(TOKEN_1) },
      env,
    );
    expect(first.status).toBe(200);
    const second = await app.request(
      '/me/accept-terms',
      { method: 'POST', headers: auth(TOKEN_1) },
      env,
    );
    expect(second.status).toBe(200);
    expect(await second.json()).toMatchObject({ user: { termsAccepted: true } });
  });
});
