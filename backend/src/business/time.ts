/**
 * Pure week-boundary math in a group's IANA timezone. No DB, no clock.
 *
 * A week is Monday 00:00:00 through Sunday 23:59:59 local time. `endsAt` is
 * the last second of Sunday (next Monday 00:00 minus 1s). Votes stay open for
 * 12 hours after the week ends (`voteDeadline` = next Monday 00:00 + 12h).
 *
 * All conversions go through Intl.DateTimeFormat, which is DST-aware, instead
 * of relying on the host process timezone.
 */

export const DAY_SECONDS = 86_400;
export const VOTE_GRACE_SECONDS = 12 * 60 * 60;

export interface LocalParts {
  year: number;
  month: number;
  day: number;
  hour: number;
  minute: number;
  second: number;
  /** 0 = Sunday ... 6 = Saturday (same as Date#getUTCDay). */
  weekday: number;
}

export interface WeekBounds {
  startsAt: number;
  endsAt: number;
  voteDeadline: number;
}

const WEEKDAY_INDEX: Record<string, number> = {
  Sun: 0,
  Mon: 1,
  Tue: 2,
  Wed: 3,
  Thu: 4,
  Fri: 5,
  Sat: 6,
};

const formatterCache = new Map<string, Intl.DateTimeFormat>();

function formatterFor(timeZone: string): Intl.DateTimeFormat {
  const cached = formatterCache.get(timeZone);
  if (cached) return cached;
  const formatter = new Intl.DateTimeFormat('en-US', {
    timeZone,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
    hourCycle: 'h23',
    weekday: 'short',
  });
  formatterCache.set(timeZone, formatter);
  return formatter;
}

export function isValidTimeZone(timeZone: string): boolean {
  if (!timeZone || timeZone.length > 64) return false;
  try {
    formatterFor(timeZone).format(new Date(0));
    return true;
  } catch {
    formatterCache.delete(timeZone);
    return false;
  }
}

export function getLocalParts(instant: Date | number, timeZone: string): LocalParts {
  const date = typeof instant === 'number' ? new Date(instant * 1000) : instant;
  const parts = formatterFor(timeZone).formatToParts(date);
  let year = 1970;
  let month = 1;
  let day = 1;
  let hour = 0;
  let minute = 0;
  let second = 0;
  let weekday = 0;
  for (const part of parts) {
    switch (part.type) {
      case 'year':
        year = Number(part.value);
        break;
      case 'month':
        month = Number(part.value);
        break;
      case 'day':
        day = Number(part.value);
        break;
      case 'hour':
        hour = Number(part.value) % 24;
        break;
      case 'minute':
        minute = Number(part.value);
        break;
      case 'second':
        second = Number(part.value);
        break;
      case 'weekday':
        weekday = WEEKDAY_INDEX[part.value] ?? 0;
        break;
      default:
        break;
    }
  }
  return { year, month, day, hour, minute, second, weekday };
}

/**
 * Convert a wall-clock local time to Unix seconds. Iterates the IANA offset
 * (twice normally, more around DST transitions).
 */
export function zonedTimeToUnix(
  year: number,
  month: number,
  day: number,
  hour: number,
  minute: number,
  second: number,
  timeZone: string,
): number {
  const target = Date.UTC(year, month - 1, day, hour, minute, second);
  let guess = target;
  for (let i = 0; i < 5; i += 1) {
    const local = getLocalParts(new Date(guess), timeZone);
    const asUtc = Date.UTC(
      local.year,
      local.month - 1,
      local.day,
      local.hour,
      local.minute,
      local.second,
    );
    const offset = asUtc - guess;
    const candidate = target - offset;
    if (candidate === guess) break;
    guess = candidate;
  }
  return Math.floor(guess / 1000);
}

/** Unix seconds of Monday 00:00 local for the week containing `instant`. */
export function startOfLocalWeek(instant: number, timeZone: string): number {
  const local = getLocalParts(instant, timeZone);
  const daysSinceMonday = (local.weekday + 6) % 7;
  const date = new Date(Date.UTC(local.year, local.month - 1, local.day));
  date.setUTCDate(date.getUTCDate() - daysSinceMonday);
  return zonedTimeToUnix(
    date.getUTCFullYear(),
    date.getUTCMonth() + 1,
    date.getUTCDate(),
    0,
    0,
    0,
    timeZone,
  );
}

/** Given a Monday 00:00 local start, return the full bounds of that week. */
export function weekBoundsFromStart(startsAt: number, timeZone: string): WeekBounds {
  const local = getLocalParts(startsAt, timeZone);
  const nextMonday = new Date(Date.UTC(local.year, local.month - 1, local.day + 7));
  const nextStart = zonedTimeToUnix(
    nextMonday.getUTCFullYear(),
    nextMonday.getUTCMonth() + 1,
    nextMonday.getUTCDate(),
    0,
    0,
    0,
    timeZone,
  );
  return {
    startsAt,
    endsAt: nextStart - 1,
    voteDeadline: nextStart + VOTE_GRACE_SECONDS,
  };
}

export function getWeekBounds(instant: number, timeZone: string): WeekBounds {
  return weekBoundsFromStart(startOfLocalWeek(instant, timeZone), timeZone);
}

export function nextWeekStart(startsAt: number, timeZone: string): number {
  return weekBoundsFromStart(startsAt, timeZone).endsAt + 1;
}

/** Local weekday (0=Sun) and hour, used by the Sunday reminder. */
export function localWeekdayAndHour(instant: number, timeZone: string): { weekday: number; hour: number } {
  const local = getLocalParts(instant, timeZone);
  return { weekday: local.weekday, hour: local.hour };
}

/** True when the local wall clock is Sunday at/after 18:00. */
export function isReminderWindow(instant: number, timeZone: string): boolean {
  const { weekday, hour } = localWeekdayAndHour(instant, timeZone);
  return weekday === 0 && hour >= 18;
}

/** A stable YYYY-MM-DD for display / debugging (not used for storage). */
export function localDateKey(instant: number, timeZone: string): string {
  const local = getLocalParts(instant, timeZone);
  return `${local.year.toString().padStart(4, '0')}-${local.month
    .toString()
    .padStart(2, '0')}-${local.day
    .toString()
    .padStart(2, '0')}`;
}

/** Local calendar month key, e.g. `2025-01`. */
export function localMonthKey(instant: number, timeZone: string): string {
  const local = getLocalParts(instant, timeZone);
  return `${local.year.toString().padStart(4, '0')}-${local.month
    .toString()
    .padStart(2, '0')}`;
}

export function isValidMonthKey(month: string): boolean {
  return /^\d{4}-(0[1-9]|1[0-2])$/u.test(month);
}

export function monthStartUnix(month: string, timeZone: string): number {
  const [year, monthNumber] = month.split('-').map(Number) as [number, number];
  return zonedTimeToUnix(year, monthNumber, 1, 0, 0, 0, timeZone);
}

/** [start, end) Unix seconds of a calendar month in the group's timezone. */
export function monthRange(month: string, timeZone: string): { start: number; end: number } {
  const [year, monthNumber] = month.split('-').map(Number) as [number, number];
  const nextYear = monthNumber === 12 ? year + 1 : year;
  const nextMonthNumber = monthNumber === 12 ? 1 : monthNumber + 1;
  return {
    start: zonedTimeToUnix(year, monthNumber, 1, 0, 0, 0, timeZone),
    end: zonedTimeToUnix(nextYear, nextMonthNumber, 1, 0, 0, 0, timeZone),
  };
}

/** Previous local calendar month key at `instant`. */
export function previousMonthKey(instant: number, timeZone: string): string {
  const local = getLocalParts(instant, timeZone);
  const year = local.month === 1 ? local.year - 1 : local.year;
  const month = local.month === 1 ? 12 : local.month - 1;
  return `${year.toString().padStart(4, '0')}-${month.toString().padStart(2, '0')}`;
}

/**
 * "Awards night" is the first Monday of the local month at/after 19:00. The
 * hourly cron retries later the same evening, so a tick that finds a week still
 * inside its vote grace can try again at 20:00, 21:00, ... By 19:00 the last
 * week that starts in the previous month is always closed and past its Monday
 * 12:00 deadline.
 *
 * Using local calendar parts (rather than UTC) keeps the window DST-safe: a
 * 19:00 local ceremony is 18:00 UTC in Europe/Paris summer time but 17:00 UTC
 * in winter.
 */
export function isMonthlyAwardsWindow(instant: number, timeZone: string): boolean {
  const local = getLocalParts(instant, timeZone);
  return local.weekday === 1 && local.day <= 7 && local.hour >= 19;
}

/** Human label for a `YYYY-MM` key, e.g. `January 2025`. */
export function monthLabel(month: string): string {
  const [year, monthNumber] = month.split('-').map(Number) as [number, number];
  return new Intl.DateTimeFormat('en-US', {
    timeZone: 'UTC',
    month: 'long',
    year: 'numeric',
  }).format(new Date(Date.UTC(year, monthNumber - 1, 1, 12)));
}

/**
 * House-fixture window: Wednesday 23:59:59 local of the current matchweek.
 * `startsAt` is that week's Monday 00:00 local.
 */
export function houseFixtureDeadline(startsAt: number, timeZone: string): number {
  const monday = getLocalParts(startsAt, timeZone);
  const wednesday = new Date(Date.UTC(monday.year, monday.month - 1, monday.day + 2));
  return zonedTimeToUnix(
    wednesday.getUTCFullYear(),
    wednesday.getUTCMonth() + 1,
    wednesday.getUTCDate(),
    23,
    59,
    59,
    timeZone,
  );
}
