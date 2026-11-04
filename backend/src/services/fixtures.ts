import type { ChallengeRow, Env, GroupRow, PublicUser, WeekRow } from '../types';
import { toPublicUser } from '../types';
import { all, first } from '../lib/db';
import { randomId } from '../lib/crypto';
import { conflict, forbidden, notFound } from '../lib/errors';
import { houseFixtureDeadline } from '../business/time';
import { pointsForDifficulty, type Difficulty } from '../business/points';
import { generateReplacementChallenge } from '../deepseek';
import { previousChallengeTitles } from './weeks';
import { countWeekReplacements } from './groups';
import { deleteMediaKeys } from './media';
import type { HouseFixtureJson } from '../types';

/**
 * v3 fixture mechanics: veto + in-place replacement, captain armband and the
 * weekly house fixture. Everything here writes with bound parameters only.
 */

const MAX_REPLACEMENTS_PER_WEEK = 2;

export async function getChallengeRow(
  db: D1Database,
  challengeId: string,
): Promise<ChallengeRow | null> {
  return await first<ChallengeRow>(
    db.prepare('SELECT * FROM challenges WHERE id = ?').bind(challengeId),
  );
}

export async function getWeekRow(
  db: D1Database,
  weekId: string,
): Promise<WeekRow | null> {
  return await first<WeekRow>(db.prepare('SELECT * FROM weeks WHERE id = ?').bind(weekId));
}

async function currentWeekTitles(db: D1Database, weekId: string): Promise<string[]> {
  const rows = await all<{ title: string }>(
    db.prepare('SELECT title FROM challenges WHERE week_id = ? ORDER BY position ASC').bind(weekId),
  );
  return rows.map((row) => row.title);
}

/** Media keys the veto-expiry UPDATE is about to orphan. */
async function expiringMediaKeys(db: D1Database, challengeId: string): Promise<string[]> {
  const rows = await all<{ media_key: string }>(
    db
      .prepare(
        `SELECT media_key FROM submissions
          WHERE challenge_id = ? AND status NOT IN ('expired', 'removed')`,
      )
      .bind(challengeId),
  );
  return rows.map((row) => row.media_key);
}

export interface VetoResult {
  replaced: boolean;
  /** The fixture the caller should see next (new one after a replacement). */
  challengeId: string;
}

/**
 * Toggles the caller's veto on a fixture. At `ceil(memberCount / 2)` vetoes the
 * fixture is replaced in place (same difficulty/position) unless it is the house
 * fixture, which is simply withdrawn. Two replacements per club per week max.
 */
export async function toggleVeto(
  env: Env,
  params: {
    challenge: ChallengeRow;
    week: WeekRow;
    group: GroupRow;
    userId: string;
    memberCount: number;
    now: number;
  },
): Promise<VetoResult> {
  const { challenge, week, group, userId, now } = params;

  const existing = await first<{ one: number }>(
    env.DB.prepare('SELECT 1 AS one FROM vetoes WHERE challenge_id = ? AND user_id = ?')
      .bind(challenge.id, userId),
  );
  if (existing) {
    await env.DB.prepare('DELETE FROM vetoes WHERE challenge_id = ? AND user_id = ?')
      .bind(challenge.id, userId)
      .run();
    return { replaced: false, challengeId: challenge.id };
  }

  const countRow = await first<{ count: number }>(
    env.DB.prepare('SELECT COUNT(*) AS count FROM vetoes WHERE challenge_id = ?').bind(challenge.id),
  );
  const nextVetoCount = (countRow?.count ?? 0) + 1;
  const threshold = Math.ceil(Math.max(1, params.memberCount) / 2);

  if (nextVetoCount >= threshold) {
    if (challenge.is_house === 1) {
      // A vetoed house fixture is withdrawn, never replaced.
      const expiringMedia = await expiringMediaKeys(env.DB, challenge.id);
      await env.DB.batch([
        env.DB.prepare('UPDATE challenges SET vetoed_at = ? WHERE id = ?').bind(now, challenge.id),
        env.DB.prepare(
          "UPDATE submissions SET status = 'expired' WHERE challenge_id = ? AND status NOT IN ('expired', 'removed')",
        ).bind(challenge.id),
        env.DB.prepare(
          `DELETE FROM point_events
            WHERE submission_id IN (SELECT id FROM submissions WHERE challenge_id = ?)`,
        ).bind(challenge.id),
        env.DB.prepare('DELETE FROM captains WHERE challenge_id = ?').bind(challenge.id),
        env.DB.prepare('INSERT INTO vetoes (challenge_id, user_id, created_at) VALUES (?, ?, ?)')
          .bind(challenge.id, userId, now),
      ]);
      await deleteMediaKeys(env, expiringMedia);
      return { replaced: false, challengeId: challenge.id };
    }

    const replacements = await countWeekReplacements(env.DB, week.id);
    if (replacements >= MAX_REPLACEMENTS_PER_WEEK) {
      throw conflict('veto_limit', 'This club has already replaced two fixtures this week');
    }

    const previousTitles = [
      ...(await currentWeekTitles(env.DB, week.id)),
      ...(await previousChallengeTitles(env.DB, group.id, week.starts_at)),
    ];
    const draft = await generateReplacementChallenge({
      env,
      difficulty: challenge.difficulty,
      language: group.language,
      timezone: group.timezone,
      theme: group.theme,
      previousTitles,
    });

    const replacement: ChallengeRow = {
      id: randomId(),
      week_id: week.id,
      title: draft.title,
      description: draft.description,
      difficulty: challenge.difficulty,
      points: pointsForDifficulty(challenge.difficulty),
      position: challenge.position,
      vetoed_at: null,
      replaced_by: null,
      is_house: 0,
      created_by: null,
      created_at: now,
    };

    const expiringMedia = await expiringMediaKeys(env.DB, challenge.id);
    await env.DB.batch([
      env.DB.prepare('INSERT INTO vetoes (challenge_id, user_id, created_at) VALUES (?, ?, ?)')
        .bind(challenge.id, userId, now),
      env.DB.prepare('UPDATE challenges SET vetoed_at = ?, replaced_by = ? WHERE id = ?').bind(
        now,
        replacement.id,
        challenge.id,
      ),
      env.DB.prepare(
        `INSERT INTO challenges
           (id, week_id, title, description, difficulty, points, position,
            vetoed_at, replaced_by, is_house, created_by, created_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, NULL, NULL, 0, NULL, ?)`,
      ).bind(
        replacement.id,
        replacement.week_id,
        replacement.title,
        replacement.description,
        replacement.difficulty,
        replacement.points,
        replacement.position,
        replacement.created_at,
      ),
      env.DB.prepare(
        "UPDATE submissions SET status = 'expired' WHERE challenge_id = ? AND status NOT IN ('expired', 'removed')",
      ).bind(challenge.id),
      env.DB.prepare(
        `DELETE FROM point_events
          WHERE submission_id IN (SELECT id FROM submissions WHERE challenge_id = ?)`,
      ).bind(challenge.id),
      env.DB.prepare('DELETE FROM captains WHERE challenge_id = ?').bind(challenge.id),
    ]);

    await deleteMediaKeys(env, expiringMedia);
    return { replaced: true, challengeId: replacement.id };
  }

  await env.DB.prepare('INSERT INTO vetoes (challenge_id, user_id, created_at) VALUES (?, ?, ?)')
    .bind(challenge.id, userId, now)
    .run();
  return { replaced: false, challengeId: challenge.id };
}

/** `PUT /groups/:id/week/captain`. Locked once the member submitted on it. */
export async function chooseCaptain(
  db: D1Database,
  params: {
    week: WeekRow;
    userId: string;
    challengeId: string;
    now: number;
  },
): Promise<void> {
  const { week, userId, challengeId, now } = params;
  if (week.status !== 'open' || now < week.starts_at || now > week.ends_at) {
    throw conflict('week_closed', 'The captain armband can only change this week');
  }

  const challenge = await first<ChallengeRow>(
    db
      .prepare(
        'SELECT * FROM challenges WHERE id = ? AND week_id = ? AND vetoed_at IS NULL',
      )
      .bind(challengeId, week.id),
  );
  if (!challenge) throw notFound('Challenge not found');

  const existing = await first<{ challenge_id: string }>(
    db.prepare('SELECT challenge_id FROM captains WHERE week_id = ? AND user_id = ?')
      .bind(week.id, userId),
  );
  if (existing?.challenge_id === challengeId) return;
  if (existing) {
    const submitted = await first<{ one: number }>(
      db
        .prepare(
          `SELECT 1 AS one FROM submissions
            WHERE challenge_id = ? AND user_id = ? AND status NOT IN ('rejected', 'expired')
            LIMIT 1`,
        )
        .bind(existing.challenge_id, userId),
    );
    if (submitted) {
      throw conflict('captain_locked', 'You already submitted on your captain fixture');
    }
  }

  await db
    .prepare(
      `INSERT INTO captains (week_id, user_id, challenge_id) VALUES (?, ?, ?)
       ON CONFLICT(week_id, user_id) DO UPDATE SET challenge_id = excluded.challenge_id`,
    )
    .bind(week.id, userId, challengeId)
    .run();
}

interface HouseFixtureRow extends ChallengeRow {
  author_id: string | null;
  author_display_name: string | null;
  author_avatar_emoji: string | null;
}

async function findHouseFixture(
  db: D1Database,
  weekId: string,
): Promise<HouseFixtureRow | null> {
  return await first<HouseFixtureRow>(
    db
      .prepare(
        `SELECT c.*, u.id AS author_id, u.display_name AS author_display_name,
                u.avatar_emoji AS author_avatar_emoji
           FROM challenges c
           LEFT JOIN users u ON u.id = c.created_by
          WHERE c.week_id = ? AND c.is_house = 1
          ORDER BY c.position ASC, c.id ASC LIMIT 1`,
      )
      .bind(weekId),
  );
}

/**
 * Allowed author: the previous week's Man of the Match (any tied winner) or,
 * in the club's first week, the owner.
 */
async function isEligibleHouseAuthor(
  env: Env,
  group: GroupRow,
  week: WeekRow,
  userId: string,
): Promise<boolean> {
  const previous = await first<WeekRow>(
    env.DB.prepare(
      'SELECT * FROM weeks WHERE group_id = ? AND starts_at < ? ORDER BY starts_at DESC LIMIT 1',
    ).bind(group.id, week.starts_at),
  );
  if (!previous || week.number === 1) return group.owner_id === userId;

  const totals = await all<{ user_id: string; points: number }>(
    env.DB.prepare(
      `SELECT user_id, SUM(points) AS points FROM point_events
        WHERE group_id = ? AND week_id = ? GROUP BY user_id`,
    ).bind(group.id, previous.id),
  );
  const best = totals.reduce((max, row) => Math.max(max, row.points), 0);
  return best > 0 && totals.some((row) => row.user_id === userId && row.points === best);
}

export async function houseFixtureState(
  env: Env,
  group: GroupRow,
  week: WeekRow,
  userId: string,
  now: number,
): Promise<HouseFixtureJson> {
  const deadline = houseFixtureDeadline(week.starts_at, group.timezone);
  const existing = await findHouseFixture(env.DB, week.id);

  let author: PublicUser | null = null;
  if (existing && existing.vetoed_at === null && existing.author_id) {
    author = toPublicUser({
      id: existing.author_id,
      apple_sub: '',
      display_name: existing.author_display_name ?? '',
      avatar_emoji: existing.author_avatar_emoji,
      created_at: 0,
      terms_accepted_at: null,
    });
  }

  const allowed =
    !existing &&
    now <= deadline &&
    (await isEligibleHouseAuthor(env, group, week, userId));

  return { allowed, deadline, author };
}

export async function createHouseFixture(
  env: Env,
  params: {
    group: GroupRow;
    week: WeekRow;
    userId: string;
    title: string;
    description: string | null;
    difficulty: Difficulty;
    now: number;
  },
): Promise<ChallengeRow> {
  const existing = await findHouseFixture(env.DB, params.week.id);
  if (existing) {
    throw conflict('house_fixture_taken', 'This week already has a house fixture');
  }
  if (!(await isEligibleHouseAuthor(env, params.group, params.week, params.userId))) {
    throw forbidden('You are not allowed to add a house fixture this week');
  }
  const deadline = houseFixtureDeadline(params.week.starts_at, params.group.timezone);
  if (params.now > deadline) {
    throw conflict('house_fixture_closed', 'The house fixture window closed on Wednesday');
  }

  const maxPosition = await first<{ position: number | null }>(
    env.DB.prepare('SELECT MAX(position) AS position FROM challenges WHERE week_id = ?').bind(
      params.week.id,
    ),
  );
  const position = (maxPosition?.position ?? -1) + 1;

  const challenge: ChallengeRow = {
    id: randomId(),
    week_id: params.week.id,
    title: params.title,
    description: params.description ?? params.title,
    difficulty: params.difficulty,
    points: pointsForDifficulty(params.difficulty),
    position,
    vetoed_at: null,
    replaced_by: null,
    is_house: 1,
    created_by: params.userId,
    created_at: params.now,
  };

  await env.DB.prepare(
    `INSERT INTO challenges
       (id, week_id, title, description, difficulty, points, position,
        vetoed_at, replaced_by, is_house, created_by, created_at)
     VALUES (?, ?, ?, ?, ?, ?, ?, NULL, NULL, 1, ?, ?)`,
  )
    .bind(
      challenge.id,
      challenge.week_id,
      challenge.title,
      challenge.description,
      challenge.difficulty,
      challenge.points,
      challenge.position,
      challenge.created_by,
      challenge.created_at,
    )
    .run();

  return challenge;
}
