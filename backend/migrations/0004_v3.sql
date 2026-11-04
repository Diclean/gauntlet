-- v3 "safety, banter, captain, house fixture" additions.
--
-- 1. users.terms_accepted_at: App Store 1.2 house-rules acceptance gate.
-- 2. challenges: veto/replacement bookkeeping + house fixtures.
-- 3. submissions: SQLite cannot widen a CHECK constraint in place, so the
--    table is rebuilt to allow status 'removed' (reported content), preserving
--    every row and recreating every index (including the partial unique index
--    that enforces one pending proof per user+challenge).
-- 4. point_events: rebuilt (as in 0002) to allow kind 'captain'.
-- 5. New tables: reports, blocks, group_bans, vetoes, notification_prefs,
--    reactions, comments, captains, banter_pushes (push throttle).

ALTER TABLE users ADD COLUMN terms_accepted_at INTEGER;

ALTER TABLE challenges ADD COLUMN vetoed_at INTEGER;
ALTER TABLE challenges ADD COLUMN replaced_by TEXT;
ALTER TABLE challenges ADD COLUMN is_house INTEGER NOT NULL DEFAULT 0;
ALTER TABLE challenges ADD COLUMN created_by TEXT;
ALTER TABLE challenges ADD COLUMN created_at INTEGER NOT NULL DEFAULT 0;

CREATE INDEX IF NOT EXISTS idx_challenges_week_house ON challenges (week_id, is_house);
CREATE INDEX IF NOT EXISTS idx_challenges_replaced_by ON challenges (replaced_by);
-- One member-written house fixture per matchweek (also guards concurrent POSTs).
CREATE UNIQUE INDEX IF NOT EXISTS idx_challenges_one_house
  ON challenges (week_id) WHERE is_house = 1;

-- Rebuild submissions to widen the status CHECK with 'removed'.
CREATE TABLE submissions_v3 (
  id TEXT PRIMARY KEY,
  challenge_id TEXT,
  user_id TEXT,
  media_key TEXT,
  media_type TEXT CHECK (media_type IN ('photo', 'video')),
  caption TEXT,
  status TEXT CHECK (status IN ('pending', 'accepted', 'rejected', 'expired', 'removed')),
  eligible_voters INTEGER,
  created_at INTEGER,
  decided_at INTEGER
);

INSERT INTO submissions_v3
  (id, challenge_id, user_id, media_key, media_type, caption, status,
   eligible_voters, created_at, decided_at)
SELECT id, challenge_id, user_id, media_key, media_type, caption, status,
       eligible_voters, created_at, decided_at
  FROM submissions;

DROP TABLE submissions;

ALTER TABLE submissions_v3 RENAME TO submissions;

CREATE INDEX IF NOT EXISTS idx_submissions_challenge_status ON submissions (challenge_id, status);
CREATE INDEX IF NOT EXISTS idx_submissions_user ON submissions (user_id);
CREATE INDEX IF NOT EXISTS idx_submissions_media_key ON submissions (media_key);
CREATE UNIQUE INDEX IF NOT EXISTS idx_submissions_one_pending
  ON submissions (challenge_id, user_id)
  WHERE status = 'pending';

-- Rebuild point_events to widen the kind CHECK with 'captain'.
CREATE TABLE point_events_v3 (
  id TEXT PRIMARY KEY,
  group_id TEXT,
  week_id TEXT,
  user_id TEXT,
  kind TEXT CHECK (kind IN (
    'challenge',
    'first_bonus',
    'weekly_winner',
    'streak',
    'monthly_award',
    'captain'
  )),
  points INTEGER,
  submission_id TEXT,
  created_at INTEGER
);

INSERT INTO point_events_v3
  (id, group_id, week_id, user_id, kind, points, submission_id, created_at)
SELECT id, group_id, week_id, user_id, kind, points, submission_id, created_at
  FROM point_events;

DROP TABLE point_events;

ALTER TABLE point_events_v3 RENAME TO point_events;

CREATE INDEX IF NOT EXISTS idx_point_events_group_week ON point_events (group_id, week_id);
CREATE INDEX IF NOT EXISTS idx_point_events_group_user ON point_events (group_id, user_id);
CREATE INDEX IF NOT EXISTS idx_point_events_week_user_kind ON point_events (week_id, user_id, kind);
CREATE UNIQUE INDEX IF NOT EXISTS idx_point_events_idempotent
  ON point_events (group_id, week_id, user_id, kind, IFNULL(submission_id, ''));

-- Reports (one per reporter + target; target_type is submission or comment).
CREATE TABLE IF NOT EXISTS reports (
  id TEXT PRIMARY KEY,
  reporter_id TEXT NOT NULL,
  target_type TEXT NOT NULL CHECK (target_type IN ('submission', 'comment')),
  target_id TEXT NOT NULL,
  group_id TEXT NOT NULL,
  reason TEXT NOT NULL CHECK (reason IN (
    'nudity',
    'violence',
    'harassment',
    'dangerous',
    'spam',
    'other'
  )),
  note TEXT,
  created_at INTEGER NOT NULL,
  UNIQUE (reporter_id, target_type, target_id)
);

CREATE INDEX IF NOT EXISTS idx_reports_target ON reports (target_type, target_id);
CREATE INDEX IF NOT EXISTS idx_reports_group ON reports (group_id);

-- One-way, silent blocks.
CREATE TABLE IF NOT EXISTS blocks (
  blocker_id TEXT NOT NULL,
  blocked_id TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  PRIMARY KEY (blocker_id, blocked_id)
);

CREATE INDEX IF NOT EXISTS idx_blocks_blocked ON blocks (blocked_id);

-- Removing a member bans them from the club until the owner lifts it.
CREATE TABLE IF NOT EXISTS group_bans (
  group_id TEXT NOT NULL,
  user_id TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  PRIMARY KEY (group_id, user_id)
);

-- Fixture vetoes (one per member per challenge).
CREATE TABLE IF NOT EXISTS vetoes (
  challenge_id TEXT NOT NULL,
  user_id TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  PRIMARY KEY (challenge_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_vetoes_user ON vetoes (user_id);

-- Notification preferences. Missing row => every category is on.
CREATE TABLE IF NOT EXISTS notification_prefs (
  user_id TEXT PRIMARY KEY,
  new_week INTEGER NOT NULL DEFAULT 1,
  vote_needed INTEGER NOT NULL DEFAULT 1,
  result INTEGER NOT NULL DEFAULT 1,
  deadline INTEGER NOT NULL DEFAULT 1,
  awards INTEGER NOT NULL DEFAULT 1,
  banter INTEGER NOT NULL DEFAULT 1
);

-- Banter reactions (emoji allowlist enforced both here and in zod).
CREATE TABLE IF NOT EXISTS reactions (
  user_id TEXT NOT NULL,
  submission_id TEXT NOT NULL,
  emoji TEXT NOT NULL CHECK (emoji IN ('🔥', '😂', '🤡', '🐐', '😮', '👏')),
  created_at INTEGER NOT NULL,
  PRIMARY KEY (user_id, submission_id, emoji)
);

CREATE INDEX IF NOT EXISTS idx_reactions_submission ON reactions (submission_id);

CREATE TABLE IF NOT EXISTS comments (
  id TEXT PRIMARY KEY,
  submission_id TEXT NOT NULL,
  user_id TEXT NOT NULL,
  text TEXT NOT NULL,
  created_at INTEGER NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_comments_submission_created
  ON comments (submission_id, created_at);

-- Captain armband: one fixture per member per week.
CREATE TABLE IF NOT EXISTS captains (
  week_id TEXT NOT NULL,
  user_id TEXT NOT NULL,
  challenge_id TEXT NOT NULL,
  PRIMARY KEY (week_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_captains_challenge ON captains (challenge_id);

-- At most one "banter" push per submission per 10 minutes.
CREATE TABLE IF NOT EXISTS banter_pushes (
  submission_id TEXT PRIMARY KEY,
  last_sent_at INTEGER NOT NULL
);
