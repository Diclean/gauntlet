import type { ErrorHandler, NotFoundHandler } from 'hono';
import type { ContentfulStatusCode } from 'hono/utils/http-status';
import type { AppEnv } from '../types';

/**
 * An error that is safe to expose to the client. Anything else becomes a
 * generic 500 so internal details and data never leak.
 */
export class ApiError extends Error {
  readonly status: ContentfulStatusCode;
  readonly code: string;
  readonly headers: Record<string, string>;

  constructor(
    status: ContentfulStatusCode,
    code: string,
    message: string,
    headers: Record<string, string> = {},
  ) {
    super(message);
    this.name = 'ApiError';
    this.status = status;
    this.code = code;
    this.headers = headers;
  }
}

export function badRequest(code: string, message: string): ApiError {
  return new ApiError(400, code, message);
}

export function unauthorized(message = 'Missing or invalid session token'): ApiError {
  return new ApiError(401, 'unauthorized', message);
}

export function forbidden(message = 'You do not have access to this resource'): ApiError {
  return new ApiError(403, 'forbidden', message);
}

export function notFound(message = 'Not found'): ApiError {
  return new ApiError(404, 'not_found', message);
}

export function conflict(code: string, message: string): ApiError {
  return new ApiError(409, code, message);
}

export function payloadTooLarge(message = 'File is too large'): ApiError {
  return new ApiError(413, 'payload_too_large', message);
}

export function unprocessable(code: string, message: string): ApiError {
  return new ApiError(422, code, message);
}

export function tooManyRequests(message = 'Too many requests', retryAfterSeconds = 60): ApiError {
  return new ApiError(429, 'rate_limited', message, {
    'Retry-After': String(Math.max(1, Math.ceil(retryAfterSeconds))),
  });
}

function jsonError(c: Parameters<ErrorHandler<AppEnv>>[1], status: ContentfulStatusCode, code: string, message: string, headers: Record<string, string> = {}): Response {
  const response = c.json({ error: { code, message } }, status);
  for (const [key, value] of Object.entries(headers)) response.headers.set(key, value);
  return response;
}

export const errorHandler: ErrorHandler<AppEnv> = (err, c) => {
  if (err instanceof ApiError) {
    return jsonError(c, err.status, err.code, err.message, err.headers);
  }

  // Hono's HTTPException (e.g. malformed request) is also client-safe.
  const maybeHttp = err as { getResponse?: () => Response };
  if (typeof maybeHttp.getResponse === 'function') {
    const response = maybeHttp.getResponse();
    const status = response.status as ContentfulStatusCode;
    return jsonError(c, status, status >= 500 ? 'internal_error' : 'bad_request', status >= 500 ? 'Internal server error' : 'Bad request');
  }

  // No PII in logs: only the error class + message, never headers/bodies.
  console.error('unhandled_error', {
    name: err?.name ?? 'Error',
    message: err?.message ?? 'unknown',
  });
  return jsonError(c, 500, 'internal_error', 'Internal server error');
};

export const notFoundHandler: NotFoundHandler<AppEnv> = (c) =>
  jsonError(c, 404, 'not_found', 'Route not found');
