import { Hono } from 'hono';
import { z } from 'zod';
import type { AppEnv, GroupRow } from '../types';
import { all, first, nowSeconds } from '../lib/db';
import { randomId } from '../lib/crypto';
import { ApiError, badRequest, conflict, notFound } from '../lib/errors';
import { isValidTimeZone } from '../business/time';
import { requireAuth } from '../middleware/auth';
import { parseJsonBody } from '../middleware/validate';
import { rateLimit } from '../middleware/rate-limit';
import { runInBackground } from '../middleware/background';
import {
  GROUP_MAX_MEMBERS,
  countMembers,
  generateInviteCode,
  getGroupRow,
  getMembership,
  groupJson,
  groupJsonWithCount,
  listMembers,
  requireGroupMembership,
  requireGroupOwnership,
  weekJson,
} from '../services/groups';
import {
  challengesWithMyStatus,
  ensureCurrentWeek,
  leaderboard,
} from '../services/weeks';
import { decodeCursor, listFeed, listPendingVotes } from '../services/submissions';
import { deleteGroupCompletely } from '../services/account';
import { pushNewWeek } from '../push';

const app = new Hono<AppEnv>();
app.use('*', requireAuth);

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
      .pipe(z.string().regex(/^[A-Z2-9]{6}$/u, 'Invite code must be 6 characters')),
  })
  .strict();

const patchGroupSchema = z
  .object({
    name: z.string().trim().min(1).max(80).optional(),
    challengesPerWeek: z.number().int().min(3).max(10).optional(),
    theme: z.string().trim().max(200).nullable().optional(),
    language: z.enum(['en', 'fr']).optional(),
    timezone: timezoneSchema.optional(),
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
  return c.json({ groups: rows.map((row) => groupJsonWithCount(row, row.member_count)) });
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
      created_at: now,
    };
    try {
      await c.env.DB.batch([
        c.env.DB.prepare(
          `INSERT INTO groups
             (id, name, owner_id, invite_code, challenges_per_week, theme, language, timezone, created_at)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
        ).bind(
          candidate.id,
          candidate.name,
          candidate.owner_id,
          candidate.invite_code,
          candidate.challenges_per_week,
          candidate.theme,
          candidate.language,
          candidate.timezone,
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

  return c.json({ group: await groupJson(c.env.DB, group) }, 201);
});

/** POST /groups/join — join with a 6-character invite code. */
app.post('/join', rateLimit({ bucket: 'group-join', capacity: 10, refillPerSecond: 10 / 60, by: 'user' }), async (c) => {
  const body = await parseJsonBody(c, joinGroupSchema);
  const userId = c.get('user').id;

  const group = await first<GroupRow>(
    c.env.DB.prepare('SELECT * FROM groups WHERE invite_code = ?').bind(body.inviteCode),
  );
  if (!group) throw new ApiError(404, 'invalid_invite_code', 'Invalid invite code');

  const existing = await getMembership(c.env.DB, group.id, userId);
  if (!existing) {
    const members = await countMembers(c.env.DB, group.id);
    if (members >= GROUP_MAX_MEMBERS) {
      throw conflict('group_full', `This group already has ${GROUP_MAX_MEMBERS} members`);
    }
    try {
      await c.env.DB.prepare(
        'INSERT INTO group_members (group_id, user_id, joined_at) VALUES (?, ?, ?)',
      )
        .bind(group.id, userId, nowSeconds())
        .run();
    } catch {
      // Concurrent join for the same membership: idempotent.
    }
  }

  return c.json({ group: await groupJson(c.env.DB, group) });
});

/** GET /groups/:id — group + members, members only. */
app.get('/:id', async (c) => {
  const group = await requireGroupMembership(c.env.DB, c.req.param('id'), c.get('user').id);
  return c.json({
    group: await groupJson(c.env.DB, group),
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
  if (sets.length === 0) throw badRequest('validation_error', 'At least one field is required');

  bindings.push(group.id);
  await c.env.DB.prepare(`UPDATE groups SET ${sets.join(', ')} WHERE id = ?`)
    .bind(...bindings)
    .run();

  const updated = await getGroupRow(c.env.DB, group.id);
  if (!updated) throw notFound('Group not found');
  return c.json({ group: await groupJson(c.env.DB, updated) });
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
  return c.json({ ok: true });
});

/** GET /groups/:id/week — current week + challenges with the caller's status. */
app.get('/:id/week', async (c) => {
  const group = await requireGroupMembership(c.env.DB, c.req.param('id'), c.get('user').id);
  const now = nowSeconds();
  const created = await ensureCurrentWeek(c.env, group, now);
  if (created.created) {
    runInBackground(c, pushNewWeek(c.env, group.id, created.challenges.length));
  }
  const challenges = await challengesWithMyStatus(c.env.DB, created.week.id, c.get('user').id);
  return c.json({ week: weekJson(created.week), challenges });
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
