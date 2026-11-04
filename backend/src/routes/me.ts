import { Hono } from 'hono';
import { z } from 'zod';
import type { AppEnv, NotificationPrefsJson, UserRow } from '../types';
import { toPublicUser } from '../types';
import { first, nowSeconds } from '../lib/db';
import { badRequest } from '../lib/errors';
import { requireAuth } from '../middleware/auth';
import { parseJsonBody } from '../middleware/validate';
import { rateLimit } from '../middleware/rate-limit';
import { deleteAccount } from '../services/account';
import { userTrophies } from '../services/awards';
import { listBlockedUsers } from '../services/moderation';

const app = new Hono<AppEnv>();
app.use('*', requireAuth);

const patchMeSchema = z
  .object({
    displayName: z.string().trim().min(1).max(40).optional(),
    avatarEmoji: z.string().trim().max(32).nullable().optional(),
  })
  .strict()
  .refine((value) => Object.keys(value).length > 0, {
    message: 'At least one field is required',
  });

const notificationPrefsSchema = z
  .object({
    newWeek: z.boolean().optional(),
    voteNeeded: z.boolean().optional(),
    result: z.boolean().optional(),
    deadline: z.boolean().optional(),
    awards: z.boolean().optional(),
    banter: z.boolean().optional(),
  })
  .strict()
  .refine((value) => Object.keys(value).length > 0, {
    message: 'At least one field is required',
  });

const DEFAULT_PREFS: NotificationPrefsJson = {
  newWeek: true,
  voteNeeded: true,
  result: true,
  deadline: true,
  awards: true,
  banter: true,
};

/** /me is the only read that exposes terms acceptance. */
function meJson(user: UserRow): Record<string, unknown> {
  return { ...toPublicUser(user), termsAccepted: user.terms_accepted_at != null };
}

interface NotificationPrefsRow {
  user_id: string;
  new_week: number;
  vote_needed: number;
  result: number;
  deadline: number;
  awards: number;
  banter: number;
}

async function loadPrefs(db: D1Database, userId: string): Promise<NotificationPrefsJson> {
  const row = await first<NotificationPrefsRow>(
    db.prepare('SELECT * FROM notification_prefs WHERE user_id = ?').bind(userId),
  );
  if (!row) return { ...DEFAULT_PREFS };
  return {
    newWeek: row.new_week === 1,
    voteNeeded: row.vote_needed === 1,
    result: row.result === 1,
    deadline: row.deadline === 1,
    awards: row.awards === 1,
    banter: row.banter === 1,
  };
}

app.get('/', (c) => c.json({ user: meJson(c.get('userRow')) }));

/** POST /me/accept-terms — records App Store 1.2 house-rules acceptance. */
app.post('/accept-terms', rateLimit({ bucket: 'accept-terms', capacity: 10, refillPerSecond: 10 / 300, by: 'user' }), async (c) => {
  const userId = c.get('user').id;
  const now = nowSeconds();
  await c.env.DB.prepare(
    'UPDATE users SET terms_accepted_at = ? WHERE id = ? AND terms_accepted_at IS NULL',
  )
    .bind(now, userId)
    .run();

  const user = await first<UserRow>(c.env.DB.prepare('SELECT * FROM users WHERE id = ?').bind(userId));
  if (!user) throw new Error('user_missing_after_terms');
  return c.json({ user: meJson(user) });
});

/** GET /me/notification-prefs — all categories default to on. */
app.get('/notification-prefs', async (c) => {
  return c.json(await loadPrefs(c.env.DB, c.get('user').id));
});

/** PATCH /me/notification-prefs — partial update, returns the full set. */
app.patch('/notification-prefs', rateLimit({ bucket: 'notification-prefs', capacity: 30, refillPerSecond: 30 / 300, by: 'user' }), async (c) => {
  const body = await parseJsonBody(c, notificationPrefsSchema);
  const userId = c.get('user').id;
  const current = await loadPrefs(c.env.DB, userId);
  const next: NotificationPrefsJson = { ...current, ...body };

  await c.env.DB.prepare(
    `INSERT INTO notification_prefs
       (user_id, new_week, vote_needed, result, deadline, awards, banter)
     VALUES (?, ?, ?, ?, ?, ?, ?)
     ON CONFLICT(user_id) DO UPDATE SET
       new_week = excluded.new_week,
       vote_needed = excluded.vote_needed,
       result = excluded.result,
       deadline = excluded.deadline,
       awards = excluded.awards,
       banter = excluded.banter`,
  )
    .bind(
      userId,
      next.newWeek ? 1 : 0,
      next.voteNeeded ? 1 : 0,
      next.result ? 1 : 0,
      next.deadline ? 1 : 0,
      next.awards ? 1 : 0,
      next.banter ? 1 : 0,
    )
    .run();

  return c.json(next);
});

/** GET /me/blocks — users I blocked. */
app.get('/blocks', async (c) => {
  return c.json({ users: await listBlockedUsers(c.env.DB, c.get('user').id) });
});

/** GET /me/trophies — every monthly award this user has won, newest first. */
app.get('/trophies', async (c) => {
  return c.json({ trophies: await userTrophies(c.env.DB, c.get('user').id) });
});

app.patch('/', async (c) => {
  const body = await parseJsonBody(c, patchMeSchema);
  const sets: string[] = [];
  const bindings: unknown[] = [];

  if (body.displayName !== undefined) {
    sets.push('display_name = ?');
    bindings.push(body.displayName);
  }
  if (body.avatarEmoji !== undefined) {
    sets.push('avatar_emoji = ?');
    bindings.push(body.avatarEmoji === '' ? null : body.avatarEmoji);
  }
  if (sets.length === 0) throw badRequest('validation_error', 'At least one field is required');

  bindings.push(c.get('user').id);
  await c.env.DB.prepare(`UPDATE users SET ${sets.join(', ')} WHERE id = ?`)
    .bind(...bindings)
    .run();

  const user = await first<UserRow>(
    c.env.DB.prepare('SELECT * FROM users WHERE id = ?').bind(c.get('user').id),
  );
  if (!user) throw new Error('user_missing_after_update');
  return c.json({ user: meJson(user) });
});

app.delete('/', async (c) => {
  await deleteAccount(c.env, c.get('user').id);
  return c.json({ ok: true });
});

export default app;
