-- One-shot guard for monthly awards.
--
-- The first run that inserts (group_id, month) is the only one allowed to write
-- that month's awards/ledger rows. The run insert and every dependent write go
-- into the same D1 batch, so a concurrent/later tick either sees the existing
-- row (and stops) or fails the primary-key insert and rolls the whole batch back.
--
-- Backfill months already awarded before this migration so they are not
-- recomputed or re-pushed once 0003 ships.

CREATE TABLE IF NOT EXISTS monthly_award_runs (
  group_id TEXT NOT NULL,
  month TEXT NOT NULL,
  ran_at INTEGER NOT NULL,
  PRIMARY KEY (group_id, month)
);

INSERT OR IGNORE INTO monthly_award_runs (group_id, month, ran_at)
SELECT group_id, month, COALESCE(MAX(created_at), 0)
  FROM monthly_awards
 GROUP BY group_id, month;
