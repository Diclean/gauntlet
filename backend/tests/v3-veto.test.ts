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
  insertPointEvent,
  insertSession,
  insertSubmission,
  insertUser,
  insertWeek,
  jsonAuth,
  resetDb,
} from './fixtures';

/** 6.3 fixture veto + in-place replacement (max two per club per week). */

const U4 = '44444444-4444-4444-8444-444444444444';
const TOKEN_4 = 'token-for-user-4-0123456789abcdef';

const C2 = 'dddddddd-dddd-4ddd-8ddd-ddddddddddd2';
const C3 = 'dddddddd-dddd-4ddd-8ddd-ddddddddddd3';
const HOUSE = 'dddddddd-dddd-4ddd-8ddd-ddddddddddd4';
const SUBMISSION = 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeee1';

async function seed(): Promise<void> {
  await resetDb(env.DB);
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
  await insertWeek(env.DB, GROUP, WEEK);
  // C1 is the hard fixture we veto.
  await env.DB.prepare(
    `INSERT INTO challenges
       (id, week_id, title, description, difficulty, points, position,
        vetoed_at, replaced_by, is_house, created_by, created_at)
     VALUES (?, ?, 'Test challenge', 'Do the test thing.', 'hard', 50, 0, NULL, NULL, 0, NULL, 0)`,
  )
    .bind(CHALLENGE, WEEK)
    .run();
  await insertChallenge(env.DB, WEEK, C2, 10);
  await insertChallenge(env.DB, WEEK, C3, 10);

  await insertSubmission(env.DB, {
    id: SUBMISSION,
    userId: U1,
    status: 'accepted',
    eligibleVoters: 2,
  });
  await insertPointEvent(env.DB, {
    weekId: WEEK,
    userId: U1,
    kind: 'challenge',
    points: 50,
    submissionId: SUBMISSION,
  });
  await insertPointEvent(env.DB, {
    weekId: WEEK,
    userId: U1,
    kind: 'first_bonus',
    points: 10,
    submissionId: SUBMISSION,
  });
}

beforeEach(seed);

function veto(token: string, challengeId: string) {
  return app.request(`/challenges/${challengeId}/veto`, {
    method: 'POST',
    headers: auth(token),
  }, env);
}

interface VetoBody {
  challenge: {
    id: string;
    title: string;
    difficulty: string;
    position: number;
    vetoCount: number;
    vetoThreshold: number;
    myVeto: boolean;
    isNew: boolean;
    isHouse: boolean;
    createdBy: { id: string } | null;
  };
  replaced: boolean;
}

async function replaceFirstFixture(): Promise<VetoBody> {
  const one = await veto(TOKEN_2, CHALLENGE);
  expect(one.status).toBe(200);
  const oneBody = (await one.json()) as VetoBody;
  expect(oneBody.replaced).toBe(false);
  expect(oneBody.challenge.vetoCount).toBe(1);
  expect(oneBody.challenge.vetoThreshold).toBe(2);

  const two = await veto(TOKEN_3, CHALLENGE);
  expect(two.status).toBe(200);
  return (await two.json()) as VetoBody;
}

describe('fixture veto', () => {
  it('replaces the fixture in place at the threshold and expires its proofs', async () => {
    const body = await replaceFirstFixture();
    expect(body.replaced).toBe(true);
    expect(body.challenge.id).not.toBe(CHALLENGE);
    expect(body.challenge.difficulty).toBe('hard');
    expect(body.challenge.position).toBe(0);
    expect(body.challenge.isNew).toBe(true);
    expect(body.challenge.isHouse).toBe(false);
    expect(body.challenge.createdBy).toBeNull();

    const old = await env.DB.prepare('SELECT vetoed_at, replaced_by FROM challenges WHERE id = ?')
      .bind(CHALLENGE)
      .first<{ vetoed_at: number | null; replaced_by: string | null }>();
    expect(old?.vetoed_at).toBeGreaterThan(0);
    expect(old?.replaced_by).toBe(body.challenge.id);

    const submission = await env.DB.prepare('SELECT status FROM submissions WHERE id = ?')
      .bind(SUBMISSION)
      .first<{ status: string }>();
    expect(submission?.status).toBe('expired');

    const events = await env.DB.prepare(
      'SELECT COUNT(*) AS count FROM point_events WHERE submission_id = ?',
    )
      .bind(SUBMISSION)
      .first<{ count: number }>();
    expect(events?.count).toBe(0);

    const week = await app.request(`/groups/${GROUP}/week`, { headers: auth(TOKEN_2) }, env);
    expect(week.status).toBe(200);
    const weekBody = (await week.json()) as {
      challenges: Array<{ id: string; isNew: boolean }>;
    };
    expect(weekBody.challenges.map((challenge) => challenge.id)).not.toContain(CHALLENGE);
    expect(weekBody.challenges.map((challenge) => challenge.id)).toContain(body.challenge.id);
    expect(weekBody.challenges).toHaveLength(3);
  });

  it('toggles my veto off without replacing anything', async () => {
    const on = await veto(TOKEN_2, CHALLENGE);
    expect(on.status).toBe(200);
    expect(((await on.json()) as VetoBody).challenge.myVeto).toBe(true);

    const off = await veto(TOKEN_2, CHALLENGE);
    expect(off.status).toBe(200);
    const offBody = (await off.json()) as VetoBody;
    expect(offBody.replaced).toBe(false);
    expect(offBody.challenge.myVeto).toBe(false);
    expect(offBody.challenge.vetoCount).toBe(0);

    const row = await env.DB.prepare('SELECT vetoed_at FROM challenges WHERE id = ?')
      .bind(CHALLENGE)
      .first<{ vetoed_at: number | null }>();
    expect(row?.vetoed_at).toBeNull();
  });

  it('allows two replacements per club per week and then returns 409 veto_limit', async () => {
    const first = await replaceFirstFixture();
    const firstId = first.challenge.id;

    const second = await veto(TOKEN_2, firstId);
    expect(second.status).toBe(200);
    const secondBody = (await second.json()) as VetoBody;
    expect(secondBody.replaced).toBe(false);
    const secondDone = await veto(TOKEN_3, firstId);
    expect(secondDone.status).toBe(200);
    const secondReplacement = (await secondDone.json()) as VetoBody;
    expect(secondReplacement.replaced).toBe(true);

    const thirdOne = await veto(TOKEN_2, C2);
    expect(thirdOne.status).toBe(200);
    expect(((await thirdOne.json()) as VetoBody).replaced).toBe(false);

    const thirdTwo = await veto(TOKEN_3, C2);
    expect(thirdTwo.status).toBe(409);
    expect(await thirdTwo.json()).toMatchObject({ error: { code: 'veto_limit' } });
  });

  it('withdraws a vetoed house fixture without replacing it', async () => {
    await env.DB.prepare(
      `INSERT INTO challenges
         (id, week_id, title, description, difficulty, points, position,
          vetoed_at, replaced_by, is_house, created_by, created_at)
       VALUES (?, ?, 'House fixture', 'Made by the club.', 'easy', 10, 3, NULL, NULL, 1, ?, ?)`,
    )
      .bind(HOUSE, WEEK, U1, Math.floor(Date.now() / 1000))
      .run();

    const one = await veto(TOKEN_2, HOUSE);
    expect(one.status).toBe(200);
    expect(((await one.json()) as VetoBody).replaced).toBe(false);
    const two = await veto(TOKEN_3, HOUSE);
    expect(two.status).toBe(200);
    const body = (await two.json()) as VetoBody;
    expect(body.replaced).toBe(false);
    expect(body.challenge.isHouse).toBe(true);

    const row = await env.DB.prepare('SELECT vetoed_at, replaced_by FROM challenges WHERE id = ?')
      .bind(HOUSE)
      .first<{ vetoed_at: number | null; replaced_by: string | null }>();
    expect(row?.vetoed_at).toBeGreaterThan(0);
    expect(row?.replaced_by).toBeNull();

    const week = await app.request(`/groups/${GROUP}/week`, { headers: auth(TOKEN_1) }, env);
    const weekBody = (await week.json()) as { challenges: Array<{ id: string }> };
    expect(weekBody.challenges.map((challenge) => challenge.id)).not.toContain(HOUSE);
  });

  it('rejects non-members and vetoes on decided/old weeks', async () => {
    const unauthenticated = await app.request(
      `/challenges/${CHALLENGE}/veto`,
      { method: 'POST', headers: auth('not-a-token') },
      env,
    );
    expect(unauthenticated.status).toBe(401);

    const outsider = await veto(TOKEN_4, CHALLENGE);
    expect(outsider.status).toBe(403);

    await env.DB.prepare("UPDATE weeks SET status = 'closed' WHERE id = ?").bind(WEEK).run();
    const closed = await veto(TOKEN_2, CHALLENGE);
    expect(closed.status).toBe(409);
    expect(await closed.json()).toMatchObject({ error: { code: 'week_closed' } });
  });
});
