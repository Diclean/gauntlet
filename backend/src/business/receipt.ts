import type { PointKind, ReceiptLineJson } from '../types';

/**
 * Full-time receipt (weekly recap) lines. Pure: the service loads the caller's
 * submissions, challenge points and bonus events for one week.
 *
 * One line per challenge the member submitted:
 *  - accepted  -> challenge points, normal line;
 *  - pending   -> 0, normal line (still waiting on VAR);
 *  - rejected/expired -> 0, struck, label suffixed " · VAR: NO GOAL".
 * Then one aggregated line per bonus kind (first_bonus, streak, weekly_winner).
 */

export interface ReceiptSubmissionInput {
  challengeId: string;
  challengeTitle: string;
  status: 'pending' | 'accepted' | 'rejected' | 'expired' | 'removed';
  /** Challenge points, awarded when the submission is accepted. */
  points: number;
}

export interface ReceiptBonusInput {
  kind: PointKind;
  points: number;
}

const BONUS_ORDER: readonly PointKind[] = [
  'first_bonus',
  'captain',
  'streak',
  'weekly_winner',
];

const BONUS_LABELS: Partial<Record<PointKind, string>> = {
  first_bonus: 'First to finish',
  captain: 'CAPTAIN ×2',
  streak: 'Streak bonus',
  weekly_winner: 'Weekly winner',
};

const STATUS_PRIORITY: Record<ReceiptSubmissionInput['status'], number> = {
  accepted: 3,
  pending: 2,
  rejected: 1,
  expired: 0,
  removed: 0,
};

function outcomeLine(submission: ReceiptSubmissionInput): ReceiptLineJson {
  if (submission.status === 'accepted') {
    return {
      label: submission.challengeTitle,
      points: submission.points,
      struck: false,
    };
  }
  if (submission.status === 'pending') {
    return { label: submission.challengeTitle, points: 0, struck: false };
  }
  return {
    label: `${submission.challengeTitle} · VAR: NO GOAL`,
    points: 0,
    struck: true,
  };
}

export function buildReceiptLines(
  submissions: readonly ReceiptSubmissionInput[],
  bonuses: readonly ReceiptBonusInput[],
): ReceiptLineJson[] {
  // One line per challenge, preserving first-submission order. A later
  // accepted attempt replaces an earlier rejected one; a pending resubmission
  // outranks the rejection it follows.
  const byChallenge = new Map<string, ReceiptSubmissionInput>();
  for (const submission of submissions) {
    const existing = byChallenge.get(submission.challengeId);
    if (
      !existing ||
      STATUS_PRIORITY[submission.status] > STATUS_PRIORITY[existing.status]
    ) {
      byChallenge.set(submission.challengeId, submission);
    }
  }

  const lines = [...byChallenge.values()].map(outcomeLine);

  const bonusTotals = new Map<PointKind, number>();
  for (const bonus of bonuses) {
    if (bonus.points === 0) continue;
    bonusTotals.set(bonus.kind, (bonusTotals.get(bonus.kind) ?? 0) + bonus.points);
  }
  for (const kind of BONUS_ORDER) {
    const points = bonusTotals.get(kind);
    const label = BONUS_LABELS[kind];
    if (!label || points === undefined || points === 0) continue;
    lines.push({ label, points, struck: false });
  }

  return lines;
}

/** Deterministic "man of the match": most points that week, ties by user id. */
export function pickManOfTheMatch(
  weekPoints: ReadonlyMap<string, number>,
  memberIds: readonly string[],
): string | null {
  let bestId: string | null = null;
  let best = 0;
  for (const memberId of memberIds) {
    const points = weekPoints.get(memberId) ?? 0;
    if (points > best || (points === best && points > 0 && bestId !== null && memberId < bestId)) {
      best = points;
      bestId = memberId;
    }
  }
  return best > 0 ? bestId : null;
}

/**
 * Wooden Spoon: fewest points among members present for the whole week.
 * Requires at least two candidates (a solo group has no spoon).
 */
export function pickWoodenSpoon(
  weekPoints: ReadonlyMap<string, number>,
  presentMemberIds: readonly string[],
): string | null {
  if (presentMemberIds.length < 2) return null;
  let worstId: string | null = null;
  let worst = Number.POSITIVE_INFINITY;
  for (const memberId of presentMemberIds) {
    const points = weekPoints.get(memberId) ?? 0;
    if (points < worst || (points === worst && worstId !== null && memberId < worstId)) {
      worst = points;
      worstId = memberId;
    }
  }
  return worstId;
}

export interface RankSnapshot {
  rank: number;
  total: number;
}

/**
 * Competition ranking for total points. Equal totals share a rank; ties are
 * broken by user id only for stable iteration, never for the rank number.
 */
export function rankTotals(totals: ReadonlyMap<string, number>): Map<string, RankSnapshot> {
  const sorted = [...totals.entries()].sort(
    (a, b) => b[1] - a[1] || a[0].localeCompare(b[0]),
  );
  const result = new Map<string, RankSnapshot>();
  let previousPoints: number | null = null;
  let previousRank = 0;
  sorted.forEach(([userId, points], index) => {
    const rank = points === previousPoints ? previousRank : index + 1;
    result.set(userId, { rank, total: points });
    previousPoints = points;
    previousRank = rank;
  });
  return result;
}
