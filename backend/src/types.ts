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

  /** Public origin used to build invite links (`<base>/join/<code>`). */
  PUBLIC_BASE_URL?: string;
  /** Apple Developer team id for the universal-links association file. */
  APPLE_TEAM_ID?: string;
  /** TestFlight invite URL shown on the /join page. */
  TESTFLIGHT_URL?: string;
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
  /** Unix seconds at which the user accepted the house rules, or null. */
  terms_accepted_at?: number | null;
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
  /** Display-only club forfeit, max 60 chars. Never enforced. */
  forfeit: string;
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
  /** 1-based matchweek index since the group was created. */
  number: number;
}

export interface ChallengeRow {
  id: string;
  week_id: string;
  title: string;
  description: string;
  difficulty: 'easy' | 'medium' | 'hard';
  points: number;
  position: number;
  /** Set when the fixture was vetoed out; vetoed challenges are never served. */
  vetoed_at: number | null;
  /** The replacement challenge created after a successful veto, if any. */
  replaced_by: string | null;
  /** 1 for member-written house fixtures. */
  is_house: number;
  created_by: string | null;
  created_at: number;
}

export type SubmissionStatus = 'pending' | 'accepted' | 'rejected' | 'expired' | 'removed';

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

export type PointKind =
  | 'challenge'
  | 'first_bonus'
  | 'weekly_winner'
  | 'streak'
  | 'monthly_award'
  | 'captain';

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
  forfeit: string;
  /** `<PUBLIC_BASE_URL>/join/<inviteCode>`. */
  inviteUrl: string;
}

export interface WeekJson {
  id: string;
  number: number;
  startsAt: number;
  endsAt: number;
  voteDeadline: number;
  status: 'open' | 'closed';
  /** The fixture the caller picked as their captain fixture this week. */
  myCaptainChallengeId: string | null;
  /** Fixtures this club already replaced this week (0–2). */
  vetoesUsed: number;
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
  /** Members who vetoed this fixture and the votes needed to replace it. */
  vetoCount: number;
  vetoThreshold: number;
  myVeto: boolean;
  /** True for a replacement fixture created less than 24h ago. */
  isNew: boolean;
  isHouse: boolean;
  createdBy: PublicUser | null;
  isCaptain: boolean;
}

export interface MemberJson {
  user: PublicUser;
  joinedAt: number;
}

/** A banned user with the unix-second timestamp of the ban. */
export interface BannedUserJson extends PublicUser {
  bannedAt: number;
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
  /**
   * Members who voted on the submission (in vote order). Empty while the tally
   * is hidden: the viewer has not voted yet and the submission is still pending.
   */
  voters: PublicUser[];
  /** The six allowed emojis in fixed order; zero-count reactions are omitted. */
  reactions: ReactionJson[];
  commentCount: number;
}

export interface ReactionJson {
  emoji: string;
  count: number;
  mine: boolean;
}

export interface CommentJson {
  id: string;
  user: PublicUser;
  text: string;
  createdAt: number;
  canDelete: boolean;
}

/** Client-editable push categories (all on by default). */
export interface NotificationPrefsJson {
  newWeek: boolean;
  voteNeeded: boolean;
  result: boolean;
  deadline: boolean;
  awards: boolean;
  banter: boolean;
}

/** `GET /groups/:id/week` house-fixture availability for the caller. */
export interface HouseFixtureJson {
  allowed: boolean;
  deadline: number;
  author: PublicUser | null;
}

export type ReportReason =
  | 'nudity'
  | 'violence'
  | 'harassment'
  | 'dangerous'
  | 'spam'
  | 'other';

export interface LeaderboardEntryJson {
  user: PublicUser;
  points: number;
  rank: number;
  streak: number;
}

/** Title-race curve: one entry per member, arrays aligned with `weeks`. */
export interface RaceWeekJson {
  id: string;
  number: number;
  startsAt: number;
}

export interface RaceSeriesJson {
  user: PublicUser;
  cumulative: number[];
  perWeek: number[];
}

export interface RaceJson {
  weeks: RaceWeekJson[];
  series: RaceSeriesJson[];
  me: {
    bestWeek: { number: number; points: number };
    avgPerWeek: number;
    streak: number;
  };
}

export interface ReceiptLineJson {
  label: string;
  points: number;
  struck: boolean;
}

export interface ReceiptJson {
  week: {
    id: string;
    number: number;
    startsAt: number;
    endsAt: number;
    vetoesUsed: number;
  };
  club: { name: string; forfeit: string };
  player: { user: PublicUser; rank: number; rankDelta: number; total: number };
  lines: ReceiptLineJson[];
  manOfTheMatch: PublicUser | null;
  woodenSpoon: PublicUser | null;
}

export type AwardKey =
  | 'player_of_the_month'
  | 'golden_boot'
  | 'toughest_ref'
  | 'comeback_kid'
  | 'first_to_score'
  | 'wooden_spoon';

export interface AwardWinnerJson {
  user: PublicUser;
  value: number;
}

/** The winner's month, shown on the Player of the Month pennant. */
export interface PlayerOfTheMonthStats {
  points: number;
  goals: number;
  redCards: number;
  firstToScore: number;
  bestWeek: number;
}

export interface AwardJson {
  award: AwardKey;
  winners: PublicUser[];
  value: number;
  nominees: AwardWinnerJson[];
  /** Only Player of the Month carries stats; every other award omits it. */
  stats?: PlayerOfTheMonthStats;
}

export interface AwardsJson {
  month: string | null;
  awards: AwardJson[];
}

export interface TrophyJson {
  groupId: string;
  groupName: string;
  month: string;
  award: AwardKey;
  value: number;
}

export interface MonthlyAwardRow {
  id: string;
  group_id: string;
  month: string;
  award: AwardKey;
  user_id: string;
  value: number;
  created_at: number;
}

/** One-shot guard: a (group, month) awards run may happen exactly once. */
export interface MonthlyAwardRunRow {
  group_id: string;
  month: string;
  ran_at: number;
}

export function toPublicUser(row: UserRow): PublicUser {
  return {
    id: row.id,
    displayName: row.display_name,
    avatarEmoji: row.avatar_emoji ?? null,
  };
}
