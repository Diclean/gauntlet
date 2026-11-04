import { beforeEach, describe, expect, it } from 'vitest';
import { env } from 'cloudflare:test';
import { app } from '../src';
import {
  CHALLENGE,
  GROUP,
  GROUP2,
  NOW,
  SUBMISSION,
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
  insertSession,
  insertSubmission,
  insertUser,
  insertWeek,
  resetDb,
} from './fixtures';

const WEEK_CLOSED = 'cccccccc-cccc-4ccc-8ccc-ccccccccccc1';
const CHALLENGE_CLOSED = 'dddddddd-dddd-4ddd-8ddd-ddddddddddd1';
const CHALLENGE_VOTED = 'dddddddd-dddd-4ddd-8ddd-ddddddddddd4';
const WEEK_PAST = 'cccccccc-cccc-4ccc-8ccc-ccccccccccc2';
const CHALLENGE_PAST = 'dddddddd-dddd-4ddd-8ddd-ddddddddddd2';

const WEEK_OTHER_GROUP = 'cccccccc-cccc-4ccc-8ccc-ccccccccccc3';
const CHALLENGE_OTHER_GROUP = 'dddddddd-dddd-4ddd-8ddd-ddddddddddd3';

const SUBMISSION_VOTED = 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeee1';
const SUBMISSION_DECIDED = 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeee2';
const SUBMISSION_REJECTED = 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeee3';
const SUBMISSION_EXPIRED = 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeee4';
const SUBMISSION_PAST = 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeee5';
const SUBMISSION_CLOSED_WEEK = 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeee6';
const SUBMISSION_OLDEST = 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeee7';
const SUBMISSION_OTHER_GROUP = 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeee8';

interface PendingBody {
  items: Array<{
    id: string;
    challengeId: string;
    status: string;
    myVote: boolean | null;
    createdAt: number;
  }>;
}

async function pending(token: string): Promise<PendingBody> {
  const response = await app.request(`/groups/${GROUP}/votes/pending`, { headers: auth(token) }, env);
  expect(response.status).toBe(200);
  return (await response.json()) as PendingBody;
}

async function seed(): Promise<void> {
  await resetDb(env.DB);

  await insertUser(env.DB, U1, 'Alice', '🦊');
  await insertUser(env.DB, U2, 'Bob', '🐻');
  await insertUser(env.DB, U3, 'Mallory', '🐍');
  await insertSession(env.DB, U1, TOKEN_1);
  await insertSession(env.DB, U2, TOKEN_2);
  await insertSession(env.DB, U3, TOKEN_3);

  await insertGroup(env.DB, GROUP, U1, 'ABC234');
  await insertMember(env.DB, GROUP, U1);
  await insertMember(env.DB, GROUP, U2);

  // Another group: its proofs must never leak into GROUP's pending list.
  await insertGroup(env.DB, GROUP2, U2, 'XYZ789', 'Other group');
  await insertMember(env.DB, GROUP2, U2);
  await insertWeek(env.DB, GROUP2, WEEK_OTHER_GROUP);
  await insertChallenge(env.DB, WEEK_OTHER_GROUP, CHALLENGE_OTHER_GROUP);
  await insertSubmission(env.DB, {
    id: SUBMISSION_OTHER_GROUP,
    challengeId: CHALLENGE_OTHER_GROUP,
    userId: U2,
    createdAt: NOW - 1_900,
  });

  // Current week: deadline still in the future.
  await insertWeek(env.DB, GROUP, WEEK);
  await insertChallenge(env.DB, WEEK, CHALLENGE);
  // The partial unique index allows one pending proof per (challenge, user),
  // so the already-voted proof gets its own challenge in the same week.
  await insertChallenge(env.DB, WEEK, CHALLENGE_VOTED, 15);

  // Closed week still inside its 12h grace period: votes are still accepted.
  await insertWeek(env.DB, GROUP, WEEK_CLOSED, 'closed', {
    startsAt: WEEK_START - 2 * 7 * 86_400,
    voteDeadline: NOW + 3_600,
  });
  await insertChallenge(env.DB, WEEK_CLOSED, CHALLENGE_CLOSED);

  // A week whose vote deadline has passed: its pending proofs are no longer votable.
  await insertWeek(env.DB, GROUP, WEEK_PAST, 'open', {
    startsAt: WEEK_START - 3 * 7 * 86_400,
    voteDeadline: NOW - 3_600,
  });
  await insertChallenge(env.DB, WEEK_PAST, CHALLENGE_PAST);

  // Authored by Alice: never in Alice's own pending list.
  await insertSubmission(env.DB, { id: SUBMISSION, userId: U1, createdAt: NOW - 1_000 });

  await insertSubmission(env.DB, {
    id: SUBMISSION_VOTED,
    challengeId: CHALLENGE_VOTED,
    userId: U2,
    createdAt: NOW - 1_500,
  });
  await env.DB.prepare(
    'INSERT INTO votes (submission_id, voter_id, approve, created_at) VALUES (?, ?, 1, ?)',
  )
    .bind(SUBMISSION_VOTED, U1, NOW - 500)
    .run();

  await insertSubmission(env.DB, {
    id: SUBMISSION_DECIDED,
    userId: U2,
    status: 'accepted',
    createdAt: NOW - 1_200,
  });
  await insertSubmission(env.DB, {
    id: SUBMISSION_REJECTED,
    userId: U2,
    status: 'rejected',
    createdAt: NOW - 1_300,
  });
  await insertSubmission(env.DB, {
    id: SUBMISSION_EXPIRED,
    userId: U2,
    status: 'expired',
    createdAt: NOW - 1_400,
  });
  await insertSubmission(env.DB, {
    id: SUBMISSION_PAST,
    challengeId: CHALLENGE_PAST,
    userId: U2,
    createdAt: NOW - 1_600,
  });
  await insertSubmission(env.DB, {
    id: SUBMISSION_CLOSED_WEEK,
    challengeId: CHALLENGE_CLOSED,
    userId: U2,
    createdAt: NOW - 2_500,
  });
  await insertSubmission(env.DB, {
    id: SUBMISSION_OLDEST,
    userId: U2,
    createdAt: NOW - 2_000,
  });
}

beforeEach(seed);

describe('GET /groups/:id/votes/pending', () => {
  it('returns only others pending proofs I have not voted on, oldest first', async () => {
    const body = await pending(TOKEN_1);

    expect(body.items.map((item) => item.id)).toEqual([
      SUBMISSION_CLOSED_WEEK,
      SUBMISSION_OLDEST,
    ]);
    expect(body.items.map((item) => item.createdAt)).toEqual([NOW - 2_500, NOW - 2_000]);
    expect(body.items.every((item) => item.status === 'pending')).toBe(true);
    expect(body.items.every((item) => item.myVote === null)).toBe(true);
  });

  it('excludes submissions I authored', async () => {
    const body = await pending(TOKEN_1);
    expect(body.items.map((item) => item.id)).not.toContain(SUBMISSION);
  });

  it('excludes submissions I already voted on, even if still pending', async () => {
    const body = await pending(TOKEN_1);
    expect(body.items.map((item) => item.id)).not.toContain(SUBMISSION_VOTED);

    const stored = await env.DB.prepare('SELECT status FROM submissions WHERE id = ?')
      .bind(SUBMISSION_VOTED)
      .first<{ status: string }>();
    expect(stored?.status).toBe('pending');
  });

  it('excludes decided, expired and past-deadline submissions', async () => {
    const ids = (await pending(TOKEN_1)).items.map((item) => item.id);
    expect(ids).not.toContain(SUBMISSION_DECIDED);
    expect(ids).not.toContain(SUBMISSION_REJECTED);
    expect(ids).not.toContain(SUBMISSION_EXPIRED);
    expect(ids).not.toContain(SUBMISSION_PAST);
  });

  it('includes a closed week that is still inside its vote grace period', async () => {
    const ids = (await pending(TOKEN_1)).items.map((item) => item.id);
    expect(ids).toContain(SUBMISSION_CLOSED_WEEK);
    expect(ids).not.toContain(SUBMISSION_PAST);
  });

  it('never mixes in submissions from another group', async () => {
    const ids = (await pending(TOKEN_1)).items.map((item) => item.id);
    expect(ids).not.toContain(SUBMISSION_OTHER_GROUP);
  });

  it('serializes each item exactly like the feed serializer', async () => {
    const pendingBody = await pending(TOKEN_1);
    const feed = await app.request(`/groups/${GROUP}/feed`, { headers: auth(TOKEN_1) }, env);
    expect(feed.status).toBe(200);
    const feedBody = (await feed.json()) as { items: Array<{ id: string }> };

    for (const item of pendingBody.items) {
      expect(item).toEqual(feedBody.items.find((entry) => entry.id === item.id));
    }
    expect(pendingBody.items[1]).toMatchObject({
      id: SUBMISSION_OLDEST,
      challengeId: CHALLENGE,
      status: 'pending',
      myVote: null,
    });
  });

  it('returns an empty list once everything has been voted on', async () => {
    for (const id of [SUBMISSION_CLOSED_WEEK, SUBMISSION_OLDEST]) {
      const response = await app.request(
        `/submissions/${id}/vote`,
        {
          method: 'POST',
          headers: { ...auth(TOKEN_1), 'Content-Type': 'application/json' },
          body: JSON.stringify({ approve: true }),
        },
        env,
      );
      expect(response.status).toBe(200);
    }

    expect((await pending(TOKEN_1)).items).toEqual([]);
  });

  it('requires membership (403) and authentication (401)', async () => {
    const outsider = await app.request(
      `/groups/${GROUP}/votes/pending`,
      { headers: auth(TOKEN_3) },
      env,
    );
    expect(outsider.status).toBe(403);
    expect(await outsider.json()).toMatchObject({ error: { code: 'forbidden' } });

    const anonymous = await app.request(`/groups/${GROUP}/votes/pending`, {}, env);
    expect(anonymous.status).toBe(401);
  });
});
