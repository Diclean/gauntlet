import { z } from 'zod';
import type { Env } from '../types';
import {
  base64UrlToBytes,
  base64UrlToUtf8,
  sha256Hex,
  timingSafeEqual,
} from '../lib/crypto';
import { unauthorized } from '../lib/errors';

/**
 * Sign in with Apple identity-token verification.
 *
 * Apple publishes RS256 signing keys at APPLE_JWKS_URL. We cache them in the
 * isolate for an hour and re-fetch once if an unknown `kid` appears (key
 * rotation). The signature is verified with WebCrypto; iss/aud/exp/iat and the
 * SHA-256 nonce binding are checked before any user is created.
 */

const APPLE_ISSUER = 'https://appleid.apple.com';
const DEFAULT_JWKS_URL = 'https://appleid.apple.com/auth/keys';
const JWKS_TTL_SECONDS = 60 * 60;
const CLOCK_SKEW_SECONDS = 60;

const headerSchema = z
  .object({
    alg: z.literal('RS256'),
    kid: z.string().min(1).max(128),
    typ: z.string().optional(),
  })
  .passthrough();

const claimsSchema = z
  .object({
    iss: z.string(),
    aud: z.union([z.string(), z.array(z.string())]),
    exp: z.number(),
    iat: z.number().optional(),
    sub: z.string().min(1).max(255),
    nonce: z.string().max(256).optional(),
    email: z.string().max(320).optional(),
    email_verified: z.union([z.boolean(), z.string()]).optional(),
  })
  .passthrough();

export type AppleClaims = z.infer<typeof claimsSchema>;

interface AppleJwk {
  kty: string;
  kid?: string;
  use?: string;
  alg?: string;
  n: string;
  e: string;
}

interface JwksCacheEntry {
  url: string;
  keys: AppleJwk[];
  fetchedAt: number;
}

let jwksCache: JwksCacheEntry | null = null;

/** Test helper: forget cached Apple keys. */
export function clearAppleJwksCache(): void {
  jwksCache = null;
}

async function fetchJwks(url: string, force: boolean): Promise<AppleJwk[]> {
  const now = Math.floor(Date.now() / 1000);
  if (!force && jwksCache && jwksCache.url === url && now - jwksCache.fetchedAt < JWKS_TTL_SECONDS) {
    return jwksCache.keys;
  }

  let response: Response;
  try {
    response = await fetch(url, { headers: { accept: 'application/json' } });
  } catch {
    throw unauthorized('Apple identity token could not be verified');
  }
  if (!response.ok) throw unauthorized('Apple identity token could not be verified');

  let body: unknown;
  try {
    body = await response.json();
  } catch {
    throw unauthorized('Apple identity token could not be verified');
  }

  const parsed = z
    .object({
      keys: z.array(
        z
          .object({
            kty: z.string(),
            kid: z.string().optional(),
            use: z.string().optional(),
            alg: z.string().optional(),
            n: z.string().min(1),
            e: z.string().min(1),
          })
          .passthrough(),
      ),
    })
    .passthrough()
    .safeParse(body);
  if (!parsed.success) throw unauthorized('Apple identity token could not be verified');

  jwksCache = { url, keys: parsed.data.keys, fetchedAt: now };
  return parsed.data.keys;
}

async function findSigningKey(url: string, kid: string): Promise<AppleJwk> {
  let keys = await fetchJwks(url, false);
  let key = keys.find((candidate) => candidate.kid === kid && candidate.kty === 'RSA');
  if (!key) {
    // Key rotation: bypass the TTL once.
    keys = await fetchJwks(url, true);
    key = keys.find((candidate) => candidate.kid === kid && candidate.kty === 'RSA');
  }
  if (!key) throw unauthorized('Apple identity token could not be verified');
  return key;
}

async function verifySignature(token: string, key: AppleJwk): Promise<boolean> {
  const [header, payload, signature] = token.split('.');
  if (!header || !payload || !signature) return false;
  try {
    const cryptoKey = await crypto.subtle.importKey(
      'jwk',
      { kty: 'RSA', n: key.n, e: key.e, alg: 'RS256', ext: true },
      { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
      false,
      ['verify'],
    );
    const data = new TextEncoder().encode(`${header}.${payload}`);
    return await crypto.subtle.verify(
      { name: 'RSASSA-PKCS1-v1_5' },
      cryptoKey,
      base64UrlToBytes(signature),
      data,
    );
  } catch {
    return false;
  }
}

export async function verifyAppleIdentityToken(
  env: Env,
  identityToken: string,
  rawNonce: string,
): Promise<AppleClaims> {
  const segments = identityToken.split('.');
  if (segments.length !== 3) throw unauthorized('Apple identity token is invalid');
  const [encodedHeader, encodedPayload, encodedSignature] = segments as [string, string, string];

  let header: unknown;
  let payload: unknown;
  try {
    header = JSON.parse(base64UrlToUtf8(encodedHeader));
    payload = JSON.parse(base64UrlToUtf8(encodedPayload));
  } catch {
    throw unauthorized('Apple identity token is invalid');
  }

  const parsedHeader = headerSchema.safeParse(header);
  const parsedClaims = claimsSchema.safeParse(payload);
  if (!parsedHeader.success || !parsedClaims.success) {
    throw unauthorized('Apple identity token is invalid');
  }

  const claims = parsedClaims.data;
  const now = Math.floor(Date.now() / 1000);

  if (claims.iss !== APPLE_ISSUER) throw unauthorized('Apple identity token is invalid');
  const audiences = Array.isArray(claims.aud) ? claims.aud : [claims.aud];
  if (!audiences.includes(env.APPLE_BUNDLE_ID)) {
    throw unauthorized('Apple identity token is invalid');
  }
  if (!Number.isFinite(claims.exp) || claims.exp <= now - CLOCK_SKEW_SECONDS) {
    throw unauthorized('Apple identity token has expired');
  }
  if (claims.iat !== undefined && claims.iat > now + CLOCK_SKEW_SECONDS) {
    throw unauthorized('Apple identity token is invalid');
  }

  // The client sends the raw nonce; Apple's token carries SHA-256(rawNonce), hex.
  const expectedNonce = await sha256Hex(rawNonce);
  const tokenNonce = claims.nonce?.trim().toLowerCase();
  if (!tokenNonce || !timingSafeEqual(tokenNonce, expectedNonce)) {
    throw unauthorized('Apple identity token nonce does not match');
  }

  const jwksUrl = env.APPLE_JWKS_URL || DEFAULT_JWKS_URL;
  const key = await findSigningKey(jwksUrl, parsedHeader.data.kid);
  const signatureValid = await verifySignature(
    `${encodedHeader}.${encodedPayload}.${encodedSignature}`,
    key,
  );
  if (!signatureValid) throw unauthorized('Apple identity token signature is invalid');

  // One-shot replay guard: burn sha256(rawNonce) only after the signature and
  // every claim check passed. Expiry follows the token's own exp, and the cron
  // purge removes rows once they can no longer be presented.
  const nonceHash = expectedNonce;
  const consumed = await env.DB.prepare(
    `INSERT INTO used_nonces (nonce_hash, expires_at, created_at) VALUES (?, ?, ?)
     ON CONFLICT(nonce_hash) DO NOTHING`,
  )
    .bind(nonceHash, claims.exp, now)
    .run();
  if ((consumed.meta.changes ?? 0) === 0) {
    throw unauthorized('Apple identity token nonce was already used');
  }

  return claims;
}
