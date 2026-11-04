import type { Context } from 'hono';
import { z } from 'zod';
import type { AppEnv } from '../types';
import { ApiError, badRequest, payloadTooLarge } from '../lib/errors';

/** Every JSON body is tiny (an invite code, a vote, a comment); cap it hard. */
export const MAX_JSON_BODY_BYTES = 64 * 1024;

/**
 * Reads the request body as UTF-8 text while enforcing a byte cap, so a
 * streaming/lying Content-Length cannot force an unbounded allocation before
 * JSON.parse runs.
 */
async function readBodyTextWithCap(c: Context<AppEnv>, maxBytes: number): Promise<string> {
  const body = c.req.raw.body;
  if (!body) return '';

  const reader = body.getReader();
  const chunks: Uint8Array[] = [];
  let total = 0;
  try {
    for (;;) {
      const { done, value } = await reader.read();
      if (done) break;
      if (!value) continue;
      total += value.byteLength;
      if (total > maxBytes) {
        await reader.cancel().catch(() => undefined);
        throw payloadTooLarge('Request body is too large');
      }
      chunks.push(value);
    }
  } finally {
    reader.releaseLock();
  }

  const bytes = new Uint8Array(total);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.byteLength;
  }
  return new TextDecoder().decode(bytes);
}

/** The client sees field paths + validation messages, never the submitted values. */
export function formatZodError(error: z.ZodError): string {
  const issues = error.issues.slice(0, 3).map((issue) => {
    const path = issue.path.length > 0 ? issue.path.join('.') : 'body';
    return `${path}: ${issue.message}`;
  });
  return issues.join('; ') || 'Invalid request body';
}

/**
 * Parses a JSON body against a schema. All request schemas are `.strict()`, so
 * unknown fields are rejected with a 400.
 */
export async function parseJsonBody<T>(c: Context<AppEnv>, schema: z.ZodType<T>): Promise<T> {
  // A declared, numeric Content-Length above the cap is rejected before any
  // body bytes are read. Missing/non-numeric lengths fall through to the
  // streaming byte cap below.
  const declared = c.req.header('content-length');
  if (declared !== undefined && /^\d+$/u.test(declared) && Number(declared) > MAX_JSON_BODY_BYTES) {
    throw payloadTooLarge('Request body is too large');
  }

  let body: unknown;
  try {
    const text = await readBodyTextWithCap(c, MAX_JSON_BODY_BYTES);
    body = JSON.parse(text);
  } catch (error) {
    if (error instanceof ApiError) throw error;
    throw badRequest('invalid_json', 'Request body must be valid JSON');
  }
  const parsed = schema.safeParse(body);
  if (!parsed.success) throw badRequest('validation_error', formatZodError(parsed.error));
  return parsed.data;
}

export function parseWithSchema<T>(schema: z.ZodType<T>, value: unknown, code = 'validation_error'): T {
  const parsed = schema.safeParse(value);
  if (!parsed.success) throw badRequest(code, formatZodError(parsed.error));
  return parsed.data;
}
