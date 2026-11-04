import { beforeEach, describe, expect, it } from 'vitest';
import { env } from 'cloudflare:test';
import { app } from '../src';
import { claimBanterPush } from '../src/push';
import {
  GROUP,
  NOW,
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

/** 6.5 reactions + comments, including visibility and delete permissions. */

const SUBMISSION = 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeee1';

async function seed(): Promise<void> {
  await resetDb(env.DB);
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
  await insertChallenge(env.DB, WEEK);
  await insertSubmission(env.DB, {
    id: SUBMISSION,
    userId: U1,
    status: 'pending',
    eligibleVoters: 2,
  });
}

beforeEach(seed);

interface ReactionJson {
  emoji: string;
  count: number;
  mine: boolean;
}

async function react(token: string, emoji: string) {
  return await app.request(
    `/submissions/${SUBMISSION}/reactions`,
    {
      method: 'POST',
      headers: jsonAuth(token),
      body: JSON.stringify({ emoji }),
    },
    env,
  );
}

async function getSubmission(token: string): Promise<{
  reactions: ReactionJson[];
  commentCount: number;
}> {
  const response = await app.request(`/submissions/${SUBMISSION}`, { headers: auth(token) }, env);
  expect(response.status).toBe(200);
  const body = (await response.json()) as {
    submission: { reactions: ReactionJson[]; commentCount: number };
  };
  return body.submission;
}

async function comment(token: string, text: string) {
  return await app.request(
    `/submissions/${SUBMISSION}/comments`,
    {
      method: 'POST',
      headers: jsonAuth(token),
      body: JSON.stringify({ text }),
    },
    env,
  );
}

describe('reactions', () => {
  it('rejects emojis outside the six allowed ones', async () => {
    for (const emoji of ['💩', '❤️', '', 'fire']) {
      const response = await react(TOKEN_2, emoji);
      expect(response.status, emoji).toBe(400);
    }
  });

  it('toggles one row per user/emoji and serializes counts in fixed order', async () => {
    const first = await react(TOKEN_2, '🔥');
    expect(first.status).toBe(200);
    expect(((await first.json()) as { submission: { reactions: ReactionJson[] } }).submission.reactions).toEqual([
      { emoji: '🔥', count: 1, mine: true },
    ]);

    await react(TOKEN_3, '🔥');
    await react(TOKEN_3, '👏');
    expect(await getSubmission(TOKEN_2)).toMatchObject({
      reactions: [
        { emoji: '🔥', count: 2, mine: true },
        { emoji: '👏', count: 1, mine: false },
      ],
      commentCount: 0,
    });

    const off = await react(TOKEN_2, '🔥');
    expect(off.status).toBe(200);
    expect(
      ((await off.json()) as { submission: { reactions: ReactionJson[] } }).submission.reactions,
    ).toEqual([
      { emoji: '🔥', count: 1, mine: false },
      { emoji: '👏', count: 1, mine: false },
    ]);
  });
});

describe('comments', () => {
  it('validates length, trims text and orders oldest first', async () => {
    expect((await comment(TOKEN_2, '')).status).toBe(400);
    expect((await comment(TOKEN_2, '   ')).status).toBe(400);
    expect((await comment(TOKEN_2, 'x'.repeat(281))).status).toBe(400);

    const first = await comment(TOKEN_2, '  Hello there  ');
    expect(first.status).toBe(201);
    expect(await first.json()).toMatchObject({
      comment: { text: 'Hello there', canDelete: true, user: { id: U2 } },
    });

    await new Promise((resolve) => setTimeout(resolve, 5));
    await comment(TOKEN_3, 'Yo');

    const list = await app.request(`/submissions/${SUBMISSION}/comments`, {
      headers: auth(TOKEN_3),
    }, env);
    expect(list.status).toBe(200);
    const body = (await list.json()) as {
      comments: Array<{ id: string; user: { id: string }; text: string; canDelete: boolean }>;
    };
    expect(body.comments.map((item) => item.text)).toEqual(['Hello there', 'Yo']);
    expect(body.comments[0]!.canDelete).toBe(false);
    expect(body.comments[1]!.canDelete).toBe(true);

    const ownerView = await app.request(`/submissions/${SUBMISSION}/comments`, {
      headers: auth(TOKEN_1),
    }, env);
    const ownerBody = (await ownerView.json()) as { comments: Array<{ canDelete: boolean }> };
    expect(ownerBody.comments.every((item) => item.canDelete)).toBe(true);
    expect(await getSubmission(TOKEN_2)).toMatchObject({ commentCount: 2 });
  });

  it('deletes only for the author or the club owner', async () => {
    const bobComment = (await (await comment(TOKEN_2, 'Bob here')).json()) as {
      comment: { id: string };
    };
    const caraComment = (await (await comment(TOKEN_3, 'Cara here')).json()) as {
      comment: { id: string };
    };

    const notMine = await app.request(`/comments/${caraComment.comment.id}`, {
      method: 'DELETE',
      headers: auth(TOKEN_2),
    }, env);
    expect(notMine.status).toBe(403);

    const own = await app.request(`/comments/${caraComment.comment.id}`, {
      method: 'DELETE',
      headers: auth(TOKEN_3),
    }, env);
    expect(own.status).toBe(200);

    const owner = await app.request(`/comments/${bobComment.comment.id}`, {
      method: 'DELETE',
      headers: auth(TOKEN_1),
    }, env);
    expect(owner.status).toBe(200);

    const list = await app.request(`/submissions/${SUBMISSION}/comments`, {
      headers: auth(TOKEN_1),
    }, env);
    expect(await list.json()).toEqual({ comments: [] });
  });

  it('hides a blocked member’s comments (and their comment count) from the blocker', async () => {
    await comment(TOKEN_3, 'Blocked words');
    await app.request(`/users/${U3}/block`, { method: 'POST', headers: auth(TOKEN_1) }, env);

    const hidden = await app.request(`/submissions/${SUBMISSION}/comments`, {
      headers: auth(TOKEN_1),
    }, env);
    expect(await hidden.json()).toEqual({ comments: [] });
    expect(await getSubmission(TOKEN_1)).toMatchObject({ commentCount: 0 });

    // Blocks are one-way: Bob still sees Cara's comment.
    const visible = await app.request(`/submissions/${SUBMISSION}/comments`, {
      headers: auth(TOKEN_2),
    }, env);
    expect(((await visible.json()) as { comments: unknown[] }).comments).toHaveLength(1);
  });

  it('removes a reported comment at the threshold', async () => {
    const created = (await (await comment(TOKEN_2, 'Report me')).json()) as {
      comment: { id: string };
    };

    const report = await app.request(`/comments/${created.comment.id}/report`, {
      method: 'POST',
      headers: jsonAuth(TOKEN_1),
      body: JSON.stringify({ reason: 'harassment', note: 'mean' }),
    }, env);
    expect(report.status).toBe(200);

    // Hidden immediately for the reporter.
    const reporterView = await app.request(`/submissions/${SUBMISSION}/comments`, {
      headers: auth(TOKEN_1),
    }, env);
    expect(await reporterView.json()).toEqual({ comments: [] });

    const second = await app.request(`/comments/${created.comment.id}/report`, {
      method: 'POST',
      headers: jsonAuth(TOKEN_3),
      body: JSON.stringify({ reason: 'harassment' }),
    }, env);
    // Already hidden from the reporter, but still visible to Cara until removal.
    expect(second.status).not.toBe(404);

    const remaining = await env.DB.prepare('SELECT COUNT(*) AS count FROM comments WHERE id = ?')
      .bind(created.comment.id)
      .first<{ count: number }>();
    expect(remaining?.count).toBe(0);
  });
});

describe('banter push throttle', () => {
  it('allows at most one banter push per submission per 10 minutes', async () => {
    expect(await claimBanterPush(env.DB, SUBMISSION, NOW)).toBe(true);
    expect(await claimBanterPush(env.DB, SUBMISSION, NOW + 60)).toBe(false);
    expect(await claimBanterPush(env.DB, SUBMISSION, NOW + 10 * 60 + 1)).toBe(true);
  });
});
