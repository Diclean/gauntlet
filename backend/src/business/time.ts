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
    .padStart(2, '0')}-${local.day.toString().padStart(2, '0')}`;
}
