import { Hono } from 'hono';
import { z } from 'zod';
import type { AppEnv, GroupRow, WeekRow } from '../types';
import { all, first, nowSeconds } from '../lib/db';
import { randomId } from '../lib/crypto';
import { ApiError, badRequest, conflict, notFound } from '../lib/errors';
import { isValidTimeZone } from '../business/time';
import { requireAuth } from '../middleware/auth';
import { parseJsonBody } from '../middleware/validate';
import { rateLimit } from '../middleware/rate-limit';
import { runInBackground } from '../middleware/background';
import {
  DEFAULT_FORFEIT,
  GROUP_MAX_MEMBERS,
  MAX_FORFEIT_LENGTH,
  countMembers,
  countWeekReplacements,
  generateInviteCode,
  getGroupRow,
  getMembership,
  captainMapForWeeks,
  groupJson,
  groupJsonWithCount,
  listBans,
  listMembers,
  replacementsForWeeks,
  requireGroupMembership,
  requireGroupOwnership,
  weekJson,
} from '../services/groups';
import {
  challengeWithMyStatus,
  challengesWithMyStatus,
  ensureCurrentWeek,
  getWeekById,
  leaderboard,
} from '../services/weeks';
import {
  chooseCaptain,
  createHouseFixture,
  houseFixtureState,
} from '../services/fixtures';
import { groupRace, weekReceipt } from '../services/stats';
import { deleteMediaKeys } from '../services/media';
import { groupAwards, listAwardMonths } from '../services/awards';
import { isValidMonthKey } from '../business/time';
import { decodeCursor, listFeed, listPendingVotes } from '../services/submissions';
import { deleteGroupCompletely } from '../services/account';
import { pushHouseFixture, pushNewWeek } from '../push';

const app = new Hono<AppEnv>();
app.use('*', requireAuth);

const INVITE_CODE_PATTERN = /^[A-Z2-9]{6}$/u;

/**
 * Join and preview deliberately share the same user + IP buckets, so invite
 * code guessing has one global budget no matter which endpoint is probed.
 */
const joinUserRateLimit = rateLimit({
  bucket: 'group-join',
  capacity: 10,
  refillPerSecond: 10 / 60,
  by: 'user',
});
const joinIpRateLimit = rateLimit({
  bucket: 'group-join-ip',
  capacity: 30,
  refillPerSecond: 30 / 60,
  by: 'ip',
});

const timezoneSchema = z
  .string()
  .trim()
  .min(1)
  .max(64)
  .refine(isValidTimeZone, { message: 'timezone must be a valid IANA time zone' });

const createGroupSchema = z
  .object({
    name: z.string().trim().min(1).max(80),
    challengesPerWeek: z.number().int().min(3).max(10).optional(),
    theme: z.string().trim().max(200).nullable().optional(),
    language: z.enum(['en', 'fr']).optional(),
    timezone: timezoneSchema,
  })
  .strict();

const joinGroupSchema = z
  .object({
    inviteCode: z
      .string()
      .trim()
      .transform((value) => value.toUpperCase())
      .pipe(z.string().regex(INVITE_CODE_PATTERN, 'Invite code must be 6 characters')),
  })
  .strict();

const captainSchema = z
  .object({
    challengeId: z.string().trim().min(1).max(64),
  })
  .strict();

const houseFixtureSchema = z
  .object({
    title: z.string().trim().min(3).max(80),
    description: z.string().trim().max(300).optional(),
    difficulty: z.enum(['easy', 'medium', 'hard']),
  })
  .strict();

const patchGroupSchema = z
  .object({
    name: z.string().trim().min(1).max(80).optional(),
    challengesPerWeek: z.number().int().min(3).max(10).optional(),
    theme: z.string().trim().max(200).nullable().optional(),
    language: z.enum(['en', 'fr']).optional(),
    timezone: timezoneSchema.optional(),
    forfeit: z.string().trim().min(1).max(MAX_FORFEIT_LENGTH).optional(),
  })
  .strict()
  .refine((value) => Object.keys(value).length > 0, {
    message: 'At least one field is required',
  });

function normalizeTheme(theme: string | null | undefined): string | null {
  if (theme === undefined || theme === null) return null;
  const trimmed = theme.trim();
  return trimmed.length > 0 ? trimmed : null;
}

/** GET /groups — groups I am a member of. */
app.get('/', async (c) => {
  const rows = await all<GroupRow & { member_count: number }>(
    c.env.DB.prepare(
      `SELECT g.*, (SELECT COUNT(*) FROM group_members m2 WHERE m2.group_id = g.id) AS member_count
         FROM groups g
         JOIN group_members m ON m.group_id = g.id
        WHERE m.user_id = ?
        ORDER BY g.created_at DESC, g.id DESC`,
    ).bind(c.get('user').id),
  );
  return c.json({
    groups: rows.map((row) =>
      groupJsonWithCount(row, row.member_count, c.env.PUBLIC_BASE_URL),
    ),
  });
});

/** POST /groups — creates the group and immediately generates its current week. */
app.post('/', rateLimit({ bucket: 'group-create', capacity: 10, refillPerSecond: 10 / 300, by: 'user' }), async (c) => {
  const body = await parseJsonBody(c, createGroupSchema);
  const ownerId = c.get('user').id;
  const now = nowSeconds();

  let group: GroupRow | null = null;
  let lastError: unknown = null;
  for (let attempt = 0; attempt < 5 && !group; attempt += 1) {
    const candidate: GroupRow = {
      id: randomId(),
      name: body.name,
      owner_id: ownerId,
      invite_code: generateInviteCode(),
      challenges_per_week: body.challengesPerWeek ?? 5,
      theme: normalizeTheme(body.theme),
      language: body.language ?? 'en',
      timezone: body.timezone,
      forfeit: DEFAULT_FORFEIT,
      created_at: now,
    };
    try {
      await c.env.DB.batch([
        c.env.DB.prepare(
          `INSERT INTO groups
             (id, name, owner_id, invite_code, challenges_per_week, theme, language, timezone, forfeit, created_at)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
        ).bind(
          candidate.id,
          candidate.name,
          candidate.owner_id,
          candidate.invite_code,
          candidate.challenges_per_week,
          candidate.theme,
          candidate.language,
          candidate.timezone,
          candidate.forfeit,
          candidate.created_at,
        ),
        c.env.DB.prepare(
          'INSERT INTO group_members (group_id, user_id, joined_at) VALUES (?, ?, ?)',
        ).bind(candidate.id, ownerId, now),
      ]);
      group = candidate;
    } catch (error) {
      lastError = error;
    }
  }
  if (!group) throw lastError instanceof Error ? lastError : new Error('group_create_failed');

  // Spec: creating a group also generates the current week immediately.
  try {
    const week = await ensureCurrentWeek(c.env, group, now);
    if (week.created) {
      runInBackground(c, pushNewWeek(c.env, group.id, week.challenges.length));
    }
  } catch (error) {
    // The group still exists; the next read/cron tick retries week generation.
    console.error('week_generation_failed', {
      name: error instanceof Error ? error.name : 'Error',
    });
  }

  return c.json({ group: await groupJson(c.env.DB, group, c.env.PUBLIC_BASE_URL) }, 201);
});

/** POST /groups/join — join with a 6-character invite code. */
app.post(
  '/join',
  joinUserRateLimit,
  // Independent IP bucket so many accounts behind one address cannot brute
  // force invite codes (or mass-join) at the per-user budget.
  joinIpRateLimit,
  async (c) => {
    const body = await parseJsonBody(c, joinGroupSchema);
    const userId = c.get('user').id;

    const group = await first<GroupRow>(
      c.env.DB.prepare('SELECT * FROM groups WHERE invite_code = ?').bind(body.inviteCode),
    );
    if (!group) throw new ApiError(404, 'invalid_invite_code', 'Invalid invite code');

    const banned = await first<{ one: number }>(
      c.env.DB.prepare('SELECT 1 AS one FROM group_bans WHERE group_id = ? AND user_id = ?').bind(
        group.id,
        userId,
      ),
    );
    if (banned) throw new ApiError(403, 'banned', 'You are banned from this club');

    const existing = await getMembership(c.env.DB, group.id, userId);
    if (!existing) {
      // The capacity check and the insert are one statement: COUNT-then-INSERT
      // let concurrent joins all observe 29 and blow past the 30-member cap.
      let insertChanges = 0;
      let insertError: unknown = null;
      try {
        const inserted = await c.env.DB.prepare(
          `INSERT INTO group_members (group_id, user_id, joined_at)
           SELECT ?, ?, ?
            WHERE (SELECT COUNT(*) FROM group_members WHERE group_id = ?) < ?`,
        )
          .bind(group.id, userId, nowSeconds(), group.id, GROUP_MAX_MEMBERS)
          .run();
        insertChanges = inserted.meta.changes ?? 0;
      } catch (error) {
        // Concurrent insert for this same (group, user): idempotent.
        insertError = error;
      }

      if (insertChanges === 0) {
        const nowMember = await getMembership(c.env.DB, group.id, userId);
        if (!nowMember) {
          if (insertError) throw insertError;
          throw conflict('group_full', `This group already has ${GROUP_MAX_MEMBERS} members`);
        }
      }
    }

    return c.json({ group: await groupJson(c.env.DB, group, c.env.PUBLIC_BASE_URL) });
  },
);

/**
 * GET /groups/preview/:code — the iOS join confirmation screen. Auth is
 * required, but the terms gate only covers writes, so an invited user can
 * preview the club before accepting the house rules. Unknown, malformed and
 * banned codes all get the same 404 (no club enumeration).
 */
app.get('/preview/:code', joinUserRateLimit, joinIpRateLimit, async (c) => {
  const code = c.req.param('code').trim().toUpperCase();
  if (!INVITE_CODE_PATTERN.test(code)) throw notFound('Club not found');

  const group = await first<GroupRow>(
    c.env.DB.prepare('SELECT * FROM groups WHERE invite_code = ?').bind(code),
  );
  if (!group) throw notFound('Club not found');

  const banned = await first<{ one: number }>(
    c.env.DB.prepare('SELECT 1 AS one FROM group_bans WHERE group_id = ? AND user_id = ?').bind(
      group.id,
      c.get('user').id,
    ),
  );
  if (banned) throw notFound('Club not found');

  return c.json({ group: await groupJson(c.env.DB, group, c.env.PUBLIC_BASE_URL) });
});

/** GET /groups/:id — group + members, members only. */
app.get('/:id', async (c) => {
  const group = await requireGroupMembership(c.env.DB, c.req.param('id'), c.get('user').id);
  return c.json({
    group: await groupJson(c.env.DB, group, c.env.PUBLIC_BASE_URL),
    members: await listMembers(c.env.DB, group.id),
  });
});

/** PATCH /groups/:id — owner only; settings apply from the next generated week. */
app.patch('/:id', async (c) => {
  const group = await requireGroupOwnership(c.env.DB, c.req.param('id'), c.get('user').id);
  const body = await parseJsonBody(c, patchGroupSchema);

  const sets: string[] = [];
  const bindings: unknown[] = [];
  if (body.name !== undefined) {
    sets.push('name = ?');
    bindings.push(body.name);
  }
  if (body.challengesPerWeek !== undefined) {
    sets.push('challenges_per_week = ?');
    bindings.push(body.challengesPerWeek);
  }
  if (body.theme !== undefined) {
    sets.push('theme = ?');
    bindings.push(normalizeTheme(body.theme));
  }
  if (body.language !== undefined) {
    sets.push('language = ?');
    bindings.push(body.language);
  }
  if (body.timezone !== undefined) {
    sets.push('timezone = ?');
    bindings.push(body.timezone);
  }
  if (body.forfeit !== undefined) {
    sets.push('forfeit = ?');
    bindings.push(body.forfeit);
  }
  if (sets.length === 0) throw badRequest('validation_error', 'At least one field is required');

  bindings.push(group.id);
  await c.env.DB.prepare(`UPDATE groups SET ${sets.join(', ')} WHERE id = ?`)
    .bind(...bindings)
    .run();

  const updated = await getGroupRow(c.env.DB, group.id);
  if (!updated) throw notFound('Group not found');
  return c.json({ group: await groupJson(c.env.DB, updated, c.env.PUBLIC_BASE_URL) });
});

/** POST /groups/:id/leave — owner transfers to the earliest remaining member. */
app.post('/:id/leave', async (c) => {
  const group = await requireGroupMembership(c.env.DB, c.req.param('id'), c.get('user').id);
  const userId = c.get('user').id;
  const members = await countMembers(c.env.DB, group.id);

  if (members <= 1) {
    await deleteGroupCompletely(c.env, group.id);
    return c.json({ ok: true });
  }

  const expiringMedia = await all<{ media_key: string }>(
    c.env.DB.prepare(
      `SELECT media_key FROM submissions
        WHERE user_id = ? AND status = 'pending'
          AND challenge_id IN (
            SELECT c.id FROM challenges c
            JOIN weeks w ON w.id = c.week_id
            WHERE w.group_id = ?
          )`,
    ).bind(userId, group.id),
  );

  const statements: D1PreparedStatement[] = [
    c.env.DB.prepare(
      `UPDATE submissions SET status = 'expired'
        WHERE user_id = ? AND status = 'pending'
          AND challenge_id IN (
            SELECT c.id FROM challenges c
            JOIN weeks w ON w.id = c.week_id
            WHERE w.group_id = ?
          )`,
    ).bind(userId, group.id),
    c.env.DB.prepare('DELETE FROM group_members WHERE group_id = ? AND user_id = ?').bind(
      group.id,
      userId,
    ),
  ];

  if (group.owner_id === userId) {
    const successor = await first<{ user_id: string }>(
      c.env.DB.prepare(
        `SELECT user_id FROM group_members
          WHERE group_id = ? AND user_id <> ?
          ORDER BY joined_at ASC, user_id ASC LIMIT 1`,
      ).bind(group.id, userId),
    );
    if (successor) {
      statements.push(
        c.env.DB.prepare('UPDATE groups SET owner_id = ? WHERE id = ?').bind(
          successor.user_id,
          group.id,
        ),
      );
    }
  }

  await c.env.DB.batch(statements);
  await deleteMediaKeys(c.env, expiringMedia.map((row) => row.media_key));
  return c.json({ ok: true });
});

/** GET /groups/:id/week — current week + challenges with the caller's status. */
app.get('/:id/week', async (c) => {
  const userId = c.get('user').id;
  const group = await requireGroupMembership(c.env.DB, c.req.param('id'), userId);
  const now = nowSeconds();
  const created = await ensureCurrentWeek(c.env, group, now);
  if (created.created) {
    runInBackground(c, pushNewWeek(c.env, group.id, created.challenges.length));
  }
  const [members, captain, vetoesUsed] = await Promise.all([
    countMembers(c.env.DB, group.id),
    first<{ challenge_id: string }>(
      c.env.DB.prepare('SELECT challenge_id FROM captains WHERE week_id = ? AND user_id = ?').bind(
        created.week.id,
        userId,
      ),
    ),
    countWeekReplacements(c.env.DB, created.week.id),
  ]);
  const challenges = await challengesWithMyStatus(
    c.env.DB,
    created.week.id,
    userId,
    members,
    now,
  );
  const houseFixture = await houseFixtureState(c.env, group, created.week, userId, now);
  return c.json({
    week: weekJson(created.week, captain?.challenge_id ?? null, vetoesUsed),
    challenges,
    houseFixture,
  });
});

/** PUT /groups/:id/week/captain — pick/change my armband fixture for this week. */
app.put('/:id/week/captain', rateLimit({ bucket: 'captain', capacity: 20, refillPerSecond: 20 / 300, by: 'user' }), async (c) => {
  const userId = c.get('user').id;
  const group = await requireGroupMembership(c.env.DB, c.req.param('id'), userId);
  const body = await parseJsonBody(c, captainSchema);
  const now = nowSeconds();
  const created = await ensureCurrentWeek(c.env, group, now);

  await chooseCaptain(c.env.DB, {
    week: created.week,
    userId,
    challengeId: body.challengeId,
    now,
  });

  const vetoesUsed = await countWeekReplacements(c.env.DB, created.week.id);
  return c.json({ week: weekJson(created.week, body.challengeId, vetoesUsed) });
});

/** POST /groups/:id/week/house-fixture — one member-written fixture per week. */
app.post('/:id/week/house-fixture', rateLimit({ bucket: 'house-fixture', capacity: 5, refillPerSecond: 5 / 300, by: 'user' }), async (c) => {
  const userId = c.get('user').id;
  const group = await requireGroupMembership(c.env.DB, c.req.param('id'), userId);
  const body = await parseJsonBody(c, houseFixtureSchema);
  const now = nowSeconds();
  const created = await ensureCurrentWeek(c.env, group, now);
  const members = await countMembers(c.env.DB, group.id);

  const challenge = await createHouseFixture(c.env, {
    group,
    week: created.week,
    userId,
    title: body.title,
    description: body.description && body.description.length > 0 ? body.description : null,
    difficulty: body.difficulty,
    now,
  });

  const json = await challengeWithMyStatus(c.env.DB, challenge.id, userId, members, now);
  if (!json) throw new Error('house_fixture_missing_after_insert');

  runInBackground(c, pushHouseFixture(c.env, group.id, userId, c.get('user').displayName));
  return c.json({ challenge: json }, 201);
});

/** POST /groups/:id/members/:userId/remove — owner removes + bans a member. */
app.post('/:id/members/:userId/remove', rateLimit({ bucket: 'member-remove', capacity: 10, refillPerSecond: 10 / 300, by: 'user' }), async (c) => {
  const ownerId = c.get('user').id;
  const group = await requireGroupOwnership(c.env.DB, c.req.param('id'), ownerId);
  const targetId = c.req.param('userId');
  if (targetId === ownerId) {
    throw badRequest('validation_error', 'The owner cannot remove themselves');
  }

  const membership = await getMembership(c.env.DB, group.id, targetId);
  if (!membership) throw notFound('Member not found');

  const expiringMedia = await all<{ media_key: string }>(
    c.env.DB.prepare(
      `SELECT media_key FROM submissions
        WHERE user_id = ? AND status = 'pending'
          AND challenge_id IN (
            SELECT c.id FROM challenges c
            JOIN weeks w ON w.id = c.week_id
            WHERE w.group_id = ?
          )`,
    ).bind(targetId, group.id),
  );

  await c.env.DB.batch([
    c.env.DB.prepare(
      `UPDATE submissions SET status = 'expired'
        WHERE user_id = ? AND status = 'pending'
          AND challenge_id IN (
            SELECT c.id FROM challenges c
            JOIN weeks w ON w.id = c.week_id
            WHERE w.group_id = ?
          )`,
    ).bind(targetId, group.id),
    c.env.DB.prepare('DELETE FROM group_members WHERE group_id = ? AND user_id = ?').bind(
      group.id,
      targetId,
    ),
    c.env.DB.prepare(
      `INSERT INTO group_bans (group_id, user_id, created_at) VALUES (?, ?, ?)
       ON CONFLICT(group_id, user_id) DO NOTHING`,
    ).bind(group.id, targetId, nowSeconds()),
  ]);

  await deleteMediaKeys(c.env, expiringMedia.map((row) => row.media_key));
  return c.json({ ok: true });
});

/** DELETE /groups/:id/members/:userId/ban — owner lifts a ban. */
app.delete('/:id/members/:userId/ban', rateLimit({ bucket: 'member-unban', capacity: 10, refillPerSecond: 10 / 300, by: 'user' }), async (c) => {
  const group = await requireGroupOwnership(c.env.DB, c.req.param('id'), c.get('user').id);
  await c.env.DB.prepare('DELETE FROM group_bans WHERE group_id = ? AND user_id = ?')
    .bind(group.id, c.req.param('userId'))
    .run();
  return c.json({ ok: true });
});

/** GET /groups/:id/bans — owner only; banned (removed) members, newest first. */
app.get('/:id/bans', async (c) => {
  const group = await requireGroupOwnership(c.env.DB, c.req.param('id'), c.get('user').id);
  return c.json({ users: await listBans(c.env.DB, group.id) });
});

/** GET /groups/:id/feed?cursor= — newest submissions first, 20 per page. */
app.get('/:id/feed', async (c) => {
  const group = await requireGroupMembership(c.env.DB, c.req.param('id'), c.get('user').id);
  const rawCursor = c.req.query('cursor');
  const cursor = rawCursor ? decodeCursor(rawCursor) : null;
  const page = await listFeed(c.env.DB, group.id, c.get('user').id, cursor);
  return c.json({ items: page.items, nextCursor: page.nextCursor });
});

/** GET /groups/:id/votes/pending — proofs I can still vote on, oldest first. */
app.get('/:id/votes/pending', async (c) => {
  const group = await requireGroupMembership(c.env.DB, c.req.param('id'), c.get('user').id);
  const items = await listPendingVotes(
    c.env.DB,
    group.id,
    c.get('user').id,
    nowSeconds(),
  );
  return c.json({ items });
});

/** GET /groups/:id/stats/race — cumulative points per member per week. */
app.get('/:id/stats/race', async (c) => {
  const group = await requireGroupMembership(c.env.DB, c.req.param('id'), c.get('user').id);
  return c.json(await groupRace(c.env.DB, group.id, c.get('user').id));
});

/** GET /groups/:id/weeks?limit=10 — closed weeks (past receipts), newest first. */
app.get('/:id/weeks', async (c) => {
  const group = await requireGroupMembership(c.env.DB, c.req.param('id'), c.get('user').id);
  const rawLimit = c.req.query('limit');
  let limit = 10;
  if (rawLimit !== undefined) {
    if (!/^\d+$/u.test(rawLimit)) {
      throw badRequest('validation_error', 'limit must be a positive integer');
    }
    limit = Number(rawLimit);
    if (limit < 1 || limit > 50) {
      throw badRequest('validation_error', 'limit must be between 1 and 50');
    }
  }

  const rows = await all<WeekRow>(
    c.env.DB.prepare(
      `SELECT * FROM weeks
        WHERE group_id = ? AND status = 'closed'
        ORDER BY starts_at DESC LIMIT ?`,
    ).bind(group.id, limit),
  );
  const captains = await captainMapForWeeks(
    c.env.DB,
    rows.map((row) => row.id),
    c.get('user').id,
  );
  const replacements = await replacementsForWeeks(
    c.env.DB,
    rows.map((row) => row.id),
  );
  return c.json({
    weeks: rows.map((row) =>
      weekJson(row, captains.get(row.id) ?? null, replacements.get(row.id) ?? 0),
    ),
  });
});

/** GET /groups/:id/weeks/:weekId/receipt — full-time receipt (members only). */
app.get('/:id/weeks/:weekId/receipt', async (c) => {
  const group = await requireGroupMembership(c.env.DB, c.req.param('id'), c.get('user').id);
  const week = await getWeekById(c.env.DB, c.req.param('weekId'));
  if (!week || week.group_id !== group.id) throw notFound('Week not found');
  return c.json(await weekReceipt(c.env.DB, group, week, c.get('user').id));
});

/** GET /groups/:id/awards/months — months that have a stored awards night. */
app.get('/:id/awards/months', async (c) => {
  const group = await requireGroupMembership(c.env.DB, c.req.param('id'), c.get('user').id);
  return c.json({ months: await listAwardMonths(c.env.DB, group.id) });
});

/** GET /groups/:id/awards?month=YYYY-MM — default latest stored month. */
app.get('/:id/awards', async (c) => {
  const group = await requireGroupMembership(c.env.DB, c.req.param('id'), c.get('user').id);
  const month = c.req.query('month');
  if (month !== undefined && !isValidMonthKey(month)) {
    throw badRequest('validation_error', 'month must be formatted as YYYY-MM');
  }
  return c.json(await groupAwards(c.env.DB, group, month));
});

/** GET /groups/:id/leaderboard?scope=week|all */
app.get('/:id/leaderboard', async (c) => {
  const group = await requireGroupMembership(c.env.DB, c.req.param('id'), c.get('user').id);
  const scope = c.req.query('scope') ?? 'week';
  if (scope !== 'week' && scope !== 'all') {
    throw badRequest('validation_error', 'scope must be "week" or "all"');
  }
  const result = await leaderboard(c.env.DB, group.id, scope);
  return c.json({ entries: result.entries });
});

export default app;
