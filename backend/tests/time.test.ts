import { describe, expect, it } from 'vitest';
import {
  getLocalParts,
  getWeekBounds,
  isMonthlyAwardsWindow,
  isReminderWindow,
  isValidTimeZone,
  localDateKey,
  localWeekdayAndHour,
  startOfLocalWeek,
  zonedTimeToUnix,
} from '../src/business/time';

const UTC_START = 1_736_121_600; // Mon 2025-01-06 00:00:00 UTC

describe('week boundaries', () => {
  it('computes a UTC week from a mid-week instant', () => {
    expect(getWeekBounds(1_736_337_600, 'UTC')).toEqual({
      startsAt: 1_736_121_600,
      endsAt: 1_736_726_399,
      voteDeadline: 1_736_769_600,
    });
  });

  it('uses Monday 00:00 local, not UTC, in Europe/Paris', () => {
    const bounds = getWeekBounds(1_736_119_800, 'Europe/Paris'); // Mon 00:30 local
    expect(bounds.startsAt).toBe(1_736_118_000); // Mon 00:00 CET
    expect(bounds.endsAt).toBe(1_736_722_799);
    expect(bounds.voteDeadline).toBe(1_736_766_000);
  });

  it('still belongs to the previous week late Sunday night in Paris', () => {
    const bounds = getWeekBounds(1_736_116_200, 'Europe/Paris'); // Sun 23:30 local
    expect(bounds.startsAt).toBe(1_735_513_200); // Mon 2024-12-30 00:00 CET
    expect(bounds.endsAt).toBe(1_736_117_999);
  });

  it('handles the spring-forward week in America/New_York', () => {
    const bounds = getWeekBounds(1_741_780_800, 'America/New_York'); // Wed Mar 12 12:00Z
    expect(bounds.startsAt).toBe(1_741_579_200); // Mon Mar 10 00:00 EDT
    expect(bounds.endsAt).toBe(1_742_183_999);
    expect(bounds.voteDeadline).toBe(1_742_227_200);
  });

  it('handles the fall-back week in America/New_York', () => {
    const instant = 1_761_624_000; // Tue Oct 28 2025 00:00Z
    const bounds = getWeekBounds(instant, 'America/New_York');
    expect(bounds.startsAt).toBe(1_761_537_600); // Mon Oct 27 00:00 EDT
    expect(bounds.endsAt).toBe(1_762_145_999);
    expect(bounds.voteDeadline).toBe(1_762_189_200);
    // The local week is 7 days + 1 hour long across the DST transition.
    expect(bounds.endsAt + 1 - bounds.startsAt).toBe(7 * 86_400 + 3_600);
  });

  it('handles Asia/Tokyo (no DST, UTC+9)', () => {
    const bounds = getWeekBounds(1_736_294_400, 'Asia/Tokyo');
    expect(bounds.startsAt).toBe(1_736_089_200);
    expect(bounds.endsAt).toBe(1_736_693_999);
    expect(bounds.voteDeadline).toBe(1_736_737_200);
  });

  it('handles Pacific/Auckland summer time (UTC+13)', () => {
    const bounds = getWeekBounds(1_736_294_400, 'Pacific/Auckland');
    expect(bounds.startsAt).toBe(1_736_074_800);
    expect(bounds.endsAt).toBe(1_736_679_599);
    expect(bounds.voteDeadline).toBe(1_736_722_800);
  });

  it('puts Sunday 23:59:59 and Monday 00:00 on the correct sides', () => {
    expect(getWeekBounds(1_736_726_399, 'UTC').startsAt).toBe(UTC_START);
    expect(getWeekBounds(1_736_726_400, 'UTC').startsAt).toBe(1_736_726_400);
  });
});

describe('timezone helpers', () => {
  it('validates IANA zones', () => {
    expect(isValidTimeZone('UTC')).toBe(true);
    expect(isValidTimeZone('America/New_York')).toBe(true);
    expect(isValidTimeZone('Mars/Olympus_Mons')).toBe(false);
    expect(isValidTimeZone('')).toBe(false);
  });

  it('round-trips a local wall clock through DST', () => {
    expect(zonedTimeToUnix(2025, 3, 10, 0, 0, 0, 'America/New_York')).toBe(1_741_579_200);
    expect(zonedTimeToUnix(2025, 1, 6, 0, 0, 0, 'Europe/Paris')).toBe(1_736_118_000);
  });

  it('reports the local weekday/hour', () => {
    expect(localWeekdayAndHour(1_736_704_800, 'UTC')).toEqual({ weekday: 0, hour: 18 });
    expect(localWeekdayAndHour(1_736_704_800, 'Europe/Paris')).toEqual({ weekday: 0, hour: 19 });
    expect(getLocalParts(1_736_337_600, 'UTC').weekday).toBe(3);
  });

  it('detects the Sunday 18:00 reminder window', () => {
    expect(isReminderWindow(1_736_704_800, 'UTC')).toBe(true); // Sun 18:00
    expect(isReminderWindow(1_736_704_740, 'UTC')).toBe(false); // Sun 17:59
    expect(isReminderWindow(1_736_762_400, 'UTC')).toBe(false); // Mon 18:00
  });

  it('exposes a local date key', () => {
    expect(localDateKey(1_736_337_600, 'UTC')).toBe('2025-01-08');
    expect(localDateKey(1_736_119_800, 'Europe/Paris')).toBe('2025-01-06');
  });

  it('startOfLocalWeek is idempotent', () => {
    const start = startOfLocalWeek(1_736_337_600, 'America/New_York');
    expect(startOfLocalWeek(start, 'America/New_York')).toBe(start);
  });
});

describe('monthly awards window', () => {
  // 2025-09-01 is a Monday and the 1st of the month: the window opens at 19:00.
  const SEP_1_1900_UTC = 1_756_753_200;
  const SEP_1_1859_UTC = SEP_1_1900_UTC - 60;

  it('opens on the first Monday at 19:00 local, not at 18:59', () => {
    expect(isMonthlyAwardsWindow(SEP_1_1859_UTC, 'UTC')).toBe(false);
    expect(isMonthlyAwardsWindow(SEP_1_1900_UTC, 'UTC')).toBe(true);
    // Later ticks the same evening still retry/confirm the run.
    expect(isMonthlyAwardsWindow(SEP_1_1900_UTC + 3 * 3_600, 'UTC')).toBe(true);
  });

  it('does nothing on the 1st when the 1st is not the first Monday', () => {
    // 2025-10-01 is a Wednesday; Awards night is Monday 2025-10-06.
    expect(isMonthlyAwardsWindow(1_759_345_200, 'UTC')).toBe(false);
    expect(isMonthlyAwardsWindow(1_759_777_200, 'UTC')).toBe(true);
  });

  it('does not run on a later Monday of the month', () => {
    // 2025-09-08 is the second Monday.
    expect(isMonthlyAwardsWindow(1_757_358_000, 'UTC')).toBe(false);
    // The day after the first Monday is a Tuesday.
    expect(isMonthlyAwardsWindow(1_756_839_600, 'UTC')).toBe(false);
  });

  it('uses local wall-clock time in Pacific/Auckland', () => {
    // 2025-09-01 19:00 NZST (UTC+12) = 07:00 UTC.
    expect(isMonthlyAwardsWindow(1_756_710_000, 'Pacific/Auckland')).toBe(true);
    expect(isMonthlyAwardsWindow(1_756_710_000 - 60, 'Pacific/Auckland')).toBe(false);
    // 07:00 UTC is still 2025-08-31 in UTC, proving local parts are used.
    expect(getLocalParts(1_756_710_000, 'Pacific/Auckland')).toMatchObject({
      year: 2025,
      month: 9,
      day: 1,
      hour: 19,
      weekday: 1,
    });
  });

  it('uses local wall-clock time in America/Los_Angeles', () => {
    // 2025-09-01 19:00 PDT (UTC-7) = 2025-09-02 02:00 UTC.
    expect(isMonthlyAwardsWindow(1_756_778_400, 'America/Los_Angeles')).toBe(true);
    expect(isMonthlyAwardsWindow(1_756_778_400 - 60, 'America/Los_Angeles')).toBe(false);
    expect(getLocalParts(1_756_778_400, 'America/Los_Angeles')).toMatchObject({
      year: 2025,
      month: 9,
      day: 1,
      hour: 19,
      weekday: 1,
    });
  });

  it('stays at 19:00 local across the fall-back DST transition', () => {
    // 2025-11-03 is the first Monday after US DST ends; 19:00 PST = 03:00 UTC.
    expect(isMonthlyAwardsWindow(1_762_225_200, 'America/Los_Angeles')).toBe(true);
    expect(isMonthlyAwardsWindow(1_762_225_200 - 60, 'America/Los_Angeles')).toBe(false);
    expect(getLocalParts(1_762_225_200, 'America/Los_Angeles')).toMatchObject({
      day: 3,
      hour: 19,
      weekday: 1,
    });
  });
});
