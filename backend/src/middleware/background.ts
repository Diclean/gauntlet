import type { Context } from 'hono';
import type { AppEnv } from '../types';

/**
 * Queues work on the Worker's waitUntil if available. Push is best-effort and
 * must never fail or delay an API response.
 */
export function runInBackground(c: Context<AppEnv>, task: Promise<unknown>): void {
  const guarded = task.catch((error: unknown) => {
    const name = error instanceof Error ? error.name : 'Error';
    console.error('background_task_failed', { name });
  });
  try {
    c.executionCtx.waitUntil(guarded);
  } catch {
    // Unit tests / environments without an ExecutionContext: just let it run.
    void guarded;
  }
}
