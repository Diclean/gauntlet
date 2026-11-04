import type { Env, GroupRow } from './types';
import { all, nowSeconds } from './lib/db';
import { isReminderWindow, startOfLocalWeek } from './business/time';
import {
  cleanupEphemeral,
  closeOpenWeeksBefore,
  createWeekAndChallenges,
  expirePastDeadlineSubmissions,
  finalizeDueWeeks,
  getWeekByStart,
  membersWithChallengesLeft,
} from './services/weeks';
import { pushDeadlineReminder, pushNewWeek } from './push';
import { maybeRunMonthlyAwards } from './services/awards';

/**
 * Hourly cron:
 *  1. Monday rollover: close prior open weeks, create + generate the current
 *     local week (idempotent through UNIQUE(group_id, starts_at)).
 *  2. Finalize closed weeks once their +12h vote grace has elapsed: expire
 *     remaining pending proofs, award weekly-winner and streak points.
 *  3. Expire pending submissions whose deadline passed.
 *  4. Sunday >= 18:00 local: one "X challenges left" push per member, then
 *     mark reminder_sent so retries do not spam.
 *  5. First Monday of the month >= 19:00 local: compute the previous month's
 *     awards from every week starting in it (one-shot per group/month), ledger
 *     +50 for Player of the Month, push once.
 *
 * Note: weekly-winner/streak awards happen at the vote deadline rather than at
 * Monday 00:00 so votes cast during the grace period still count. Weeks are
 * still marked closed at rollover, and the awards are idempotent.
 */
export async function runCron(env: Env, now: number = nowSeconds()): Promise<void> {
  await expirePastDeadlineSubmissions(env, now);

  const groups = await all<GroupRow>(env.DB.prepare('SELECT * FROM groups ORDER BY created_at ASC'));

  for (const group of groups) {
    try {
      await processGroup(env, group, now);
    } catch (error) {
      console.error('cron_group_failed', {
        name: error instanceof Error ? error.name : 'Error',
      });
    }
  }

  try {
    await cleanupEphemeral(env.DB, now);
  } catch (error) {
    console.error('cron_cleanup_failed', { name: error instanceof Error ? error.name : 'Error' });
  }
}

async function processGroup(env: Env, group: GroupRow, now: number): Promise<void> {
  const currentStart = startOfLocalWeek(now, group.timezone);
  await closeOpenWeeksBefore(env.DB, group.id, currentStart);

  let current = await getWeekByStart(env.DB, group.id, currentStart);
  if (!current) {
    const created = await createWeekAndChallenges(env, group, currentStart);
    current = created.week;
    if (created.created) {
      await pushNewWeek(env, group.id, created.challenges.length);
    }
  }

  await finalizeDueWeeks(env, group, now);

  // Monthly "Awards night": first Monday of the month, 19:00 group-local,
  // previous month. The run guard makes later ticks no-ops.
  try {
    await maybeRunMonthlyAwards(env, group, now);
  } catch (error) {
    console.error('monthly_awards_failed', {
      name: error instanceof Error ? error.name : 'Error',
    });
  }

  if (isReminderWindow(now, group.timezone) && current.reminder_sent === 0) {
    const marked = await env.DB.prepare(
      'UPDATE weeks SET reminder_sent = 1 WHERE id = ? AND reminder_sent = 0',
    )
      .bind(current.id)
      .run();
    if ((marked.meta.changes ?? 0) > 0) {
      const left = await membersWithChallengesLeft(env.DB, group.id, current.id);
      if (left.length > 0) await pushDeadlineReminder(env, group.id, left);
    }
  }
}
