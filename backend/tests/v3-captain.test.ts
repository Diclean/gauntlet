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
  insertSubmission,
  insertUser,
  insertWeek,
  jsonAuth,
  resetDb,
} from './fixtures';

/** 6.6 captain armband: selection, lock rule and ×2 ledger points. */

const C2 = 'dddddddd-dddd-4ddd-8ddd-ddddddddddd2';
const SUBMISSION = 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeee1';

async function seed(): Promise<void> {
  await resetDb(env.DB);
  await insertUser(env.DB, U1, 'Alice', '🦊');
  await insertUser(env.DB, U2, 'Bob', '🐻');
  await insertUser(env.DB, U3, 'Outsider', '👀');
  await insertSession(env.DB, U1, TOKEN_1);
  await insertSession(env.DB, U2, TOKEN_2);
  await insertSession(env.DB, U3, TOKEN_3);

  await insertGroup(env.DB, GROUP, U1, 'ABC234');
  await insertMember(env.DB, GROUP, U1);
  await insertMember(env.DB, GROUP, U2);
  await insertWeek(env.DB, GROUP, WEEK);
  await insertChallenge(env.DB, WEEK, CHALLENGE, 25);
  await insertChallenge(env.DB, WEEK, C2, 10);
}

beforeEach(seed);

function putCaptain(token: string, challengeId: string) {
  return app.request(
    `/groups/${GROUP}/week/captain`,
    {
      method: 'PUT',
      headers: jsonAuth(token),
      body: JSON.stringify({ challengeId }),
    },
    env,
  );
}

describe('captain armband', () => {
  it('stores the choice, exposes it on Week and flags the fixture', async () => {
    const put = await putCaptain(TOKEN_1, CHALLENGE);
    expect(put.status).toBe(200);
    expect(await put.json()).toMatchObject({
      week: { id: WEEK, myCaptainChallengeId: CHALLENGE },
    });

    const week = await app.request(`/groups/${GROUP}/week`, { headers: auth(TOKEN_1) }, env);
    const body = (await week.json()) as {
      week: { myCaptainChallengeId: string | null };
      challenges: Array<{ id: string; isCaptain: boolean }>;
    };
    expect(body.week.myCaptainChallengeId).toBe(CHALLENGE);
    expect(body.challenges.find((challenge) => challenge.id === CHALLENGE)?.isCaptain).toBe(true);
    expect(body.challenges.find((challenge) => challenge.id === C2)?.isCaptain).toBe(false);

    // Other members are unaffected.
    const other = await app.request(`/groups/${GROUP}/week`, { headers: auth(TOKEN_2) }, env);
    expect(
      ((await other.json()) as { week: { myCaptainChallengeId: string | null } }).week
        .myCaptainChallengeId,
    ).toBeNull();
  });

  it('locks changes once I have a submission on my captain fixture', async () => {
    await putCaptain(TOKEN_1, CHALLENGE);
    await insertSubmission(env.DB, {
      id: SUBMISSION,
      challengeId: CHALLENGE,
      userId: U1,
      status: 'pending',
      eligibleVoters: 1,
    });

    const change = await putCaptain(TOKEN_1, C2);
    expect(change.status).toBe(409);
    expect(await change.json()).toMatchObject({ error: { code: 'captain_locked' } });

    // Re-selecting the same fixture is a no-op, not a lock error.
    const same = await putCaptain(TOKEN_1, CHALLENGE);
    expect(same.status).toBe(200);
  });

  it('rejects fixtures from another week and non-members', async () => {
    const outside = await putCaptain(TOKEN_1, 'dddddddd-dddd-4ddd-8ddd-ddddddddddd9');
    expect(outside.status).toBe(404);

    const outsider = await putCaptain(TOKEN_3, CHALLENGE);
    expect(outsider.status).toBe(403);
  });

  it('awards the fixture base points again on acceptance and adds a CAPTAIN ×2 receipt line', async () => {
    await putCaptain(TOKEN_1, CHALLENGE);
    await insertSubmission(env.DB, {
      id: SUBMISSION,
      challengeId: CHALLENGE,
      userId: U1,
      status: 'pending',
      eligibleVoters: 1,
    });

    const vote = await app.request(
      `/submissions/${SUBMISSION}/vote`,
      { method: 'POST', headers: jsonAuth(TOKEN_2), body: JSON.stringify({ approve: true }) },
      env,
    );
    expect(vote.status).toBe(200);

    const events = await env.DB.prepare(
      'SELECT kind, points FROM point_events WHERE submission_id = ? ORDER BY kind ASC',
    )
      .bind(SUBMISSION)
      .all<{ kind: string; points: number }>();
    expect(events.results).toEqual([
      { kind: 'captain', points: 25 },
      { kind: 'challenge', points: 25 },
      { kind: 'first_bonus', points: 10 },
    ]);

    const receipt = await app.request(
      `/groups/${GROUP}/weeks/${WEEK}/receipt`,
      { headers: auth(TOKEN_1) },
      env,
    );
    expect(receipt.status).toBe(200);
    const body = (await receipt.json()) as {
      lines: Array<{ label: string; points: number; struck: boolean }>;
    };
    expect(body.lines).toContainEqual({ label: 'CAPTAIN ×2', points: 25, struck: false });
    expect(body.lines).toContainEqual({ label: 'First to finish', points: 10, struck: false });
  });
});
