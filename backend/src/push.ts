import type { Env } from './types';
import { all, chunk, placeholders } from './lib/db';
import { base64ToBytes, bytesToBase64Url } from './lib/crypto';

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
): Promise<void> {
  if (userIds.length === 0) return;
  if (!env.APNS_KEY_P8 || !env.APNS_KEY_ID || !env.APNS_TEAM_ID) {
    console.log('push_skipped', { reason: 'missing_secrets' });
    return;
  }

  try {
    const jwt = await apnsJwt(env);
    if (!jwt) return;
    const tokens = await tokensForUsers(env, userIds);
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
  await sendPushToUsers(env, members, {
    title: 'A new week of dares is live',
    body: `${challengeCount} new dares are waiting for you.`,
    groupId,
  });
}

export async function pushNewSubmission(
  env: Env,
  groupId: string,
  submitterId: string,
  challengeTitle: string,
  submissionId: string,
): Promise<void> {
  const members = await groupMemberIds(env, groupId, submitterId);
  await sendPushToUsers(env, members, {
    title: 'New proof to vote on',
    body: `“${challengeTitle}” needs your vote.`,
    groupId,
    submissionId,
  });
}

export async function pushDecision(
  env: Env,
  groupId: string,
  submitterId: string,
  submissionId: string,
  accepted: boolean,
  points: number,
): Promise<void> {
  await sendPushToUsers(env, [submitterId], {
    title: accepted ? 'Dare accepted!' : 'Dare rejected',
    body: accepted
      ? `Nice work — you earned ${points} points.`
      : 'The group did not accept this proof. You can try again while the week is open.',
    groupId,
    submissionId,
  });
}

export async function pushDeadlineReminder(
  env: Env,
  groupId: string,
  membersWithChallengesLeft: ReadonlyArray<{ userId: string; count: number }>,
): Promise<void> {
  for (const member of membersWithChallengesLeft) {
    if (member.count <= 0) continue;
    await sendPushToUsers(env, [member.userId], {
      title: 'Dare deadline tonight',
      body: `${member.count} challenge${member.count === 1 ? '' : 's'} left this week.`,
      groupId,
    });
  }
}

/** Test helper. */
export function clearApnsJwtCache(): void {
  jwtCache = null;
}
