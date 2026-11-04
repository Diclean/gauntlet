import { beforeEach, describe, expect, it } from 'vitest';
import { env } from 'cloudflare:test';
import { app } from '../src';
import {
  CHALLENGE,
  GROUP,
  GROUP2,
  MEDIA_KEY,
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
  insertPointEvent,
  insertSession,
  insertSubmission,
  insertUser,
  insertWeek,
  jsonAuth,
  resetDb,
} from './fixtures';

/** 6.2 report threshold, blocks and owner removal/ban. */

const U4 = '44444444-4444-4444-8444-444444444444';
const TOKEN_4 = 'token-for-user-4-0123456789abcdef';

const WEEK2 = 'cccccccc-cccc-4ccc-8ccc-ccccccccccc2';
const CHALLENGE2 = 'dddddddd-dddd-4ddd-8ddd-ddddddddddd2';
const SUBMISSION = 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeee1';
const SUBMISSION_BLOCKED = 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeee2';

async function seed(): Promise<void> {
  await resetDb(env.DB);
  await env.MEDIA.delete(`${SUBMISSION}.jpg`);

  await insertUser(env.DB, U1, 'Alice', '🦊');
  await insertUser(env.DB, U2, 'Bob', '🐻');
  await insertUser(env.DB, U3, 'Cara', '🐧');
  await insertUser(env.DB, U4, 'Dan', '🐢');
  await insertSession(env.DB, U1, TOKEN_1);
  await insertSession(env.DB, U2, TOKEN_2);
  await insertSession(env.DB, U3, TOKEN_3);
  await insertSession(env.DB, U4, TOKEN_4);

  await insertGroup(env.DB, GROUP, U1, 'ABC234');
  await insertMember(env.DB, GROUP, U1);
  await insertMember(env.DB, GROUP, U2);
  await insertMember(env.DB, GROUP, U3);
  await insertMember(env.DB, GROUP, U4);
  await insertWeek(env.DB, GROUP, WEEK);
  await insertChallenge(env.DB, WEEK, CHALLENGE);

  // Bob's accepted proof with captain points (removed after reports).
  await insertSubmission(env.DB, {
    id: SUBMISSION,
    userId: U2,
    status: 'accepted',
    eligibleVoters: 3,
  });
  await insertPointEvent(env.DB, {
    weekId: WEEK,
    userId: U2,
    kind: 'challenge',
    points: 10,
    submissionId: SUBMISSION,
  });
  await insertPointEvent(env.DB, {
    weekId: WEEK,
    userId: U2,
    kind: 'captain',
    points: 10,
    submissionId: SUBMISSION,
  });
}

beforeEach(seed);

async function feedIds(token: string): Promise<string[]> {
  const response = await app.request(`/groups/${GROUP}/feed`, { headers: auth(token) }, env);
  expect(response.status).toBe(200);
  const body = (await response.json()) as { items: Array<{ id: string }> };
  return body.items.map((item) => item.id);
}

async function report(token: string, submissionId: string, reason = 'spam') {
  return await app.request(
    `/submissions/${submissionId}/report`,
    {
      method: 'POST',
      headers: jsonAuth(token),
      body: JSON.stringify({ reason }),
    },
    env,
  );
}

describe('reports', () => {
  it('hides the proof for the reporter immediately, then removes it at the threshold', async () => {
    const first = await report(TOKEN_1, SUBMISSION);
    expect(first.status).toBe(200);
    expect(await first.json()).toEqual({ ok: true });

    expect(await feedIds(TOKEN_1)).not.toContain(SUBMISSION);
    expect(await feedIds(TOKEN_4)).toContain(SUBMISSION);

    const duplicate = await report(TOKEN_1, SUBMISSION);
    expect(duplicate.status).toBe(409);
    expect(await duplicate.json()).toMatchObject({ error: { code: 'already_reported' } });

    // 4 members => max(2, ceil(4/3)) = 2 distinct reporters.
    const second = await report(TOKEN_3, SUBMISSION, 'harassment');
    expect(second.status).toBe(200);

    const row = await env.DB.prepare('SELECT status FROM submissions WHERE id = ?')
      .bind(SUBMISSION)
      .first<{ status: string }>();
    expect(row?.status).toBe('removed');

    expect(await feedIds(TOKEN_4)).not.toContain(SUBMISSION);
    expect(await feedIds(TOKEN_1)).not.toContain(SUBMISSION);

    // The submitter still sees their own removed proof.
    expect(await feedIds(TOKEN_2)).toContain(SUBMISSION);
    const own = await app.request(`/submissions/${SUBMISSION}`, { headers: auth(TOKEN_2) }, env);
    expect(own.status).toBe(200);
    expect(await own.json()).toMatchObject({ submission: { status: 'removed' } });
    const other = await app.request(`/submissions/${SUBMISSION}`, { headers: auth(TOKEN_4) }, env);
    expect(other.status).toBe(404);

    // A removed proof loses its ledger rows (challenge + captain).
    const events = await env.DB.prepare('SELECT COUNT(*) AS count FROM point_events WHERE submission_id = ?')
      .bind(SUBMISSION)
      .first<{ count: number }>();
    expect(events?.count).toBe(0);
  });

  it('rejects reporting your own content and unknown reasons', async () => {
    const own = await report(TOKEN_2, SUBMISSION);
    expect(own.status).toBe(400);

    const invalid = await report(TOKEN_1, SUBMISSION, 'not-a-reason');
    expect(invalid.status).toBe(400);
  });
});

describe('blocks', () => {
  beforeEach(async () => {
    await insertGroup(env.DB, GROUP2, U1, 'XYZ789', 'Second club');
    await insertMember(env.DB, GROUP2, U1);
    await insertMember(env.DB, GROUP2, U2);
    await insertMember(env.DB, GROUP2, U3);
    await insertWeek(env.DB, GROUP2, WEEK2);
    await insertChallenge(env.DB, WEEK2, CHALLENGE2);
    await insertSubmission(env.DB, {
      id: SUBMISSION_BLOCKED,
      challengeId: CHALLENGE2,
      userId: U2,
      status: 'pending',
      eligibleVoters: 2,
      mediaKey: 'blocked.jpg',
    });
  });

  it('hides the blocked member from feed and pending votes without changing thresholds', async () => {
    const block = await app.request(
      `/users/${U2}/block`,
      { method: 'POST', headers: auth(TOKEN_1) },
      env,
    );
    expect(block.status).toBe(200);

    const blocks = await app.request('/me/blocks', { headers: auth(TOKEN_1) }, env);
    expect(blocks.status).toBe(200);
    const blocksBody = (await blocks.json()) as { users: Array<{ id: string }> };
    expect(blocksBody.users.map((user) => user.id)).toEqual([U2]);

    const feed = await app.request(`/groups/${GROUP2}/feed`, { headers: auth(TOKEN_1) }, env);
    const feedBody = (await feed.json()) as { items: Array<{ id: string }> };
    expect(feedBody.items.map((item) => item.id)).not.toContain(SUBMISSION_BLOCKED);

    const pending = await app.request(
      `/groups/${GROUP2}/votes/pending`,
      { headers: auth(TOKEN_1) },
      env,
    );
    const pendingBody = (await pending.json()) as { items: Array<{ id: string }> };
    expect(pendingBody.items.map((item) => item.id)).not.toContain(SUBMISSION_BLOCKED);

    // Direct access is hidden too.
    const direct = await app.request(
      `/submissions/${SUBMISSION_BLOCKED}`,
      { headers: auth(TOKEN_1) },
      env,
    );
    expect(direct.status).toBe(404);

    // eligible_voters stays 2: one approval is not enough even though the
    // blocker can no longer see (and therefore cannot vote on) the proof.
    const vote = await app.request(
      `/submissions/${SUBMISSION_BLOCKED}/vote`,
      { method: 'POST', headers: jsonAuth(TOKEN_3), body: JSON.stringify({ approve: true }) },
      env,
    );
    expect(vote.status).toBe(200);
    expect(await vote.json()).toMatchObject({ submission: { status: 'pending', approvals: 1 } });

    const unblock = await app.request(
      `/users/${U2}/block`,
      { method: 'DELETE', headers: auth(TOKEN_1) },
      env,
    );
    expect(unblock.status).toBe(200);
    const after = await app.request(`/groups/${GROUP2}/feed`, { headers: auth(TOKEN_1) }, env);
    const afterBody = (await after.json()) as { items: Array<{ id: string }> };
    expect(afterBody.items.map((item) => item.id)).toContain(SUBMISSION_BLOCKED);
  });
});

describe('owner removal + ban', () => {
  it('expires pending proofs, bans rejoining and lets the owner lift the ban', async () => {
    await insertSubmission(env.DB, {
      id: 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeee9',
      userId: U2,
      status: 'pending',
    });

    const notOwner = await app.request(
      `/groups/${GROUP}/members/${U3}/remove`,
      { method: 'POST', headers: auth(TOKEN_2) },
      env,
    );
    expect(notOwner.status).toBe(403);

    const self = await app.request(
      `/groups/${GROUP}/members/${U1}/remove`,
      { method: 'POST', headers: auth(TOKEN_1) },
      env,
    );
    expect(self.status).toBe(400);

    const removed = await app.request(
      `/groups/${GROUP}/members/${U2}/remove`,
      { method: 'POST', headers: auth(TOKEN_1) },
      env,
    );
    expect(removed.status).toBe(200);

    const membership = await env.DB.prepare(
      'SELECT 1 AS one FROM group_members WHERE group_id = ? AND user_id = ?',
    )
      .bind(GROUP, U2)
      .first();
    expect(membership).toBeNull();

    const pending = await env.DB.prepare(
      'SELECT status FROM submissions WHERE user_id = ? AND status = ?',
    )
      .bind(U2, 'pending')
      .all<{ status: string }>();
    expect(pending.results).toHaveLength(0);

    const join = await app.request(
      '/groups/join',
      {
        method: 'POST',
        headers: jsonAuth(TOKEN_2),
        body: JSON.stringify({ inviteCode: 'ABC234' }),
      },
      env,
    );
    expect(join.status).toBe(403);
    expect(await join.json()).toMatchObject({ error: { code: 'banned' } });

    const lift = await app.request(
      `/groups/${GROUP}/members/${U2}/ban`,
      { method: 'DELETE', headers: auth(TOKEN_1) },
      env,
    );
    expect(lift.status).toBe(200);

    const rejoin = await app.request(
      '/groups/join',
      {
        method: 'POST',
        headers: jsonAuth(TOKEN_2),
        body: JSON.stringify({ inviteCode: 'ABC234' }),
      },
      env,
    );
    expect(rejoin.status).toBe(200);
  });
});

describe('DELETE /submissions/:id', () => {
  it('lets only the submitter delete the proof, its media and its ledger rows', async () => {
    const mediaKey = MEDIA_KEY;
    await env.MEDIA.put(mediaKey, new TextEncoder().encode('proof'), {
      httpMetadata: { contentType: 'image/jpeg' },
    });
    await env.DB.prepare(
      'INSERT INTO votes (submission_id, voter_id, approve, created_at) VALUES (?, ?, 1, ?)',
    )
      .bind(SUBMISSION, U1, Math.floor(Date.now() / 1000))
      .run();
    await env.DB.prepare(
      'INSERT INTO comments (id, submission_id, user_id, text, created_at) VALUES (?, ?, ?, ?, ?)',
    )
      .bind('comment-1', SUBMISSION, U1, 'nice', Math.floor(Date.now() / 1000))
      .run();
    await env.DB.prepare(
      'INSERT INTO reactions (user_id, submission_id, emoji, created_at) VALUES (?, ?, ?, ?)',
    )
      .bind(U1, SUBMISSION, '🔥', Math.floor(Date.now() / 1000))
      .run();

    const foreign = await app.request(`/submissions/${SUBMISSION}`, {
      method: 'DELETE',
      headers: auth(TOKEN_1),
    }, env);
    expect(foreign.status).toBe(403);

    const own = await app.request(`/submissions/${SUBMISSION}`, {
      method: 'DELETE',
      headers: auth(TOKEN_2),
    }, env);
    expect(own.status).toBe(200);
    expect(await own.json()).toEqual({ ok: true });

    expect(await env.MEDIA.get(mediaKey)).toBeNull();
    for (const [table, column] of [
      ['submissions', 'id'],
      ['votes', 'submission_id'],
      ['comments', 'submission_id'],
      ['reactions', 'submission_id'],
      ['point_events', 'submission_id'],
    ] as const) {
      const row = await env.DB.prepare(
        `SELECT COUNT(*) AS count FROM ${table} WHERE ${column} = ?`,
      )
        .bind(SUBMISSION)
        .first<{ count: number }>();
      expect(row?.count, table).toBe(0);
    }
  });
});
