import type { Context } from 'hono';
import { z } from 'zod';
import type { AppEnv } from '../types';
import { badRequest } from '../lib/errors';

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
  let body: unknown;
  try {
    body = await c.req.json();
  } catch {
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
