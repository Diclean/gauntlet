import type { UserRow } from '../types';
import { first, nowSeconds } from '../lib/db';
import { randomToken, sha256Hex } from '../lib/crypto';

export const SESSION_TTL_SECONDS = 60 * 24 * 60 * 60; // 60 days

export interface CreatedSession {
  token: string;
  tokenHash: string;
  expiresAt: number;
}

/**
 * Creates a 32-byte opaque bearer token. Only its SHA-256 lands in D1, so a DB
 * dump does not expose usable sessions.
 */
export async function createSession(
  db: D1Database,
  userId: string,
  now: number = nowSeconds(),
): Promise<CreatedSession> {
  const token = randomToken();
  const tokenHash = await sha256Hex(token);
  const expiresAt = now + SESSION_TTL_SECONDS;
  await db
    .prepare(
      'INSERT INTO sessions (token_hash, user_id, expires_at, created_at) VALUES (?, ?, ?, ?)',
    )
    .bind(tokenHash, userId, expiresAt, now)
    .run();
  return { token, tokenHash, expiresAt };
}

export async function hashSessionToken(token: string): Promise<string> {
  return await sha256Hex(token);
}

export async function findUserBySessionHash(
  db: D1Database,
  tokenHash: string,
  now: number = nowSeconds(),
): Promise<UserRow | null> {
  return await first<UserRow>(
    db
      .prepare(
        `SELECT u.*
           FROM sessions s
           JOIN users u ON u.id = s.user_id
          WHERE s.token_hash = ? AND s.expires_at > ?`,
      )
      .bind(tokenHash, now),
  );
}

export async function deleteSession(db: D1Database, tokenHash: string): Promise<void> {
  await db.prepare('DELETE FROM sessions WHERE token_hash = ?').bind(tokenHash).run();
}

export async function deleteExpiredSessions(db: D1Database, now: number = nowSeconds()): Promise<void> {
  await db.prepare('DELETE FROM sessions WHERE expires_at <= ?').bind(now).run();
}
