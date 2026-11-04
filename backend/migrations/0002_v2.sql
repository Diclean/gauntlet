-- v2 "Sunday League" additions.
--
-- 1. groups.forfeit: display-only club forfeit shown on the relegation line,
--    the full-time receipt and the Wooden Spoon award.
-- 2. weeks.number: 1-based matchweek index per group, backfilled in starts_at
--    order (the first generated week is matchweek 1).
-- 3. monthly_awards: one row per winner (ties => several rows) for a month.
--    The unique key includes user_id so ties are representable while repeated
--    cron ticks stay idempotent.
-- 4. point_events: SQLite cannot widen a CHECK constraint in place, so the
--    table is rebuilt (copy -> drop -> rename) to allow kind 'monthly_award',
--    preserving every row and recreating every index.

ALTER TABLE groups ADD COLUMN forfeit TEXT NOT NULL DEFAULT 'Buys the round 🍺';

ALTER TABLE weeks ADD COLUMN number INTEGER NOT NULL DEFAULT 0;

-- Backfill: matchweek 1 is the earliest week ever generated for the group.
UPDATE weeks
   SET number = (
     SELECT COUNT(*)
       FROM weeks AS earlier
      WHERE earlier.group_id = weeks.group_id
        AND earlier.starts_at <= weeks.starts_at
   );

CREATE INDEX IF NOT EXISTS idx_weeks_group_number ON weeks (group_id, number);

CREATE TABLE IF NOT EXISTS monthly_awards (
  id TEXT PRIMARY KEY,
  group_id TEXT NOT NULL,
  month TEXT NOT NULL,
  award TEXT NOT NULL CHECK (award IN (
    'player_of_the_month',
    'golden_boot',
    'toughest_ref',
    'comeback_kid',
    'first_to_score',
    'wooden_spoon'
  )),
  user_id TEXT NOT NULL,
  value INTEGER,
  created_at INTEGER,
  UNIQUE (group_id, month, award, user_id)
);

CREATE INDEX IF NOT EXISTS idx_monthly_awards_group_month
  ON monthly_awards (group_id, month);
CREATE INDEX IF NOT EXISTS idx_monthly_awards_user
  ON monthly_awards (user_id);

-- Rebuild point_events to widen the kind CHECK.
CREATE TABLE point_events_v2 (
  id TEXT PRIMARY KEY,
  group_id TEXT,
  week_id TEXT,
  user_id TEXT,
  kind TEXT CHECK (kind IN (
    'challenge',
    'first_bonus',
    'weekly_winner',
    'streak',
    'monthly_award'
  )),
  points INTEGER,
  submission_id TEXT,
  created_at INTEGER
);

INSERT INTO point_events_v2
  (id, group_id, week_id, user_id, kind, points, submission_id, created_at)
SELECT id, group_id, week_id, user_id, kind, points, submission_id, created_at
  FROM point_events;

DROP TABLE point_events;

ALTER TABLE point_events_v2 RENAME TO point_events;

-- Keep the original indexes (dropped with the table) plus the expression
-- index that makes cron retries and double votes idempotent.
CREATE INDEX IF NOT EXISTS idx_point_events_group_week ON point_events (group_id, week_id);
CREATE INDEX IF NOT EXISTS idx_point_events_group_user ON point_events (group_id, user_id);
CREATE INDEX IF NOT EXISTS idx_point_events_week_user_kind ON point_events (week_id, user_id, kind);
CREATE UNIQUE INDEX IF NOT EXISTS idx_point_events_idempotent
  ON point_events (group_id, week_id, user_id, kind, IFNULL(submission_id, ''));
