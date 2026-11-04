import type { Env } from './types';
import { all, chunk, placeholders } from './lib/db';
import { base64ToBytes, bytesToBase64Url } from './lib/crypto';
import { isBlocked } from './services/moderation';

/**
 * APNs push (best effort). All failures are swallowed: push must never fail a
 * request or a cron tick. Missing secrets are logged once per call and skipped.
 */

interface ApnsJwtCache {
  keyId: string;
  token: string;
  createdAt: number;
}

let jwtCache: ApnsJwtCache | null = null;
const JWT_TTL_SECONDS = 50 * 60;

export interface PushMessage {
  title: string;
  body: string;
  groupId: string;
  submissionId?: string;
}

/** Notification-preference category checked before every send. */
export type PushCategory =
  | 'newWeek'
  | 'voteNeeded'
  | 'result'
  | 'deadline'
  | 'awards'
  | 'banter';

const PREF_COLUMN: Record<PushCategory, string> = {
  newWeek: 'new_week',
  voteNeeded: 'vote_needed',
  result: 'result',
  deadline: 'deadline',
  awards: 'awards',
  banter: 'banter',
};

interface ApnsResult {
  status: number;
  token: string;
}

function normalizePem(value: string): string {
  return value.replace(/\\n/g, '\n').trim();
}

function pemToPkcs8(pem: string): Uint8Array {
  const body = normalizePem(pem)
    .replace(/-----BEGIN PRIVATE KEY-----/g, '')
    .replace(/-----END PRIVATE KEY-----/g, '')
    .replace(/\s+/g, '');
  return base64ToBytes(body);
}

async function apnsJwt(env: Env): Promise<string | null> {
  const keyP8 = env.APNS_KEY_P8;
  const keyId = env.APNS_KEY_ID;
  const teamId = env.APNS_TEAM_ID;
  if (!keyP8 || !keyId || !teamId) return null;

  const now = Math.floor(Date.now() / 1000);
  if (jwtCache && jwtCache.keyId === keyId && now - jwtCache.createdAt < JWT_TTL_SECONDS) {
    return jwtCache.token;
  }

  try {
    const key = await crypto.subtle.importKey(
      'pkcs8',
      pemToPkcs8(keyP8),
      { name: 'ECDSA', namedCurve: 'P-256' },
      false,
      ['sign'],
    );
    const header = bytesToBase64Url(
      new TextEncoder().encode(JSON.stringify({ alg: 'ES256', kid: keyId })),
    );
    const claims = bytesToBase64Url(
      new TextEncoder().encode(JSON.stringify({ iss: teamId, iat: now })),
    );
    const signingInput = `${header}.${claims}`;
    // WebCrypto ECDSA returns the raw 64-byte r||s that ES256 JWT expects.
    const signature = await crypto.subtle.sign(
      { name: 'ECDSA', hash: 'SHA-256' },
      key,
      new TextEncoder().encode(signingInput),
    );
    const token = `${signingInput}.${bytesToBase64Url(new Uint8Array(signature))}`;
    jwtCache = { keyId, token, createdAt: now };
    return token;
  } catch {
    return null;
  }
}

function apnsHost(env: Env): string {
  if (env.APNS_BASE_URL) return env.APNS_BASE_URL.replace(/\/+$/u, '');
  return env.APNS_ENV === 'sandbox'
    ? 'https://api.sandbox.push.apple.com'
    : 'https://api.push.apple.com';
}

async function sendOne(env: Env, jwt: string, token: string, message: PushMessage): Promise<ApnsResult> {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 10_000);
  try {
    const payload: Record<string, unknown> = {
      aps: {
        alert: { title: message.title, body: message.body },
        sound: 'default',
      },
      groupId: message.groupId,
    };
    if (message.submissionId) payload.submissionId = message.submissionId;

    const response = await fetch(`${apnsHost(env)}/3/device/${encodeURIComponent(token)}`, {
      method: 'POST',
      headers: {
        authorization: `bearer ${jwt}`,
        'apns-topic': env.APPLE_BUNDLE_ID,
        'apns-push-type': 'alert',
        'apns-priority': '10',
        'content-type': 'application/json',
      },
      body: JSON.stringify(payload),
      signal: controller.signal,
    });
    return { status: response.status, token };
  } catch {
    return { status: 0, token };
  } finally {
    clearTimeout(timeout);
  }
}

async function deleteTokens(env: Env, tokens: readonly string[]): Promise<void> {
  if (tokens.length === 0) return;
  for (const group of chunk(tokens, 50)) {
    try {
      await env.DB.prepare(`DELETE FROM devices WHERE apns_token IN (${placeholders(group.length)})`)
        .bind(...group)
        .run();
    } catch {
      // Best effort.
    }
  }
}

/**
 * Drops recipients who muted this category. A missing pref row means every
 * category stays on. `category` is a code constant, never user input.
 */
export async function filterRecipientsByPrefs(
  db: D1Database,
  userIds: readonly string[],
  category: PushCategory | undefined,
): Promise<string[]> {
  const unique = [...new Set(userIds)];
  if (!category || unique.length === 0) return unique;

  const column = PREF_COLUMN[category];
  const muted = new Set<string>();
  for (const group of chunk(unique, 50)) {
    const rows = await all<{ user_id: string }>(
      db
        .prepare(
          `SELECT user_id FROM notification_prefs
            WHERE user_id IN (${placeholders(group.length)}) AND ${column} = 0`,
        )
        .bind(...group),
    );
    for (const row of rows) muted.add(row.user_id);
  }
  return unique.filter((userId) => !muted.has(userId));
}

/** Recipients that have not blocked `actorId` (silent, one-way blocks). */
export async function excludeUsersBlockingActor(
  db: D1Database,
  actorId: string,
  userIds: readonly string[],
): Promise<string[]> {
  const unique = [...new Set(userIds)].filter((id) => id !== actorId);
  if (unique.length === 0) return [];
  const blocked = new Set<string>();
  for (const group of chunk(unique, 50)) {
    const rows = await all<{ blocker_id: string }>(
      db
        .prepare(
          `SELECT blocker_id FROM blocks
            WHERE blocked_id = ? AND blocker_id IN (${placeholders(group.length)})`,
        )
        .bind(actorId, ...group),
    );
    for (const row of rows) blocked.add(row.blocker_id);
  }
  return unique.filter((userId) => !blocked.has(userId));
}

async function tokensForUsers(env: Env, userIds: readonly string[]): Promise<string[]> {
  const tokens: string[] = [];
  for (const group of chunk([...new Set(userIds)], 50)) {
    const rows = await all<{ apns_token: string }>(
      env.DB.prepare(
        `SELECT apns_token FROM devices WHERE user_id IN (${placeholders(group.length)})`,
      ).bind(...group),
    );
    for (const row of rows) tokens.push(row.apns_token);
  }
  return [...new Set(tokens)];
}

export async function sendPushToUsers(
  env: Env,
  userIds: readonly string[],
  message: PushMessage,
  category?: PushCategory,
): Promise<void> {
  if (userIds.length === 0) return;
  if (!env.APNS_KEY_P8 || !env.APNS_KEY_ID || !env.APNS_TEAM_ID) {
    console.log('push_skipped', { reason: 'missing_secrets' });
    return;
  }

  try {
    const recipients = await filterRecipientsByPrefs(env.DB, userIds, category);
    if (recipients.length === 0) return;
    const jwt = await apnsJwt(env);
    if (!jwt) return;
    const tokens = await tokensForUsers(env, recipients);
    if (tokens.length === 0) return;

    const gone: string[] = [];
    let delivered = 0;
    for (const group of chunk(tokens, 20)) {
      const results = await Promise.all(group.map((token) => sendOne(env, jwt, token, message)));
      for (const result of results) {
        if (result.status === 200) delivered += 1;
        if (result.status === 410) gone.push(result.token);
        if (result.status !== 200 && result.status !== 410 && result.status !== 0) {
          // Status only: never log device tokens.
          console.log('push_failed', { status: result.status });
        }
      }
    }
    if (gone.length > 0) await deleteTokens(env, gone);
    console.log('push_sent', { delivered, gone: gone.length });
  } catch (error) {
    console.log('push_failed', { reason: error instanceof Error ? error.name : 'unknown' });
  }
}

async function groupMemberIds(env: Env, groupId: string, excludeUserId?: string): Promise<string[]> {
  const rows = await all<{ user_id: string }>(
    env.DB.prepare('SELECT user_id FROM group_members WHERE group_id = ?').bind(groupId),
  );
  return rows.map((row) => row.user_id).filter((id) => id !== excludeUserId);
}

export async function pushNewWeek(
  env: Env,
  groupId: string,
  challengeCount: number,
): Promise<void> {
  const members = await groupMemberIds(env, groupId);
  await sendPushToUsers(
    env,
    members,
    {
      title: 'A new week of dares is live',
      body: `${challengeCount} new dares are waiting for you.`,
      groupId,
    },
    'newWeek',
  );
}

export async function pushNewSubmission(
  env: Env,
  groupId: string,
  submitterId: string,
  challengeTitle: string,
  submissionId: string,
): Promise<void> {
  const members = await groupMemberIds(env, groupId, submitterId);
  const recipients = await excludeUsersBlockingActor(env.DB, submitterId, members);
  await sendPushToUsers(
    env,
    recipients,
    {
      title: 'New proof to vote on',
      body: `“${challengeTitle}” needs your vote.`,
      groupId,
      submissionId,
    },
    'voteNeeded',
  );
}

export async function pushDecision(
  env: Env,
  groupId: string,
  submitterId: string,
  submissionId: string,
  accepted: boolean,
  points: number,
): Promise<void> {
  await sendPushToUsers(
    env,
    [submitterId],
    {
      title: accepted ? 'Dare accepted!' : 'Dare rejected',
      body: accepted
        ? `Nice work — you earned ${points} points.`
        : 'The group did not accept this proof. You can try again while the week is open.',
      groupId,
      submissionId,
    },
    'result',
  );
}

export async function pushDeadlineReminder(
  env: Env,
  groupId: string,
  membersWithChallengesLeft: ReadonlyArray<{ userId: string; count: number }>,
): Promise<void> {
  for (const member of membersWithChallengesLeft) {
    if (member.count <= 0) continue;
    await sendPushToUsers(
      env,
      [member.userId],
      {
        title: 'Dare deadline tonight',
        body: `${member.count} challenge${member.count === 1 ? '' : 's'} left this week.`,
        groupId,
      },
      'deadline',
    );
  }
}

/** Monthly "Awards night" announcement (best effort, never fails cron). */
export async function pushAwardsLive(
  env: Env,
  groupId: string,
  monthName: string,
): Promise<void> {
  const members = await groupMemberIds(env, groupId);
  await sendPushToUsers(
    env,
    members,
    {
      title: `🏆 ${monthName} Awards is live`,
      body: 'Open the awards night to see who took home the silverware.',
      groupId,
    },
    'awards',
  );
}

/**
 * At most one "banter" push per submission per 10 minutes. The conditional
 * upsert is atomic, so concurrent reactions/comments cannot both win.
 */
export async function claimBanterPush(
  db: D1Database,
  submissionId: string,
  now: number,
): Promise<boolean> {
  const result = await db
    .prepare(
      `INSERT INTO banter_pushes (submission_id, last_sent_at) VALUES (?, ?)
       ON CONFLICT(submission_id) DO UPDATE SET last_sent_at = excluded.last_sent_at
        WHERE banter_pushes.last_sent_at <= ?`,
    )
    .bind(submissionId, now, now - 10 * 60)
    .run();
  return (result.meta.changes ?? 0) > 0;
}

/**
 * Banter push to the proof's submitter (reaction / comment). Respects the
 * banter pref, one-way blocks, self-actions and the 10-minute throttle.
 */
export async function pushBanter(
  env: Env,
  params: {
    groupId: string;
    submissionId: string;
    recipientId: string;
    actorId: string;
    title: string;
    body: string;
  },
): Promise<void> {
  if (params.recipientId === params.actorId) return;
  if (await isBlocked(env.DB, params.recipientId, params.actorId)) return;
  if (!(await claimBanterPush(env.DB, params.submissionId, Math.floor(Date.now() / 1000)))) {
    return;
  }
  await sendPushToUsers(
    env,
    [params.recipientId],
    {
      title: params.title,
      body: params.body,
      groupId: params.groupId,
      submissionId: params.submissionId,
    },
    'banter',
  );
}

/** "Alex added a house fixture" (banter pref, blocked authors filtered out). */
export async function pushHouseFixture(
  env: Env,
  groupId: string,
  authorId: string,
  authorName: string,
): Promise<void> {
  const members = await groupMemberIds(env, groupId, authorId);
  const recipients = await excludeUsersBlockingActor(env.DB, authorId, members);
  await sendPushToUsers(
    env,
    recipients,
    {
      title: 'House fixture added',
      body: `${authorName} added a house fixture.`,
      groupId,
    },
    'banter',
  );
}

/** "Fixture 03 was vetoed — new fixture is up" (banter pref). */
export async function pushFixtureVetoed(
  env: Env,
  groupId: string,
  position: number,
): Promise<void> {
  const members = await groupMemberIds(env, groupId);
  const label = String(position + 1).padStart(2, '0');
  await sendPushToUsers(
    env,
    members,
    {
      title: 'Fixture vetoed',
      body: `Fixture ${label} was vetoed — new fixture is up.`,
      groupId,
    },
    'banter',
  );
}

/** Safety notice to the club owner when reported content is removed. */
export async function pushContentRemoved(
  env: Env,
  ownerId: string,
  groupId: string,
  targetType: 'submission' | 'comment',
): Promise<void> {
  await sendPushToUsers(env, [ownerId], {
    title:
      targetType === 'submission'
        ? 'A proof was removed after reports'
        : 'A comment was removed after reports',
    body: 'The club reported it and it is now hidden.',
    groupId,
  });
}

/** Test helper. */
export function clearApnsJwtCache(): void {
  jwtCache = null;
}
