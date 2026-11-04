import { beforeEach, describe, expect, it } from 'vitest';
import { env } from 'cloudflare:test';
import { app } from '../src';
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

/** Submission.voters: hidden before I vote, visible after I vote and when decided. */

const U4 = '44444444-4444-4444-8444-444444444444';
const TOKEN_4 = 'token-for-user-4-0123456789abcdef';

const C_HIDDEN = 'dddddddd-dddd-4ddd-8ddd-ddddddddddd1';
const C_AFTER = 'dddddddd-dddd-4ddd-8ddd-ddddddddddd2';
const C_ACCEPTED = 'dddddddd-dddd-4ddd-8ddd-ddddddddddd3';
const C_REJECTED = 'dddddddd-dddd-4ddd-8ddd-ddddddddddd4';
const C_VOTE = 'dddddddd-dddd-4ddd-8ddd-ddddddddddd5';

const S_HIDDEN = 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeee1';
const S_AFTER = 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeee2';
const S_ACCEPTED = 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeee3';
const S_REJECTED = 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeee4';
const S_VOTE = 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeee5';

interface VoterJson {
  id: string;
  displayName: string;
  avatarEmoji: string | null;
}

interface SubmissionJson {
  id: string;
  status: string;
  myVote: boolean | null;
  voters: VoterJson[];
}

async function insertVote(
  submissionId: string,
  voterId: string,
  approve: boolean,
  createdAt: number,
): Promise<void> {
  await env.DB.prepare(
    'INSERT INTO votes (submission_id, voter_id, approve, created_at) VALUES (?, ?, ?, ?)',
  )
    .bind(submissionId, voterId, approve ? 1 : 0, createdAt)
    .run();
}

async function feed(token: string): Promise<SubmissionJson[]> {
  const response = await app.request(`/groups/${GROUP}/feed`, { headers: auth(token) }, env);
  expect(response.status).toBe(200);
  return ((await response.json()) as { items: SubmissionJson[] }).items;
}

async function getSubmission(id: string, token: string): Promise<SubmissionJson> {
  const response = await app.request(`/submissions/${id}`, { headers: auth(token) }, env);
  expect(response.status).toBe(200);
  return ((await response.json()) as { submission: SubmissionJson }).submission;
}

async function seed(): Promise<void> {
  await resetDb(env.DB);

  await insertUser(env.DB, U1, 'Alice', '🦊');
  await insertUser(env.DB, U2, 'Bob', '🐻');
  await insertUser(env.DB, U3, 'Lee', '🐧');
  await insertUser(env.DB, U4, 'Outsider', '👀');
  await insertSession(env.DB, U1, TOKEN_1);
  await insertSession(env.DB, U2, TOKEN_2);
  await insertSession(env.DB, U3, TOKEN_3);
  await insertSession(env.DB, U4, TOKEN_4);

  await insertGroup(env.DB, GROUP, U1, 'ABC234');
  await insertMember(env.DB, GROUP, U1);
  await insertMember(env.DB, GROUP, U2);
  await insertMember(env.DB, GROUP, U3);
  // U4 is deliberately not a member of GROUP.
  await insertGroup(env.DB, 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', U4, 'XYZ789', 'Other group');
  await insertMember(env.DB, 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', U4);

  await insertWeek(env.DB, GROUP, WEEK);
  await insertChallenge(env.DB, WEEK, C_HIDDEN);
  await insertChallenge(env.DB, WEEK, C_AFTER);
  await insertChallenge(env.DB, WEEK, C_ACCEPTED);
  await insertChallenge(env.DB, WEEK, C_REJECTED);
  await insertChallenge(env.DB, WEEK, C_VOTE);

  // Pending proof by Alice, already called by Bob. Lee has not voted yet.
  await insertSubmission(env.DB, {
    id: S_HIDDEN,
    challengeId: C_HIDDEN,
    userId: U1,
    eligibleVoters: 2,
    createdAt: NOW - 1_000,
  });
  await insertVote(S_HIDDEN, U2, true, NOW - 500);

  // Pending proof by Bob, already called by Lee (two voters needed).
  await insertSubmission(env.DB, {
    id: S_AFTER,
    challengeId: C_AFTER,
    userId: U2,
    eligibleVoters: 2,
    createdAt: NOW - 900,
  });
  await insertVote(S_AFTER, U3, true, NOW - 400);

  // Decided proofs, called by Lee. Bob did not vote on either.
  await insertSubmission(env.DB, {
    id: S_ACCEPTED,
    challengeId: C_ACCEPTED,
    userId: U1,
    status: 'accepted',
    eligibleVoters: 2,
    createdAt: NOW - 800,
  });
  await insertVote(S_ACCEPTED, U3, true, NOW - 300);

  await insertSubmission(env.DB, {
    id: S_REJECTED,
    challengeId: C_REJECTED,
    userId: U1,
    status: 'rejected',
    eligibleVoters: 2,
    createdAt: NOW - 700,
  });
  await insertVote(S_REJECTED, U3, false, NOW - 200);

  // Fresh vote target: Alice votes, one approval of two keeps it pending.
  await insertSubmission(env.DB, {
    id: S_VOTE,
    challengeId: C_VOTE,
    userId: U2,
    eligibleVoters: 2,
    createdAt: NOW - 600,
  });
}

beforeEach(seed);

describe('Submission.voters', () => {
  it('is empty while pending and the viewer has not voted', async () => {
    const item = (await feed(TOKEN_3)).find((entry) => entry.id === S_HIDDEN)!;
    expect(item).toMatchObject({ status: 'pending', myVote: null, voters: [] });

    expect((await getSubmission(S_HIDDEN, TOKEN_3)).voters).toEqual([]);
  });

  it('never leaks a pending tally into the pending-votes list', async () => {
    const response = await app.request(
      `/groups/${GROUP}/votes/pending`,
      { headers: auth(TOKEN_3) },
      env,
    );
    expect(response.status).toBe(200);
    const body = (await response.json()) as { items: SubmissionJson[] };

    expect(body.items.map((item) => item.id)).toEqual([S_HIDDEN, S_VOTE]);
    expect(body.items.every((item) => item.voters.length === 0)).toBe(true);
  });

  it('is visible to a viewer who already voted, even while still pending', async () => {
    const item = (await feed(TOKEN_2)).find((entry) => entry.id === S_HIDDEN)!;
    expect(item).toMatchObject({ status: 'pending', myVote: true });
    expect(item.voters).toEqual([{ id: U2, displayName: 'Bob', avatarEmoji: '🐻' }]);
  });

  it('is visible on a decided proof even when the viewer did not vote', async () => {
    const items = await feed(TOKEN_2);
    for (const id of [S_ACCEPTED, S_REJECTED]) {
      const item = items.find((entry) => entry.id === id)!;
      expect(item.myVote).toBeNull();
      expect(item.voters.map((voter) => voter.id)).toEqual([U3]);
    }
  });

  it('returns voters on the vote response and matches GET and feed exactly', async () => {
    const response = await app.request(
      `/submissions/${S_VOTE}/vote`,
      {
        method: 'POST',
        headers: jsonAuth(TOKEN_1),
        body: JSON.stringify({ approve: true }),
      },
      env,
    );
    expect(response.status).toBe(200);
    const { submission } = (await response.json()) as { submission: SubmissionJson };

    expect(submission).toMatchObject({ id: S_VOTE, status: 'pending', myVote: true });
    expect(submission.voters.map((voter) => voter.id)).toEqual([U1]);
    expect(await getSubmission(S_VOTE, TOKEN_1)).toEqual(submission);
    expect((await feed(TOKEN_1)).find((entry) => entry.id === S_VOTE)).toEqual(submission);
  });

  it('never leaks voters to non-members', async () => {
    for (const path of [
      `/submissions/${S_ACCEPTED}`,
      `/groups/${GROUP}/feed`,
      `/groups/${GROUP}/votes/pending`,
    ]) {
      const response = await app.request(path, { headers: auth(TOKEN_4) }, env);
      expect(response.status, path).toBe(403);
      const body = (await response.json()) as Record<string, unknown>;
      expect(body).toMatchObject({ error: { code: 'forbidden' } });
      expect(body).not.toHaveProperty('voters');
    }

    const vote = await app.request(
      `/submissions/${S_VOTE}/vote`,
      {
        method: 'POST',
        headers: jsonAuth(TOKEN_4),
        body: JSON.stringify({ approve: true }),
      },
      env,
    );
    expect(vote.status).toBe(403);
    expect(await vote.json()).toMatchObject({ error: { code: 'forbidden' } });
  });
});
