import type {
  PublicUser,
  ReactionJson,
  SubmissionJson,
  SubmissionRow,
  WeekRow,
} from '../types';
import { toPublicUser } from '../types';
import { all, first } from '../lib/db';
import { badRequest, notFound } from '../lib/errors';
import { base64UrlToUtf8, utf8ToBase64Url } from '../lib/crypto';
import { loadCommentCounts, loadReactions } from './banter';

/** Submission joins, serialization, vote counts and cursor pagination. */

export interface SubmissionContext {
  submission: SubmissionRow;
  challengeId: string;
  challengeTitle: string;
  challengePoints: number;
  groupId: string;
  week: WeekRow;
}

interface SubmissionContextRow extends SubmissionRow {
  challenge_title: string;
  challenge_points: number;
  group_id: string;
  week_id: string;
  week_starts_at: number;
  week_ends_at: number;
  week_vote_deadline: number;
  week_status: 'open' | 'closed';
  week_reminder_sent: number;
  week_number: number;
}

const CONTEXT_SELECT = `
  SELECT s.*, c.title AS challenge_title, c.points AS challenge_points,
         w.id AS week_id, w.group_id AS group_id, w.starts_at AS week_starts_at,
         w.ends_at AS week_ends_at, w.vote_deadline AS week_vote_deadline,
         w.status AS week_status, w.reminder_sent AS week_reminder_sent,
         w.number AS week_number
    FROM submissions s
    JOIN challenges c ON c.id = s.challenge_id
    JOIN weeks w ON w.id = c.week_id
`;

export async function loadSubmissionContext(
  db: D1Database,
  submissionId: string,
): Promise<SubmissionContext | null> {
  const row = await first<SubmissionContextRow>(
    db.prepare(`${CONTEXT_SELECT} WHERE s.id = ?`).bind(submissionId),
  );
  if (!row) return null;
  return {
    submission: {
      id: row.id,
      challenge_id: row.challenge_id,
      user_id: row.user_id,
      media_key: row.media_key,
      media_type: row.media_type,
      caption: row.caption,
      status: row.status,
      eligible_voters: row.eligible_voters,
      created_at: row.created_at,
      decided_at: row.decided_at,
    },
    challengeId: row.challenge_id,
    challengeTitle: row.challenge_title,
    challengePoints: row.challenge_points,
    groupId: row.group_id,
    week: {
      id: row.week_id,
      group_id: row.group_id,
      starts_at: row.week_starts_at,
      ends_at: row.week_ends_at,
      vote_deadline: row.week_vote_deadline,
      status: row.week_status,
      reminder_sent: row.week_reminder_sent,
      number: row.week_number,
    },
  };
}

interface SubmissionViewRow extends SubmissionRow {
  challenge_title: string;
  display_name: string;
  avatar_emoji: string | null;
  approvals: number;
  rejections: number;
  my_vote: number | null;
}

const VIEW_SELECT = `
  SELECT s.*, c.title AS challenge_title, u.display_name, u.avatar_emoji,
         (SELECT COUNT(*) FROM votes v WHERE v.submission_id = s.id AND v.approve = 1) AS approvals,
         (SELECT COUNT(*) FROM votes v WHERE v.submission_id = s.id AND v.approve = 0) AS rejections,
         (SELECT v.approve FROM votes v WHERE v.submission_id = s.id AND v.voter_id = ?) AS my_vote
    FROM submissions s
    JOIN challenges c ON c.id = s.challenge_id
    JOIN users u ON u.id = s.user_id
`;

/**
 * The tally stays hidden until the viewer has called it: voters are exposed only
 * when the submission is decided (accepted/rejected) or the viewer already voted.
 * Otherwise the array is empty, even if other members have voted.
 */
function votersAreVisible(row: SubmissionViewRow): boolean {
  if (row.status === 'accepted' || row.status === 'rejected') return true;
  return row.my_vote !== null && row.my_vote !== undefined;
}

export function submissionToJson(
  row: SubmissionViewRow,
  voters: readonly PublicUser[] = [],
  reactions: readonly ReactionJson[] = [],
  commentCount = 0,
): SubmissionJson {
  return {
    id: row.id,
    challengeId: row.challenge_id,
    challengeTitle: row.challenge_title,
    user: toPublicUser({
      id: row.user_id,
      apple_sub: '',
      display_name: row.display_name,
      avatar_emoji: row.avatar_emoji,
      created_at: 0,
      terms_accepted_at: null,
    }),
    mediaUrl: `/media/${row.media_key}`,
    mediaType: row.media_type,
    caption: row.caption,
    status: row.status,
    approvals: row.approvals,
    rejections: row.rejections,
    eligibleVoters: row.eligible_voters,
    myVote: row.my_vote === null || row.my_vote === undefined ? null : Boolean(row.my_vote),
    createdAt: row.created_at,
    decidedAt: row.decided_at,
    voters: votersAreVisible(row) ? [...voters] : [],
    reactions: [...reactions],
    commentCount,
  };
}

interface SubmissionVoterRow {
  submission_id: string;
  id: string;
  display_name: string;
  avatar_emoji: string | null;
}

/**
 * All voters for a batch of submissions, grouped by submission id, in vote
 * order. One query per page/list keeps the feed and pending-votes paths cheap.
 */
async function loadSubmissionVoters(
  db: D1Database,
  submissionIds: readonly string[],
): Promise<Map<string, PublicUser[]>> {
  const ids = [...new Set(submissionIds)];
  if (ids.length === 0) return new Map();

  const bySubmission = new Map<string, PublicUser[]>();
  // Keep each IN (...) under D1's bound-parameter limit on large pending lists.
  const CHUNK_SIZE = 50;
  for (let offset = 0; offset < ids.length; offset += CHUNK_SIZE) {
    const chunk = ids.slice(offset, offset + CHUNK_SIZE);
    const placeholders = chunk.map(() => '?').join(', ');
    const rows = await all<SubmissionVoterRow>(
      db
        .prepare(
          `SELECT v.submission_id, u.id, u.display_name, u.avatar_emoji
             FROM votes v
             JOIN users u ON u.id = v.voter_id
            WHERE v.submission_id IN (${placeholders})
            ORDER BY v.created_at ASC, u.id ASC`,
        )
        .bind(...chunk),
    );

    for (const row of rows) {
      const user = toPublicUser({
        id: row.id,
        apple_sub: '',
        display_name: row.display_name,
        avatar_emoji: row.avatar_emoji,
        created_at: 0,
        terms_accepted_at: null,
      });
      const list = bySubmission.get(row.submission_id);
      if (list) list.push(user);
      else bySubmission.set(row.submission_id, [user]);
    }
  }
  return bySubmission;
}

export async function loadSubmissionView(
  db: D1Database,
  submissionId: string,
  viewerId: string,
): Promise<SubmissionJson | null> {
  const row = await first<SubmissionViewRow>(
    db.prepare(`${VIEW_SELECT} WHERE s.id = ?`).bind(viewerId, submissionId),
  );
  if (!row) return null;
  const [voters, reactions, commentCounts] = await Promise.all([
    loadSubmissionVoters(db, [row.id]),
    loadReactions(db, [row.id], viewerId),
    loadCommentCounts(db, [row.id], viewerId),
  ]);
  return submissionToJson(
    row,
    voters.get(row.id) ?? [],
    reactions.get(row.id) ?? [],
    commentCounts.get(row.id) ?? 0,
  );
}

/** Batched enrichment for feed / pending lists. */
async function viewsToJson(
  db: D1Database,
  rows: readonly SubmissionViewRow[],
  viewerId: string,
): Promise<SubmissionJson[]> {
  const ids = rows.map((row) => row.id);
  const [voters, reactions, commentCounts] = await Promise.all([
    loadSubmissionVoters(db, ids),
    loadReactions(db, ids, viewerId),
    loadCommentCounts(db, ids, viewerId),
  ]);
  return rows.map((row) =>
    submissionToJson(
      row,
      voters.get(row.id) ?? [],
      reactions.get(row.id) ?? [],
      commentCounts.get(row.id) ?? 0,
    ),
  );
}

export async function requireSubmissionView(
  db: D1Database,
  submissionId: string,
  viewerId: string,
): Promise<SubmissionJson> {
  const submission = await loadSubmissionView(db, submissionId, viewerId);
  if (!submission) throw notFound('Submission not found');
  return submission;
}

export interface VoteCountsRow {
  approvals: number;
  rejections: number;
}

export async function loadVoteCounts(db: D1Database, submissionId: string): Promise<VoteCountsRow> {
  const row = await first<{ approvals: number; rejections: number }>(
    db
      .prepare(
        `SELECT
           COALESCE(SUM(CASE WHEN approve = 1 THEN 1 ELSE 0 END), 0) AS approvals,
           COALESCE(SUM(CASE WHEN approve = 0 THEN 1 ELSE 0 END), 0) AS rejections
         FROM votes WHERE submission_id = ?`,
      )
      .bind(submissionId),
  );
  return { approvals: row?.approvals ?? 0, rejections: row?.rejections ?? 0 };
}

export interface FeedCursor {
  createdAt: number;
  id: string;
}

export function encodeCursor(cursor: FeedCursor): string {
  return utf8ToBase64Url(JSON.stringify({ t: cursor.createdAt, i: cursor.id }));
}

export function decodeCursor(value: string): FeedCursor {
  try {
    const parsed: unknown = JSON.parse(base64UrlToUtf8(value));
    if (
      !parsed ||
      typeof parsed !== 'object' ||
      typeof (parsed as { t?: unknown }).t !== 'number' ||
      typeof (parsed as { i?: unknown }).i !== 'string'
    ) {
      throw new Error('shape');
    }
    return { createdAt: (parsed as { t: number }).t, id: (parsed as { i: string }).i };
  } catch {
    throw badRequest('invalid_cursor', 'Feed cursor is invalid');
  }
}

export interface FeedPage {
  items: SubmissionJson[];
  nextCursor: string | null;
}

const FEED_LIMIT = 20;

/**
 * Pending submissions in a group that the viewer still has to judge: not their
 * own, no vote from them yet, and from a week whose vote deadline has not
 * passed (a closed week during the grace period is still votable). Oldest first
 * so the longest-waiting proof is surfaced first.
 */
export async function listPendingVotes(
  db: D1Database,
  groupId: string,
  viewerId: string,
  now: number,
): Promise<SubmissionJson[]> {
  const rows = await all<SubmissionViewRow>(
    db
      .prepare(
        `${VIEW_SELECT}
           JOIN weeks w ON w.id = c.week_id
          WHERE w.group_id = ?
            AND s.status = 'pending'
            AND s.user_id <> ?
            AND w.vote_deadline >= ?
            AND NOT EXISTS (
              SELECT 1 FROM votes v
               WHERE v.submission_id = s.id AND v.voter_id = ?
            )
            AND NOT EXISTS (
              SELECT 1 FROM blocks b
               WHERE b.blocker_id = ? AND b.blocked_id = s.user_id
            )
            AND NOT EXISTS (
              SELECT 1 FROM reports r
               WHERE r.reporter_id = ? AND r.target_type = 'submission'
                 AND r.target_id = s.id
            )
          ORDER BY s.created_at ASC, s.id ASC`,
      )
      .bind(viewerId, groupId, viewerId, now, viewerId, viewerId, viewerId),
  );
  return await viewsToJson(db, rows, viewerId);
}

export async function listFeed(
  db: D1Database,
  groupId: string,
  viewerId: string,
  cursor: FeedCursor | null,
): Promise<FeedPage> {
  const conditions = [
    'w.group_id = ?',
    "(s.status <> 'removed' OR s.user_id = ?)",
    `NOT EXISTS (
       SELECT 1 FROM blocks b
        WHERE b.blocker_id = ? AND b.blocked_id = s.user_id
     )`,
    `NOT EXISTS (
       SELECT 1 FROM reports r
        WHERE r.reporter_id = ? AND r.target_type = 'submission'
          AND r.target_id = s.id
     )`,
  ];
  const bindings: unknown[] = [groupId, viewerId, viewerId, viewerId];
  if (cursor) {
    conditions.push('(s.created_at < ? OR (s.created_at = ? AND s.id < ?))');
    bindings.push(cursor.createdAt, cursor.createdAt, cursor.id);
  }

  const rows = await all<SubmissionViewRow>(
    db
      .prepare(
        `${VIEW_SELECT}
           JOIN weeks w ON w.id = c.week_id
          WHERE ${conditions.join(' AND ')}
          ORDER BY s.created_at DESC, s.id DESC
          LIMIT ${FEED_LIMIT + 1}`,
      )
      .bind(viewerId, ...bindings),
  );

  const hasMore = rows.length > FEED_LIMIT;
  const page = hasMore ? rows.slice(0, FEED_LIMIT) : rows;
  const last = page[page.length - 1];
  return {
    items: await viewsToJson(db, page, viewerId),
    nextCursor: hasMore && last ? encodeCursor({ createdAt: last.created_at, id: last.id }) : null,
  };
}
