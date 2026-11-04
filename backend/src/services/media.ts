import type { Env } from '../types';
import { chunk } from '../lib/db';

/**
 * The single R2 deletion path for proof media.
 *
 * Every submission lifecycle transition that makes a proof invisible or
 * unreachable (rejected, expired, removed, deleted, account/group deletion)
 * funnels through here, after the D1 change has committed. Deletion is
 * best-effort: a transient R2 failure must never roll back or fail the DB
 * transition, and orphaned keys are harmless (private bucket, no reader path).
 */
export async function deleteMediaKeys(
  env: Env,
  keys: string | readonly string[] | null | undefined,
): Promise<void> {
  if (!keys) return;
  const unique = [...new Set((typeof keys === 'string' ? [keys] : keys).filter(Boolean))];
  for (const group of chunk(unique, 100)) {
    if (group.length === 0) continue;
    try {
      await env.MEDIA.delete(group);
    } catch {
      console.error('media_delete_failed', { count: group.length });
    }
  }
}

/** Convenience for a single submission. */
export async function deleteSubmissionMedia(env: Env, mediaKey: string): Promise<void> {
  await deleteMediaKeys(env, mediaKey);
}
