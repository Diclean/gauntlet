/**
 * Shared bindings, row shapes and API shapes.
 *
 * D1 rows use snake_case because that is the storage schema. Everything that
 * leaves the Worker is converted to the camelCase API shapes below.
 */

export interface Env {
  DB: D1Database;
  MEDIA: R2Bucket;

  APPLE_BUNDLE_ID: string;
  APPLE_JWKS_URL?: string;

  DEEPSEEK_API_KEY?: string;
  DEEPSEEK_BASE_URL?: string;

  APNS_KEY_P8?: string;
  APNS_KEY_ID?: string;
  APNS_TEAM_ID?: string;
  APNS_ENV?: string;
  APNS_BASE_URL?: string;
}

export interface PublicUser {
  id: string;
  displayName: string;
  avatarEmoji: string | null;
}

export type AppEnv = {
  Bindings: Env;
  Variables: {
    user: PublicUser;
    userRow: UserRow;
    sessionTokenHash: string;
  };
};

export interface UserRow {
  id: string;
  apple_sub: string;
  display_name: string;
  avatar_emoji: string | null;
  created_at: number;
}

export interface SessionRow {
  token_hash: string;
  user_id: string;
  expires_at: number;
  created_at: number;
}

export interface DeviceRow {
  id: string;
  user_id: string;
  apns_token: string;
  created_at: number;
}

export interface GroupRow {
  id: string;
  name: string;
  owner_id: string;
  invite_code: string;
  challenges_per_week: number;
  theme: string | null;
  language: string;
  timezone: string;
  created_at: number;
}

export interface GroupMemberRow {
  group_id: string;
  user_id: string;
  joined_at: number;
}

export interface WeekRow {
  id: string;
  group_id: string;
  starts_at: number;
  ends_at: number;
  vote_deadline: number;
  status: 'open' | 'closed';
  reminder_sent: number;
}

export interface ChallengeRow {
  id: string;
  week_id: string;
  title: string;
  description: string;
  difficulty: 'easy' | 'medium' | 'hard';
  points: number;
  position: number;
}

export type SubmissionStatus = 'pending' | 'accepted' | 'rejected' | 'expired';

export interface SubmissionRow {
  id: string;
  challenge_id: string;
  user_id: string;
  media_key: string;
  media_type: 'photo' | 'video';
  caption: string | null;
  status: SubmissionStatus;
  eligible_voters: number;
  created_at: number;
  decided_at: number | null;
}

export interface VoteRow {
  submission_id: string;
  voter_id: string;
  approve: number;
  created_at: number;
}

export type PointKind = 'challenge' | 'first_bonus' | 'weekly_winner' | 'streak';

export interface PointEventRow {
  id: string;
  group_id: string;
  week_id: string;
  user_id: string;
  kind: PointKind;
  points: number;
  submission_id: string | null;
  created_at: number;
}

export interface GroupJson {
  id: string;
  name: string;
  inviteCode: string;
  challengesPerWeek: number;
  theme: string | null;
  language: string;
  timezone: string;
  ownerId: string;
  memberCount: number;
}

export interface WeekJson {
  id: string;
  startsAt: number;
  endsAt: number;
  voteDeadline: number;
  status: 'open' | 'closed';
}

export type MyChallengeStatus = 'todo' | 'pending' | 'accepted' | 'rejected';

export interface ChallengeWithMyStatusJson {
  id: string;
  title: string;
  description: string;
  difficulty: 'easy' | 'medium' | 'hard';
  points: number;
  position: number;
  myStatus: MyChallengeStatus;
  acceptedCount: number;
}

export interface MemberJson {
  user: PublicUser;
  joinedAt: number;
}

export interface SubmissionJson {
  id: string;
  challengeId: string;
  challengeTitle: string;
  user: PublicUser;
  mediaUrl: string;
  mediaType: 'photo' | 'video';
  caption: string | null;
  status: SubmissionStatus;
  approvals: number;
  rejections: number;
  eligibleVoters: number;
  myVote: boolean | null;
  createdAt: number;
  decidedAt: number | null;
}

export interface LeaderboardEntryJson {
  user: PublicUser;
  points: number;
  rank: number;
  streak: number;
}

export function toPublicUser(row: UserRow): PublicUser {
  return {
    id: row.id,
    displayName: row.display_name,
    avatarEmoji: row.avatar_emoji ?? null,
  };
}
