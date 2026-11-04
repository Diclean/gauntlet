import { beforeEach, describe, expect, it } from 'vitest';
import { env } from 'cloudflare:test';
import { app } from '../src';
import {
  CHALLENGE,
  GROUP,
  MEDIA_KEY,
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

async function seed(): Promise<void> {
  await resetDb(env.DB);
  await env.MEDIA.delete(MEDIA_KEY);

  await insertUser(env.DB, U1, 'Alice', '🦊');
  await insertUser(env.DB, U2, 'Bob', '🐻');
  await insertUser(env.DB, U3, 'Mallory', '🐍');
  await insertSession(env.DB, U1, TOKEN_1);
  await insertSession(env.DB, U2, TOKEN_2);
  await insertSession(env.DB, U3, TOKEN_3);

  await insertGroup(env.DB, GROUP, U1, 'ABC234');
  await insertMember(env.DB, GROUP, U1);
  await insertMember(env.DB, GROUP, U2);
  await insertWeek(env.DB, GROUP, WEEK);
  await insertChallenge(env.DB, WEEK, CHALLENGE, 10);
  await insertSubmission(env.DB, { id: SUBMISSION, eligibleVoters: 1 });

  await env.MEDIA.put(MEDIA_KEY, new TextEncoder().encode('0123456789'), {
    httpMetadata: { contentType: 'image/jpeg' },
  });
}

beforeEach(seed);

describe('authentication', () => {
  it('rejects requests without a bearer token', async () => {
    const response = await app.request(`/groups/${GROUP}`, {}, env);
    expect(response.status).toBe(401);
    expect(await response.json()).toMatchObject({ error: { code: 'unauthorized' } });
  });

  it('rejects unknown session tokens', async () => {
    const response = await app.request(`/groups/${GROUP}`, { headers: auth('not-a-real-token') }, env);
    expect(response.status).toBe(401);
  });

  it('serves /health without auth', async () => {
    const response = await app.request('/health', {}, env);
    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({ ok: true });
  });
});

describe('membership authorization', () => {
  it('lets members read a group and blocks non-members with 403', async () => {
    const member = await app.request(`/groups/${GROUP}`, { headers: auth(TOKEN_1) }, env);
    expect(member.status).toBe(200);
    const body = (await member.json()) as { group: { id: string; memberCount: number }; members: unknown[] };
    expect(body.group.id).toBe(GROUP);
    expect(body.group.memberCount).toBe(2);
    expect(body.members).toHaveLength(2);

    const outsider = await app.request(`/groups/${GROUP}`, { headers: auth(TOKEN_3) }, env);
    expect(outsider.status).toBe(403);
    expect(await outsider.json()).toMatchObject({ error: { code: 'forbidden' } });
  });

  it('lets members read a submission and blocks non-members with 403', async () => {
    const member = await app.request(`/submissions/${SUBMISSION}`, { headers: auth(TOKEN_2) }, env);
    expect(member.status).toBe(200);
    const body = (await member.json()) as { submission: { status: string; mediaUrl: string } };
    expect(body.submission.status).toBe('pending');
    expect(body.submission.mediaUrl).toBe(`/media/${MEDIA_KEY}`);

    const outsider = await app.request(`/submissions/${SUBMISSION}`, { headers: auth(TOKEN_3) }, env);
    expect(outsider.status).toBe(403);
  });

  it('lets members read the feed and blocks non-members with 403', async () => {
    const member = await app.request(`/groups/${GROUP}/feed`, { headers: auth(TOKEN_1) }, env);
    expect(member.status).toBe(200);
    const body = (await member.json()) as { items: Array<{ id: string }>; nextCursor: string | null };
    expect(body.items[0]?.id).toBe(SUBMISSION);
    expect(body.nextCursor).toBeNull();

    const outsider = await app.request(`/groups/${GROUP}/feed`, { headers: auth(TOKEN_3) }, env);
    expect(outsider.status).toBe(403);
  });

  it('lets members read the current week with their challenge statuses', async () => {
    const member = await app.request(`/groups/${GROUP}/week`, { headers: auth(TOKEN_1) }, env);
    expect(member.status).toBe(200);
    const body = (await member.json()) as {
      week: { id: string; startsAt: number };
      challenges: Array<{ id: string; myStatus: string }>;
    };
    expect(body.week.id).toBe(WEEK);
    expect(body.challenges).toHaveLength(1);
    expect(body.challenges[0]).toMatchObject({ id: CHALLENGE, myStatus: 'pending' });

    const otherMember = await app.request(`/groups/${GROUP}/week`, { headers: auth(TOKEN_2) }, env);
    const otherBody = (await otherMember.json()) as { challenges: Array<{ myStatus: string }> };
    expect(otherBody.challenges[0]!.myStatus).toBe('todo');

    const outsider = await app.request(`/groups/${GROUP}/week`, { headers: auth(TOKEN_3) }, env);
    expect(outsider.status).toBe(403);
  });

  it('returns the group leaderboard to members only', async () => {
    const member = await app.request(
      `/groups/${GROUP}/leaderboard?scope=all`,
      { headers: auth(TOKEN_1) },
      env,
    );
    expect(member.status).toBe(200);
    const body = (await member.json()) as {
      entries: Array<{ points: number; rank: number; streak: number }>;
    };
    expect(body.entries).toHaveLength(2);
    expect(body.entries[0]!.points).toBe(0);
    expect(body.entries[0]!.rank).toBe(1);

    const outsider = await app.request(
      `/groups/${GROUP}/leaderboard`,
      { headers: auth(TOKEN_3) },
      env,
    );
    expect(outsider.status).toBe(403);
  });

  it('never exposes media to non-members', async () => {
    const member = await app.request(`/media/${MEDIA_KEY}`, { headers: auth(TOKEN_2) }, env);
    expect(member.status).toBe(200);
    expect(new TextDecoder().decode(await member.arrayBuffer())).toBe('0123456789');
    expect(member.headers.get('content-type')).toBe('image/jpeg');
    expect(member.headers.get('cache-control')).toContain('private');

    const outsider = await app.request(`/media/${MEDIA_KEY}`, { headers: auth(TOKEN_3) }, env);
    expect(outsider.status).toBe(403);
  });

  it('supports single Range requests for video scrubbing', async () => {
    const response = await app.request(
      `/media/${MEDIA_KEY}`,
      { headers: { ...auth(TOKEN_1), Range: 'bytes=2-5' } },
      env,
    );
    expect(response.status).toBe(206);
    expect(response.headers.get('content-range')).toBe('bytes 2-5/10');
    expect(response.headers.get('content-length')).toBe('4');
    expect(new TextDecoder().decode(await response.arrayBuffer())).toBe('2345');

    const suffix = await app.request(
      `/media/${MEDIA_KEY}`,
      { headers: { ...auth(TOKEN_1), Range: 'bytes=-3' } },
      env,
    );
    expect(suffix.status).toBe(206);
    expect(new TextDecoder().decode(await suffix.arrayBuffer())).toBe('789');

    const invalid = await app.request(
      `/media/${MEDIA_KEY}`,
      { headers: { ...auth(TOKEN_1), Range: 'bytes=99-100' } },
      env,
    );
    expect(invalid.status).toBe(416);
    expect(invalid.headers.get('content-range')).toBe('bytes */10');
  });

  it('returns 404 for an unknown media key to members', async () => {
    const response = await app.request('/media/nope.jpg', { headers: auth(TOKEN_1) }, env);
    expect(response.status).toBe(404);
  });
});

describe('voting + points', () => {
  it('accepts at threshold, records a vote and awards challenge + first bonus points', async () => {
    const response = await app.request(
      `/submissions/${SUBMISSION}/vote`,
      { method: 'POST', headers: jsonAuth(TOKEN_2), body: JSON.stringify({ approve: true }) },
      env,
    );
    expect(response.status).toBe(200);
    const body = (await response.json()) as {
      submission: { status: string; approvals: number; rejections: number; myVote: boolean | null; decidedAt: number | null };
    };
    expect(body.submission.status).toBe('accepted');
    expect(body.submission.approvals).toBe(1);
    expect(body.submission.rejections).toBe(0);
    expect(body.submission.myVote).toBe(true);
    expect(body.submission.decidedAt).toBeGreaterThan(0);

    const events = await env.DB.prepare(
      'SELECT kind, points FROM point_events WHERE submission_id = ? ORDER BY kind ASC',
    )
      .bind(SUBMISSION)
      .all<{ kind: string; points: number }>();
    expect(events.results).toEqual([
      { kind: 'challenge', points: 10 },
      { kind: 'first_bonus', points: 10 },
    ]);
  });

  it('rejects at threshold', async () => {
    const response = await app.request(
      `/submissions/${SUBMISSION}/vote`,
      { method: 'POST', headers: jsonAuth(TOKEN_2), body: JSON.stringify({ approve: false }) },
      env,
    );
    expect(response.status).toBe(200);
    const body = (await response.json()) as { submission: { status: string; rejections: number } };
    expect(body.submission.status).toBe('rejected');
    expect(body.submission.rejections).toBe(1);
  });

  it('forbids voting on your own submission', async () => {
    const response = await app.request(
      `/submissions/${SUBMISSION}/vote`,
      { method: 'POST', headers: jsonAuth(TOKEN_1), body: JSON.stringify({ approve: true }) },
      env,
    );
    expect(response.status).toBe(403);
  });

  it('forbids outsiders from voting', async () => {
    const response = await app.request(
      `/submissions/${SUBMISSION}/vote`,
      { method: 'POST', headers: jsonAuth(TOKEN_3), body: JSON.stringify({ approve: true }) },
      env,
    );
    expect(response.status).toBe(403);
  });

  it('refuses a second vote once the submission is decided', async () => {
    await app.request(
      `/submissions/${SUBMISSION}/vote`,
      { method: 'POST', headers: jsonAuth(TOKEN_2), body: JSON.stringify({ approve: true }) },
      env,
    );
    const again = await app.request(
      `/submissions/${SUBMISSION}/vote`,
      { method: 'POST', headers: jsonAuth(TOKEN_2), body: JSON.stringify({ approve: false }) },
      env,
    );
    expect(again.status).toBe(409);
    expect(await again.json()).toMatchObject({ error: { code: 'submission_decided' } });
  });
});

describe('submission upload', () => {
  it('accepts a camera photo multipart upload and stores it privately in R2', async () => {
    const form = new FormData();
    form.set(
      'media',
      new File([new Uint8Array([0xff, 0xd8, 0xff, 0xe0, 1, 2, 3])], 'proof.jpg', {
        type: 'image/jpeg',
      }),
    );
    form.set('mediaType', 'photo');
    form.set('caption', '  Proof!  ');

    const response = await app.request(
      `/challenges/${CHALLENGE}/submissions`,
      { method: 'POST', headers: { ...auth(TOKEN_2), 'Content-Length': '1024' }, body: form },
      env,
    );
    expect(response.status).toBe(201);
    const body = (await response.json()) as {
      submission: {
        id: string;
        challengeId: string;
        caption: string | null;
        status: string;
        eligibleVoters: number;
        mediaUrl: string;
        mediaType: string;
      };
    };
    expect(body.submission.challengeId).toBe(CHALLENGE);
    expect(body.submission.caption).toBe('Proof!');
    expect(body.submission.status).toBe('pending');
    expect(body.submission.eligibleVoters).toBe(1);
    expect(body.submission.mediaType).toBe('photo');
    expect(body.submission.mediaUrl).toMatch(/^\/media\/[0-9a-f-]+\.jpg$/u);

    const stored = await env.MEDIA.get(body.submission.mediaUrl.replace('/media/', ''));
    expect(stored).not.toBeNull();
    expect(stored!.httpMetadata?.contentType).toBe('image/jpeg');

    // The other group member can stream it.
    const media = await app.request(
      body.submission.mediaUrl,
      { headers: auth(TOKEN_1) },
      env,
    );
    expect(media.status).toBe(200);
    expect(await media.arrayBuffer()).toBeInstanceOf(ArrayBuffer);
  });

  it('enforces the MIME allowlist and rejects unknown multipart fields', async () => {
    const wrongType = new FormData();
    wrongType.set('media', new File([new Uint8Array([1])], 'proof.txt', { type: 'text/plain' }));
    wrongType.set('mediaType', 'photo');
    const unsupported = await app.request(
      `/challenges/${CHALLENGE}/submissions`,
      { method: 'POST', headers: { ...auth(TOKEN_2), 'Content-Length': '1024' }, body: wrongType },
      env,
    );
    expect(unsupported.status).toBe(415);
    expect(await unsupported.json()).toMatchObject({
      error: { code: 'unsupported_media_type' },
    });

    const extraField = new FormData();
    extraField.set('media', new File([new Uint8Array([1])], 'proof.jpg', { type: 'image/jpeg' }));
    extraField.set('mediaType', 'photo');
    extraField.set('surprise', 'nope');
    const unknown = await app.request(
      `/challenges/${CHALLENGE}/submissions`,
      { method: 'POST', headers: { ...auth(TOKEN_2), 'Content-Length': '1024' }, body: extraField },
      env,
    );
    expect(unknown.status).toBe(400);
  });

  it('requires a numeric Content-Length and rejects an oversized declared body before parsing', async () => {
    const form = new FormData();
    form.set('media', new File([new Uint8Array([1])], 'proof.jpg', { type: 'image/jpeg' }));
    form.set('mediaType', 'photo');

    const missing = await app.request(
      `/challenges/${CHALLENGE}/submissions`,
      { method: 'POST', headers: auth(TOKEN_2), body: form },
      env,
    );
    expect(missing.status).toBe(411);
    expect(await missing.json()).toMatchObject({ error: { code: 'length_required' } });

    const nonNumeric = await app.request(
      `/challenges/${CHALLENGE}/submissions`,
      { method: 'POST', headers: { ...auth(TOKEN_2), 'Content-Length': 'nope' }, body: form },
      env,
    );
    expect(nonNumeric.status).toBe(411);

    const oversized = await app.request(
      `/challenges/${CHALLENGE}/submissions`,
      {
        method: 'POST',
        headers: { ...auth(TOKEN_2), 'Content-Length': String(60 * 1024 * 1024) },
        body: form,
      },
      env,
    );
    expect(oversized.status).toBe(413);
  });

  it('rejects a second active submission for the same challenge', async () => {
    for (let attempt = 0; attempt < 2; attempt += 1) {
      const form = new FormData();
      form.set('media', new File([new Uint8Array([1, 2, 3])], 'proof.jpg', { type: 'image/jpeg' }));
      form.set('mediaType', 'photo');
      const response = await app.request(
        `/challenges/${CHALLENGE}/submissions`,
        { method: 'POST', headers: { ...auth(TOKEN_2), 'Content-Length': '1024' }, body: form },
        env,
      );
      if (attempt === 0) expect(response.status).toBe(201);
      else {
        expect(response.status).toBe(409);
        expect(await response.json()).toMatchObject({ error: { code: 'submission_pending' } });
      }
    }
  });
});

describe('joining groups', () => {
  it('joins with a case-insensitive invite code and rejects unknown codes', async () => {
    const joined = await app.request(
      '/groups/join',
      {
        method: 'POST',
        headers: jsonAuth(TOKEN_3),
        body: JSON.stringify({ inviteCode: 'abc234' }),
      },
      env,
    );
    expect(joined.status).toBe(200);
    const body = (await joined.json()) as { group: { id: string; memberCount: number } };
    expect(body.group.id).toBe(GROUP);
    expect(body.group.memberCount).toBe(3);

    const nowMember = await app.request(`/groups/${GROUP}`, { headers: auth(TOKEN_3) }, env);
    expect(nowMember.status).toBe(200);

    const unknown = await app.request(
      '/groups/join',
      {
        method: 'POST',
        headers: jsonAuth(TOKEN_3),
        body: JSON.stringify({ inviteCode: 'ZZZZZZ' }),
      },
      env,
    );
    expect(unknown.status).toBe(404);
    expect(await unknown.json()).toMatchObject({ error: { code: 'invalid_invite_code' } });
  });
});

describe('group creation', () => {
  it('creates a group and immediately generates the current week', async () => {
    const response = await app.request(
      '/groups',
      {
        method: 'POST',
        headers: jsonAuth(TOKEN_3),
        body: JSON.stringify({ name: 'Fresh group', challengesPerWeek: 3, timezone: 'UTC' }),
      },
      env,
    );
    expect(response.status).toBe(201);
    const body = (await response.json()) as {
      group: { id: string; name: string; memberCount: number; inviteCode: string; ownerId: string };
    };
    expect(body.group.name).toBe('Fresh group');
    expect(body.group.memberCount).toBe(1);
    expect(body.group.ownerId).toBe(U3);
    expect(body.group.inviteCode).toMatch(/^[A-Z2-9]{6}$/u);

    const week = await app.request(`/groups/${body.group.id}/week`, { headers: auth(TOKEN_3) }, env);
    expect(week.status).toBe(200);
    const weekBody = (await week.json()) as {
      week: { status: string };
      challenges: Array<{ title: string; points: number; myStatus: string }>;
    };
    expect(weekBody.week.status).toBe('open');
    expect(weekBody.challenges).toHaveLength(3);
    for (const challenge of weekBody.challenges) {
      expect(challenge.points).toBeGreaterThan(0);
      expect(challenge.myStatus).toBe('todo');
    }

    const patch = await app.request(
      `/groups/${body.group.id}`,
      {
        method: 'PATCH',
        headers: jsonAuth(TOKEN_3),
        body: JSON.stringify({ name: 'Renamed', challengesPerWeek: 4 }),
      },
      env,
    );
    expect(patch.status).toBe(200);
    expect((await patch.json()) as { group: { name: string } }).toMatchObject({
      group: { name: 'Renamed', challengesPerWeek: 4 },
    });

    const intruder = await app.request(
      `/groups/${body.group.id}`,
      { method: 'PATCH', headers: jsonAuth(TOKEN_1), body: JSON.stringify({ name: 'Hacked' }) },
      env,
    );
    expect(intruder.status).toBe(403);
  });
});

describe('account deletion', () => {
  it('removes the account, its media, and transfers an owned group', async () => {
    const response = await app.request('/me', { method: 'DELETE', headers: auth(TOKEN_1) }, env);
    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({ ok: true });

    const user = await env.DB.prepare('SELECT id FROM users WHERE id = ?').bind(U1).first();
    expect(user).toBeNull();
    expect(await env.MEDIA.get(MEDIA_KEY)).toBeNull();

    const submission = await env.DB.prepare('SELECT id FROM submissions WHERE id = ?')
      .bind(SUBMISSION)
      .first();
    expect(submission).toBeNull();

    const group = await env.DB.prepare('SELECT owner_id FROM groups WHERE id = ?')
      .bind(GROUP)
      .first<{ owner_id: string }>();
    expect(group?.owner_id).toBe(U2);

    const staleSession = await app.request('/me', { headers: auth(TOKEN_1) }, env);
    expect(staleSession.status).toBe(401);

    const newOwner = await app.request(`/groups/${GROUP}`, { headers: auth(TOKEN_2) }, env);
    expect(newOwner.status).toBe(200);
  });
});

describe('request validation', () => {
  it('rejects unknown body fields', async () => {
    const response = await app.request(
      '/me',
      {
        method: 'PATCH',
        headers: jsonAuth(TOKEN_1),
        body: JSON.stringify({ displayName: 'New name', hacker: true }),
      },
      env,
    );
    expect(response.status).toBe(400);
    expect(await response.json()).toMatchObject({ error: { code: 'validation_error' } });
  });

  it('rejects invalid invite codes', async () => {
    const response = await app.request(
      '/groups/join',
      {
        method: 'POST',
        headers: jsonAuth(TOKEN_3),
        body: JSON.stringify({ inviteCode: 'abc' }),
      },
      env,
    );
    expect(response.status).toBe(400);
  });

  it('rejects an empty PATCH', async () => {
    const response = await app.request(
      '/me',
      { method: 'PATCH', headers: jsonAuth(TOKEN_1), body: JSON.stringify({}) },
      env,
    );
    expect(response.status).toBe(400);
  });
});
