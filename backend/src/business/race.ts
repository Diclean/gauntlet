import type { PublicUser, RaceJson, RaceSeriesJson, RaceWeekJson } from '../types';

/**
 * Title-race curve math. Pure: the service loads weeks, members and the points
 * ledger; this module only shapes the cumulative/per-week arrays.
 *
 * Everyone's arrays are aligned with `weeks` (oldest first). A member who
 * joined later simply has 0 for the weeks before their first point event.
 */

export interface RaceWeekInput {
  id: string;
  number: number;
  startsAt: number;
}

export interface RaceMemberInput {
  user: PublicUser;
  joinedAt: number;
}

export interface RacePointEvent {
  weekId: string;
  userId: string;
  points: number;
}

export interface RaceSeries {
  user: PublicUser;
  cumulative: number[];
  perWeek: number[];
}

export interface RaceResult {
  weeks: RaceWeekJson[];
  series: RaceSeries[];
}

export function buildRaceSeries(
  weeksInput: readonly RaceWeekInput[],
  members: readonly RaceMemberInput[],
  events: readonly RacePointEvent[],
): RaceResult {
  const weeks = [...weeksInput].sort((a, b) => a.startsAt - b.startsAt);
  const weekIndex = new Map(weeks.map((week, index) => [week.id, index]));

  const perWeekByUser = new Map<string, number[]>();
  for (const member of members) {
    perWeekByUser.set(member.user.id, Array.from({ length: weeks.length }, () => 0));
  }

  for (const event of events) {
    const index = weekIndex.get(event.weekId);
    if (index === undefined) continue;
    const perWeek = perWeekByUser.get(event.userId);
    if (!perWeek) continue;
    perWeek[index] = (perWeek[index] ?? 0) + event.points;
  }

  const series: RaceSeries[] = members.map((member) => {
    const perWeek = perWeekByUser.get(member.user.id) ?? [];
    const cumulative: number[] = [];
    let running = 0;
    for (const points of perWeek) {
      running += points;
      cumulative.push(running);
    }
    return { user: member.user, cumulative, perWeek };
  });

  // Highest total first; stable by user id for deterministic API output.
  series.sort((a, b) => {
    const totalA = a.cumulative.at(-1) ?? 0;
    const totalB = b.cumulative.at(-1) ?? 0;
    return totalB - totalA || a.user.id.localeCompare(b.user.id);
  });

  return {
    weeks: weeks.map((week) => ({
      id: week.id,
      number: week.number,
      startsAt: week.startsAt,
    })),
    series,
  };
}

export interface RaceMe {
  bestWeek: { number: number; points: number };
  avgPerWeek: number;
  streak: number;
}

/**
 * The caller's summary. `weeks` is the same ordered array used for the series,
 * so a late joiner's average includes the zero weeks before they joined (the
 * season is since group creation by spec).
 */
export function computeRaceMe(
  result: RaceResult,
  userId: string,
  streak: number,
): RaceMe {
  const mine = result.series.find((entry) => entry.user.id === userId);
  if (!mine || result.weeks.length === 0) {
    return { bestWeek: { number: 0, points: 0 }, avgPerWeek: 0, streak };
  }

  let bestIndex = 0;
  for (let index = 1; index < mine.perWeek.length; index += 1) {
    if ((mine.perWeek[index] ?? 0) > (mine.perWeek[bestIndex] ?? 0)) bestIndex = index;
  }

  const total = mine.cumulative.at(-1) ?? 0;
  return {
    bestWeek: {
      number: result.weeks[bestIndex]?.number ?? 0,
      points: mine.perWeek[bestIndex] ?? 0,
    },
    avgPerWeek: Math.round(total / result.weeks.length),
    streak,
  };
}

export function raceJson(result: RaceResult, me: RaceMe): RaceJson {
  const series: RaceSeriesJson[] = result.series.map((entry) => ({
    user: entry.user,
    cumulative: entry.cumulative,
    perWeek: entry.perWeek,
  }));
  return { weeks: result.weeks, series, me };
}
