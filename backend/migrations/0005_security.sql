-- 0005: security hardening.
--
-- 1. point_events.challenge_id + a partial unique index: at most one
--    first_bonus row per challenge, regardless of which member's submission
--    won it. The award path uses INSERT OR IGNORE and only credits the bonus
--    when its INSERT actually landed, so concurrent acceptances cannot
--    double-award.
-- 2. used_nonces: one-shot Apple identity-token nonces, keyed by the SHA-256
--    of the token's nonce claim and purged once the token expires.

ALTER TABLE point_events ADD COLUMN challenge_id TEXT;

-- Backfill historical first_bonus rows from their submission.
UPDATE point_events
   SET challenge_id = (
         SELECT s.challenge_id
           FROM submissions s
          WHERE s.id = point_events.submission_id
       )
 WHERE kind = 'first_bonus'
   AND challenge_id IS NULL;

-- Defensive: if a pre-fix race already wrote duplicates, keep the earliest
-- row (lowest rowid) so the unique index can be created.
DELETE FROM point_events
 WHERE kind = 'first_bonus'
   AND challenge_id IS NOT NULL
   AND rowid NOT IN (
     SELECT MIN(rowid)
       FROM point_events
      WHERE kind = 'first_bonus'
        AND challenge_id IS NOT NULL
      GROUP BY challenge_id
   );

CREATE UNIQUE INDEX IF NOT EXISTS idx_point_events_one_first_bonus
  ON point_events (challenge_id)
  WHERE kind = 'first_bonus' AND challenge_id IS NOT NULL;

CREATE TABLE IF NOT EXISTS used_nonces (
  nonce_hash TEXT PRIMARY KEY,
  expires_at INTEGER NOT NULL,
  created_at INTEGER NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_used_nonces_expires ON used_nonces (expires_at);
