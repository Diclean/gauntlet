/**
 * Pure points, bonus, streak and ranking rules. No I/O.
 *
 * Every award becomes a row in point_events; nothing here mutates a counter.
 */

export const DIFFICULTY_POINTS = {
  easy: 10,
  medium: 25,
  hard: 50,
} as const;

export type Difficulty = keyof typeof DIFFICULTY_POINTS;

export const FIRST_FINISH_BONUS = 10;
export const WEEKLY_WINNER_BONUS = 50;
export const STREAK_POINTS_PER_WEEK = 5;
export const STREAK_MAX_WEEKS = 10;

export function pointsForDifficulty(difficulty: Difficulty): number {
  return DIFFICULTY_POINTS[difficulty];
}

export interface AcceptedSubmissionRef {
  id: string;
  userId: string;
  challengeId: string;
  /** Unix seconds at which the submission became accepted. */
  decidedAt: number;
  createdAt: number;
  points: number;
}

/**
 * First-to-finish: the accepted submission with the earliest decided_at wins.
 * created_at and id are deterministic tie-breakers (votes are serialized in
 * practice, but the pure function stays total).
 */
export function firstAcceptedSubmission(
  submissions: readonly AcceptedSubmissionRef[],
): AcceptedSubmissionRef | null {
  if (submissions.length === 0) return null;
  return [...submissions].sort(
    (a, b) =>
      a.decidedAt - b.decidedAt ||
      a.createdAt - b.createdAt ||
      a.id.localeCompare(b.id),
  )[0]!;
}

export function firstFinishBonus(
  submissionId: string,
  accepted: readonly AcceptedSubmissionRef[],
): number {
  return firstAcceptedSubmission(accepted)?.id === submissionId ? FIRST_FINISH_BONUS : 0;
}

export interface WinnerCandidate {
  userId: string;
  points: number;
}

/** Members with the most points this week; ties all win. No points => no winner. */
export function weeklyWinnerIds(candidates: readonly WinnerCandidate[]): string[] {
  const totals = new Map<string, number>();
  for (const candidate of candidates) {
    totals.set(candidate.userId, (totals.get(candidate.userId) ?? 0) + candidate.points);
  }
  if (totals.size === 0) return [];
  const max = Math.max(...totals.values());
  if (max <= 0) return [];
  return [...totals.entries()]
    .filter(([, points]) => points === max)
    .map(([userId]) => userId)
    .sort();
}

/** +5 per streak week from 2 through 10. */
export function streakBonus(streak: number): number {
  if (!Number.isFinite(streak) || streak < 2) return 0;
  return STREAK_POINTS_PER_WEEK * Math.min(Math.floor(streak), STREAK_MAX_WEEKS);
}

export interface WeekRef {
  id: string;
  startsAt: number;
}

/**
 * Consecutive weeks ending at currentWeekId in which the member had at least
 * one accepted submission. A missing/skipped week breaks the streak.
 */
export function computeStreaks(
  weeks: readonly WeekRef[],
  acceptedByWeek: ReadonlyMap<string, ReadonlySet<string>>,
  currentWeekId: string,
  memberIds: readonly string[],
): Map<string, number> {
  const sorted = [...weeks].sort((a, b) => a.startsAt - b.startsAt);
  const currentIndex = sorted.findIndex((week) => week.id === currentWeekId);
  const result = new Map<string, number>();
  for (const memberId of memberIds) result.set(memberId, 0);
  if (currentIndex < 0) return result;

  // Adjacent week rows must actually be ~7 days apart (DST makes 167-169h).
  const MIN_WEEK_GAP = 6.8 * 86_400;
  const MAX_WEEK_GAP = 7.2 * 86_400;

  for (const memberId of memberIds) {
    const current = acceptedByWeek.get(currentWeekId);
    if (!current?.has(memberId)) continue;

    let streak = 1;
    for (let index = currentIndex - 1; index >= 0; index -= 1) {
      const week = sorted[index]!;
      const newerWeek = sorted[index + 1]!;
      const gap = newerWeek.startsAt - week.startsAt;
      if (gap < MIN_WEEK_GAP || gap > MAX_WEEK_GAP) break;
      if (!acceptedByWeek.get(week.id)?.has(memberId)) break;
      streak += 1;
    }
    result.set(memberId, streak);
  }
  return result;
}

/**
 * Standard competition ranking: equal scores share a rank, then the next rank
 * skips (1, 1, 3). Stable for equal scores by the input order.
 */
export function rankByPoints<T extends { points: number }>(entries: readonly T[]): Array<T & { rank: number }> {
  const sorted = [...entries].sort((a, b) => b.points - a.points);
  let previousPoints: number | null = null;
  let previousRank = 0;
  return sorted.map((entry, index) => {
    const rank = entry.points === previousPoints ? previousRank : index + 1;
    previousPoints = entry.points;
    previousRank = rank;
    return { ...entry, rank };
  });
}
