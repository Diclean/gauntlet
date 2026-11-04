import type { AwardKey, PlayerOfTheMonthStats } from '../types';

/**
 * Monthly "Awards night" rules. Pure: the service feeds this module the month's
 * aggregates and all-time rank snapshots; it decides winners and nominees.
 *
 * Rules (SPEC §5):
 *  - ties => every tied member wins;
 *  - a member with 0 relevant activity cannot win, except Wooden Spoon;
 *  - nominees are the top 3 by that award's metric.
 */

export const CEREMONY_ORDER: readonly AwardKey[] = [
  'wooden_spoon',
  'comeback_kid',
  'toughest_ref',
  'first_to_score',
  'golden_boot',
  'player_of_the_month',
];

export const PLAYER_OF_THE_MONTH_BONUS = 50;

export interface AwardMetricInput {
  month: string;
  /** All current group members (winners/nominees are drawn from this list). */
  memberIds: readonly string[];
  /** Current members whose joined_at is at or before the first second of the month. */
  presentAllMonth: ReadonlySet<string>;
  /** Points earned from challenge/first_bonus/weekly_winner/streak events in the month. */
  points: ReadonlyMap<string, number>;
  acceptedSubmissions: ReadonlyMap<string, number>;
  /** `status = 'rejected'` submissions by the member, in that month. */
  rejectedSubmissions: ReadonlyMap<string, number>;
  /** `approve = 0` votes cast by the member, on that month's submissions. */
  rejectionVotes: ReadonlyMap<string, number>;
  firstBonuses: ReadonlyMap<string, number>;
  /**
   * Points earned per member per week, for weeks starting in the month.
   * The month's own `monthly_award` bonus is excluded.
   */
  pointsByWeek: ReadonlyMap<string, ReadonlyMap<string, number>>;
  /** All-time competition rank at the start of the month (1 = leader). */
  rankAtStart: ReadonlyMap<string, number>;
  /** All-time competition rank after the month's weeks. */
  rankAtEnd: ReadonlyMap<string, number>;
}

export interface AwardWinner {
  userId: string;
  value: number;
}

export interface MonthlyAward {
  award: AwardKey;
  winners: AwardWinner[];
  nominees: AwardWinner[];
}

interface RankedByMetric {
  winners: AwardWinner[];
  nominees: AwardWinner[];
}

function valueFor(map: ReadonlyMap<string, number>, userId: string): number {
  return map.get(userId) ?? 0;
}

/**
 * Most/fewest by a metric. `direction: 'max'` requires a positive value to
 * award (0 activity can't win); `'min'` (Wooden Spoon) accepts 0.
 */
function rankByMetric(
  memberIds: readonly string[],
  values: ReadonlyMap<string, number>,
  direction: 'max' | 'min',
  allowZeroWinner: boolean,
  limit = 3,
): RankedByMetric {
  const entries = memberIds.map((userId) => ({ userId, value: valueFor(values, userId) }));
  if (entries.length === 0) return { winners: [], nominees: [] };

  const sorted = [...entries].sort((a, b) => {
    const byValue = direction === 'max' ? b.value - a.value : a.value - b.value;
    return byValue || a.userId.localeCompare(b.userId);
  });

  const best = sorted[0]!.value;
  const winners = sorted.filter(
    (entry) => entry.value === best && (allowZeroWinner || entry.value > 0),
  );

  // For "most" awards, zero-activity members are not contenders. Wooden Spoon
  // intentionally lists everyone, including 0-point members.
  const nominees = sorted
    .filter((entry) => allowZeroWinner || entry.value > 0)
    .slice(0, limit);

  return { winners, nominees };
}

function comebackAward(input: AwardMetricInput): RankedByMetric {
  const deltas = new Map<string, number>();
  for (const memberId of input.memberIds) {
    const start = input.rankAtStart.get(memberId);
    const end = input.rankAtEnd.get(memberId);
    if (start === undefined || end === undefined) continue;
    deltas.set(memberId, start - end);
  }

  const ranked = rankByMetric(input.memberIds, deltas, 'max', false);
  return {
    winners: ranked.winners.filter((winner) => winner.value >= 1),
    nominees: ranked.nominees.filter((nominee) => nominee.value >= 1),
  };
}

/**
 * Computes every award for one month. Awards with no eligible winner are
 * omitted (an empty month produces an empty list).
 */
export function computeMonthlyAwards(input: AwardMetricInput): MonthlyAward[] {
  const results = new Map<AwardKey, RankedByMetric>();

  results.set(
    'wooden_spoon',
    rankByMetric([...input.presentAllMonth], input.points, 'min', true),
  );
  results.set('comeback_kid', comebackAward(input));
  results.set(
    'toughest_ref',
    rankByMetric(input.memberIds, input.rejectionVotes, 'max', false),
  );
  results.set('first_to_score', rankByMetric(input.memberIds, input.firstBonuses, 'max', false));
  results.set(
    'golden_boot',
    rankByMetric(input.memberIds, input.acceptedSubmissions, 'max', false),
  );
  results.set(
    'player_of_the_month',
    rankByMetric(input.memberIds, input.points, 'max', false),
  );

  const awards: MonthlyAward[] = [];
  for (const award of CEREMONY_ORDER) {
    const ranked = results.get(award);
    if (!ranked || ranked.winners.length === 0) continue;
    awards.push({ award, winners: ranked.winners, nominees: ranked.nominees });
  }
  return awards;
}

/** Ceremony order helper for SQL/read paths that return rows out of order. */
export function awardOrder(award: AwardKey): number {
  const index = CEREMONY_ORDER.indexOf(award);
  return index < 0 ? CEREMONY_ORDER.length : index;
}

/**
 * The Player of the Month pennant stats: the month's points, accepted
 * submissions (goals), rejected submissions (red cards), first-to-score
 * bonuses, and the best single week's points. Pure: the service supplies the
 * month's aggregates.
 */
export function playerOfTheMonthStats(
  input: AwardMetricInput,
  userId: string,
): PlayerOfTheMonthStats {
  let bestWeek = 0;
  const weeks = input.pointsByWeek.get(userId);
  if (weeks) {
    for (const points of weeks.values()) {
      if (points > bestWeek) bestWeek = points;
    }
  }

  return {
    points: valueFor(input.points, userId),
    goals: valueFor(input.acceptedSubmissions, userId),
    redCards: valueFor(input.rejectedSubmissions, userId),
    firstToScore: valueFor(input.firstBonuses, userId),
    bestWeek,
  };
}
