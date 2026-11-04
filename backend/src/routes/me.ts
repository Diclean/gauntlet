import { Hono } from 'hono';
import { z } from 'zod';
import type { AppEnv, UserRow } from '../types';
import { toPublicUser } from '../types';
import { first } from '../lib/db';
import { badRequest } from '../lib/errors';
import { requireAuth } from '../middleware/auth';
import { parseJsonBody } from '../middleware/validate';
import { deleteAccount } from '../services/account';

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

app.get('/', (c) => c.json({ user: c.get('user') }));

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
  return c.json({ user: toPublicUser(user) });
});

app.delete('/', async (c) => {
  await deleteAccount(c.env, c.get('user').id);
  return c.json({ ok: true });
});

export default app;
