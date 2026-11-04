-- Dares initial schema. Timestamps are Unix seconds. IDs are crypto.randomUUID().
-- All access goes through bound parameters; this file only defines storage.

CREATE TABLE IF NOT EXISTS users (
  id TEXT PRIMARY KEY,
  apple_sub TEXT UNIQUE NOT NULL,
  display_name TEXT NOT NULL,
  avatar_emoji TEXT,
  created_at INTEGER
);

CREATE TABLE IF NOT EXISTS sessions (
  token_hash TEXT PRIMARY KEY,
  user_id TEXT,
  expires_at INTEGER,
  created_at INTEGER
);

CREATE TABLE IF NOT EXISTS devices (
  id TEXT PRIMARY KEY,
  user_id TEXT,
  apns_token TEXT UNIQUE,
  created_at INTEGER
);

CREATE TABLE IF NOT EXISTS groups (
  id TEXT PRIMARY KEY,
  name TEXT,
  owner_id TEXT,
  invite_code TEXT UNIQUE,
  challenges_per_week INTEGER,
  theme TEXT,
  language TEXT,
  timezone TEXT,
  created_at INTEGER
);

CREATE TABLE IF NOT EXISTS group_members (
  group_id TEXT,
  user_id TEXT,
  joined_at INTEGER,
  PRIMARY KEY (group_id, user_id)
);

CREATE TABLE IF NOT EXISTS weeks (
  id TEXT PRIMARY KEY,
  group_id TEXT,
  starts_at INTEGER,
  ends_at INTEGER,
  vote_deadline INTEGER,
  status TEXT CHECK (status IN ('open', 'closed')),
  reminder_sent INTEGER DEFAULT 0,
  UNIQUE (group_id, starts_at)
);

CREATE TABLE IF NOT EXISTS challenges (
  id TEXT PRIMARY KEY,
  week_id TEXT,
  title TEXT,
  description TEXT,
  difficulty TEXT,
  points INTEGER,
  position INTEGER
);

CREATE TABLE IF NOT EXISTS submissions (
  id TEXT PRIMARY KEY,
  challenge_id TEXT,
  user_id TEXT,
  media_key TEXT,
  media_type TEXT CHECK (media_type IN ('photo', 'video')),
  caption TEXT,
  status TEXT CHECK (status IN ('pending', 'accepted', 'rejected', 'expired')),
  eligible_voters INTEGER,
  created_at INTEGER,
  decided_at INTEGER
);

CREATE TABLE IF NOT EXISTS votes (
  submission_id TEXT,
  voter_id TEXT,
  approve INTEGER,
  created_at INTEGER,
  PRIMARY KEY (submission_id, voter_id)
);

CREATE TABLE IF NOT EXISTS point_events (
  id TEXT PRIMARY KEY,
  group_id TEXT,
  week_id TEXT,
  user_id TEXT,
  kind TEXT CHECK (kind IN ('challenge', 'first_bonus', 'weekly_winner', 'streak')),
  points INTEGER,
  submission_id TEXT,
  created_at INTEGER
);

CREATE TABLE IF NOT EXISTS rate_limits (
  key TEXT PRIMARY KEY,
  tokens REAL,
  updated_at INTEGER
);

-- Sessions / devices
CREATE INDEX IF NOT EXISTS idx_sessions_user ON sessions (user_id);
CREATE INDEX IF NOT EXISTS idx_sessions_expires ON sessions (expires_at);
CREATE INDEX IF NOT EXISTS idx_devices_user ON devices (user_id);

-- Groups / membership
CREATE INDEX IF NOT EXISTS idx_group_members_user ON group_members (user_id);

-- Weeks / challenges
CREATE INDEX IF NOT EXISTS idx_weeks_group_status ON weeks (group_id, status);
CREATE INDEX IF NOT EXISTS idx_weeks_vote_deadline ON weeks (vote_deadline);
CREATE INDEX IF NOT EXISTS idx_challenges_week_position ON challenges (week_id, position);

-- Submissions: at most one active (pending) submission per (challenge, user).
CREATE INDEX IF NOT EXISTS idx_submissions_challenge_status ON submissions (challenge_id, status);
CREATE INDEX IF NOT EXISTS idx_submissions_user ON submissions (user_id);
CREATE INDEX IF NOT EXISTS idx_submissions_media_key ON submissions (media_key);
CREATE UNIQUE INDEX IF NOT EXISTS idx_submissions_one_pending
  ON submissions (challenge_id, user_id)
  WHERE status = 'pending';

-- Votes
CREATE INDEX IF NOT EXISTS idx_votes_voter ON votes (voter_id);

-- Point ledger. The expression index makes cron retries / double votes idempotent
-- while still allowing several challenge/first_bonus rows for the same week.
CREATE INDEX IF NOT EXISTS idx_point_events_group_week ON point_events (group_id, week_id);
CREATE INDEX IF NOT EXISTS idx_point_events_group_user ON point_events (group_id, user_id);
CREATE INDEX IF NOT EXISTS idx_point_events_week_user_kind ON point_events (week_id, user_id, kind);
CREATE UNIQUE INDEX IF NOT EXISTS idx_point_events_idempotent
  ON point_events (group_id, week_id, user_id, kind, IFNULL(submission_id, ''));

-- Rate limits are ephemeral; index for cheap cleanup in cron/tests.
CREATE INDEX IF NOT EXISTS idx_rate_limits_updated ON rate_limits (updated_at);
