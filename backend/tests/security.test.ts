import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { env } from 'cloudflare:test';
import { app } from '../src';
import { clearAppleJwksCache, verifyAppleIdentityToken } from '../src/auth/apple';
import { expirePastDeadlineSubmissions, awardAcceptedSubmission } from '../src/services/weeks';
import { bytesToBase64Url, sha256Hex, utf8ToBase64Url } from '../src/lib/crypto';
import {
  CHALLENGE,
  GROUP,
  NOW,
  SUBMISSION,
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
  insertSubmission,
  insertUser,
  insertWeek,
  jsonAuth,
  resetDb,
} from './fixtures';

/** Regression tests for the security-hardening pass. */

async function seedClub(): Promise<void> {
  await insertUser(env.DB, U1, 'Alice', '🦊');
  await insertUser(env.DB, U2, 'Bob', '🐻');
  await insertUser(env.DB, U3, 'Cara', '🐧');
  await insertSession(env.DB, U1, TOKEN_1);
  await insertSession(env.DB, U2, TOKEN_2);
  await insertSession(env.DB, U3, TOKEN_3);
  await insertGroup(env.DB, GROUP, U1, 'ABC234');
  await insertMember(env.DB, GROUP, U1);
  await insertMember(env.DB, GROUP, U2);
  await insertMember(env.DB, GROUP, U3);
  await insertWeek(env.DB, GROUP, WEEK);
  await insertChallenge(env.DB, WEEK, CHALLENGE, 10);
}

beforeEach(async () => {
  await resetDb(env.DB);
  await env.MEDIA.delete('reject-me.jpg');
  await env.MEDIA.delete('expire-me.jpg');
  await env.MEDIA.delete('quota.jpg');
});

afterEach(() => {
  vi.unstubAllGlobals();
  clearAppleJwksCache();
});

describe('bounded JSON bodies', () => {
  it('returns 413 for an oversized streamed body and for a declared oversize', async () => {
    await insertUser(env.DB, U1, 'Alice');
    await insertSession(env.DB, U1, TOKEN_1);

    const huge = JSON.stringify({ displayName: 'a'.repeat(70 * 1024) });
    const streamed = await app.request(
      '/me',
      { method: 'PATCH', headers: jsonAuth(TOKEN_1), body: huge },
      env,
    );
    expect(streamed.status).toBe(413);
    expect(await streamed.json()).toMatchObject({ error: { code: 'payload_too_large' } });

    const declared = await app.request(
      '/me',
      {
        method: 'PATCH',
        headers: { ...jsonAuth(TOKEN_1), 'Content-Length': String(70 * 1024) },
        body: JSON.stringify({ displayName: 'Alice' }),
      },
      env,
    );
    expect(declared.status).toBe(413);
  });
});

describe('R2 media cleanup', () => {
  it('deletes the media object when a submission is rejected by votes', async () => {
    await seedClub();
    await insertSubmission(env.DB, {
      id: SUBMISSION,
      userId: U2,
      status: 'pending',
      eligibleVoters: 2,
      mediaKey: 'reject-me.jpg',
    });
    await env.MEDIA.put('reject-me.jpg', new TextEncoder().encode('proof'));

    const response = await app.request(
      `/submissions/${SUBMISSION}/vote`,
      { method: 'POST', headers: jsonAuth(TOKEN_1), body: JSON.stringify({ approve: false }) },
      env,
    );
    expect(response.status).toBe(200);
    expect(await response.json()).toMatchObject({ submission: { status: 'rejected' } });
    expect(await env.MEDIA.get('reject-me.jpg')).toBeNull();
  });

  it('deletes the media object when a submission expires at the cron deadline', async () => {
    await seedClub();
    await env.DB.prepare("UPDATE weeks SET vote_deadline = ? WHERE id = ?")
      .bind(NOW - 1, WEEK)
      .run();
    await insertSubmission(env.DB, {
      id: SUBMISSION,
      userId: U2,
      status: 'pending',
      mediaKey: 'expire-me.jpg',
    });
    await env.MEDIA.put('expire-me.jpg', new TextEncoder().encode('proof'));

    const expired = await expirePastDeadlineSubmissions(env, NOW);
    expect(expired).toBe(1);

    const row = await env.DB.prepare('SELECT status FROM submissions WHERE id = ?')
      .bind(SUBMISSION)
      .first<{ status: string }>();
    expect(row?.status).toBe('expired');
    expect(await env.MEDIA.get('expire-me.jpg')).toBeNull();
  });
});

describe('upload quota', () => {
  it('returns 429 upload_quota after 30 submissions in the rolling 24h window', async () => {
    await seedClub();
    for (let index = 0; index < 30; index += 1) {
      await insertSubmission(env.DB, {
        id: `quota-${index}`,
        userId: U2,
        status: 'rejected',
        mediaKey: `quota-${index}.jpg`,
        createdAt: NOW - 100,
      });
    }

    const form = new FormData();
    form.set('media', new File([new Uint8Array([1, 2, 3])], 'proof.jpg', { type: 'image/jpeg' }));
    form.set('mediaType', 'photo');
    const response = await app.request(
      `/challenges/${CHALLENGE}/submissions`,
      {
        method: 'POST',
        headers: { ...auth(TOKEN_2), 'Content-Length': '1024' },
        body: form,
      },
      env,
    );
    expect(response.status).toBe(429);
    expect(await response.json()).toMatchObject({ error: { code: 'upload_quota' } });
  });
});

describe('first-finish bonus', () => {
  it('can never record two first_bonus rows for the same challenge', async () => {
    await seedClub();
    await insertSubmission(env.DB, {
      id: 'first-a',
      userId: U1,
      status: 'accepted',
      createdAt: NOW - 200,
      mediaKey: 'first-a.jpg',
    });
    await insertSubmission(env.DB, {
      id: 'first-b',
      userId: U2,
      status: 'accepted',
      createdAt: NOW - 100,
      mediaKey: 'first-b.jpg',
    });

    const a = {
      id: 'first-a',
      user_id: U1,
      challenge_id: CHALLENGE,
      decided_at: null,
      created_at: NOW - 200,
    };
    const b = {
      id: 'first-b',
      user_id: U2,
      challenge_id: CHALLENGE,
      decided_at: null,
      created_at: NOW - 100,
    };

    const awardedA = await awardAcceptedSubmission(env, {
      groupId: GROUP,
      weekId: WEEK,
      submission: a,
      challengePoints: 10,
      now: NOW,
    });
    expect(awardedA).toBe(20); // 10 base + 10 first bonus

    const awardedB = await awardAcceptedSubmission(env, {
      groupId: GROUP,
      weekId: WEEK,
      submission: b,
      challengePoints: 10,
      now: NOW,
    });
    expect(awardedB).toBe(10); // no second first bonus

    const awardedAgain = await awardAcceptedSubmission(env, {
      groupId: GROUP,
      weekId: WEEK,
      submission: a,
      challengePoints: 10,
      now: NOW,
    });
    expect(awardedAgain).toBe(10); // retry does not re-credit the bonus

    const rows = await env.DB.prepare(
      "SELECT challenge_id FROM point_events WHERE kind = 'first_bonus' AND challenge_id = ?",
    )
      .bind(CHALLENGE)
      .all<{ challenge_id: string }>();
    expect(rows.results).toHaveLength(1);
  });
});

describe('group member cap', () => {
  it('serializes concurrent joins so exactly one member can take the last slot', async () => {
    await insertGroup(env.DB, GROUP, U1, 'ABC234');
    await insertMember(env.DB, GROUP, U1);
    for (let index = 0; index < 28; index += 1) {
      await insertMember(env.DB, GROUP, `filler-${index}`, NOW - 4_000 + index);
    }

    const joiners = Array.from({ length: 5 }, (_, index) => ({
      id: `90000000-0000-4000-8000-00000000000${index}`,
      token: `join-token-${index}-0123456789abcdef`,
    }));
    for (const joiner of joiners) {
      await insertUser(env.DB, joiner.id, `Joiner ${joiner.id}`);
      await insertSession(env.DB, joiner.id, joiner.token);
    }

    const responses = await Promise.all(
      joiners.map((joiner) =>
        app.request(
          '/groups/join',
          {
            method: 'POST',
            headers: jsonAuth(joiner.token),
            body: JSON.stringify({ inviteCode: 'ABC234' }),
          },
          env,
        ),
      ),
    );

    const statuses = responses.map((response) => response.status).sort();
    expect(statuses).toEqual([200, 409, 409, 409, 409]);

    const members = await env.DB.prepare(
      'SELECT COUNT(*) AS count FROM group_members WHERE group_id = ?',
    )
      .bind(GROUP)
      .first<{ count: number }>();
    expect(members?.count).toBe(30);
  });
});

describe('logout', () => {
  it('deletes the presented session so the token stops working', async () => {
    await insertUser(env.DB, U1, 'Alice');
    await insertSession(env.DB, U1, TOKEN_1);

    const logout = await app.request(
      '/auth/logout',
      { method: 'POST', headers: auth(TOKEN_1) },
      env,
    );
    expect(logout.status).toBe(200);
    expect(await logout.json()).toEqual({ ok: true });

    const me = await app.request('/me', { headers: auth(TOKEN_1) }, env);
    expect(me.status).toBe(401);
  });
});

describe('Apple nonce replay', () => {
  it('rejects the second use of a verified identity token', async () => {
    const keyPair = (await crypto.subtle.generateKey(
      {
        name: 'RSASSA-PKCS1-v1_5',
        modulusLength: 2048,
        publicExponent: new Uint8Array([1, 0, 1]),
        hash: 'SHA-256',
      },
      true,
      ['sign', 'verify'],
    )) as CryptoKeyPair;

    const jwk = (await crypto.subtle.exportKey('jwk', keyPair.publicKey)) as JsonWebKey;
    const fetchMock = vi.fn(async () =>
      new Response(
        JSON.stringify({
          keys: [
            {
              kty: 'RSA',
              kid: 'test-key',
              use: 'sig',
              alg: 'RS256',
              n: jwk.n,
              e: jwk.e,
            },
          ],
        }),
        { status: 200, headers: { 'content-type': 'application/json' } },
      ),
    );
    vi.stubGlobal('fetch', fetchMock);
    clearAppleJwksCache();

    const rawNonce = `nonce-${crypto.randomUUID()}`;
    const nonce = await sha256Hex(rawNonce);
    const header = utf8ToBase64Url(JSON.stringify({ alg: 'RS256', kid: 'test-key', typ: 'JWT' }));
    const payload = utf8ToBase64Url(
      JSON.stringify({
        iss: 'https://appleid.apple.com',
        aud: env.APPLE_BUNDLE_ID,
        exp: NOW + 300,
        iat: NOW,
        sub: 'apple-replay-subject',
        nonce,
      }),
    );
    const signature = await crypto.subtle.sign(
      { name: 'RSASSA-PKCS1-v1_5' },
      keyPair.privateKey,
      new TextEncoder().encode(`${header}.${payload}`),
    );
    const token = `${header}.${payload}.${bytesToBase64Url(new Uint8Array(signature))}`;

    const first = await verifyAppleIdentityToken(env, token, rawNonce);
    expect(first.sub).toBe('apple-replay-subject');

    await expect(verifyAppleIdentityToken(env, token, rawNonce)).rejects.toMatchObject({
      status: 401,
      code: 'unauthorized',
    });

    const stored = await env.DB.prepare('SELECT nonce_hash, expires_at FROM used_nonces')
      .first<{ nonce_hash: string; expires_at: number }>();
    expect(stored?.nonce_hash).toBe(nonce); // sha256(rawNonce)
    expect(stored?.expires_at).toBe(NOW + 300);
  });
});
