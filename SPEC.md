# Weekly Dares — product & technical spec

Working name: **Dares** (bundle id `com.mathys.dares`). iPhone app for friend groups: every week the
AI generates a list of challenges; members complete them with **live camera** photo/video proof;
other members vote; accepted proofs earn points.

Monorepo layout:

```
/SPEC.md            ← this file, the single source of truth
/backend            ← Cloudflare Worker (TypeScript), D1, R2, Cron Triggers
/ios                ← SwiftUI app (iOS 18+), XcodeGen project.yml
```

---

## 1. Product rules

### Groups
- A user can create or join **multiple groups**. Join with a 6-char invite code (A–Z, 2–9, no ambiguous chars).
- Group settings (editable by the group owner): `name`, `challenges_per_week` (3–10, default 5),
  `theme` (optional free text sent to the AI, max 200 chars), `language` (`en` default; `fr` later),
  `timezone` (IANA, default from the creator's device).
- Max 30 members per group.

### Week
- A week runs **Monday 00:00 → Sunday 23:59:59 in the group's timezone**.
- On Monday 00:00 (local) the server generates that week's challenges with the DeepSeek API.
- Submissions are only allowed while the week is open. Votes are allowed until Monday 00:00 + 12h grace
  (so Sunday-night proofs can still be judged); after that, pending submissions are marked `expired`.

### Challenges
- Each has: `title` (≤80 chars), `description` (≤300), `difficulty` ∈ `easy|medium|hard`, `points` (10/25/50).
- The AI must produce challenges that are doable within a week, safe, legal, non-humiliating, and provable by photo/video.

### Submissions (proof)
- Proof is **camera-only** (no photo library import): a photo (JPEG/HEIC → JPEG) or a video (≤ 30 s, ≤ 50 MB, MP4/MOV).
- Optional caption ≤ 200 chars.
- One **active** submission per (user, challenge). If rejected, the user can resubmit while the week is open.
  Once accepted, no more submissions for that challenge.

### Voting
- You cannot vote on your own submission. One vote per member per submission (can change it while pending).
- Let `N` = number of group members **excluding the submitter** at submission time (store it as `eligible_voters`).
- **Accepted** when `approvals >= min(2, N)`.
- **Rejected** when `rejections >= ceil(N / 2)` (half the group without the submitter).
- Evaluate after every vote. Whichever threshold is hit first wins; status is then final.
- Edge case `N == 0` (solo group): submissions cannot be accepted; the app shows "invite friends to get votes".

### Points
- Accepted submission → challenge `points` (easy 10 / medium 25 / hard 50).
- **First-to-finish bonus**: +10 to the first member whose submission for that challenge got **accepted** (by `decided_at`).
- **Weekly winner**: when the week closes, the member(s) with the most points that week get +50 (ties all get it).
- **Streak**: a week counts toward the streak if the member got ≥1 accepted submission. At week close, each member with
  streak ≥ 2 gets `+5 × min(streak, 10)`.
- All points are stored as rows in a `point_events` ledger (never a mutable counter), so leaderboards are sums.
- Leaderboards: this week, and all-time (per group).

### Push notifications (APNs)
1. New week's challenges are ready (Monday).
2. Someone in your group submitted proof → needs your vote.
3. Your submission was accepted (+points) or rejected.
4. Deadline reminder Sunday 18:00 local: "X challenges left".

### Language
- English first. All UI strings go through `String(localized:)` / a String Catalog (`Localizable.xcstrings`) so French can be added later.
  The AI prompt takes the group's `language`.

---

## 2. Security requirements (non-negotiable)

- Auth: **Sign in with Apple only**. The app sends Apple's `identityToken` to `POST /auth/apple`. The Worker verifies the JWT
  signature against Apple's JWKS (`https://appleid.apple.com/auth/keys`, cache it), checks `iss=https://appleid.apple.com`,
  `aud=APPLE_BUNDLE_ID`, `exp`, and the `nonce` (SHA-256 of a client nonce). Then it issues its own session:
  an opaque random 32-byte token, stored **hashed (SHA-256)** in D1, 60-day expiry. Client keeps it in the **Keychain**.
- Every endpoint except `/auth/apple` and `/health` requires `Authorization: Bearer <token>`.
- **Authorization checks on every request**: a user can only read or write data of groups they are a member of. Media is never public:
  `GET /media/:key` checks that the requester is a member of the submission's group before streaming from R2.
- All SQL uses bound parameters (D1 `prepare().bind()`), never string concatenation.
- Validate every request body with **zod**. Reject unknown fields.
- Upload limits enforced server-side (content-type allowlist + size). R2 keys are random UUIDs, never user input.
- Rate limit sensitive endpoints (auth, join, submit, vote) per user/IP with a small D1-backed or in-memory token bucket.
- Secrets (`DEEPSEEK_API_KEY`, `APNS_KEY_P8`, `APNS_KEY_ID`, `APNS_TEAM_ID`, `APPLE_BUNDLE_ID`) come from `wrangler secret`, never committed.
  Ship a `.dev.vars.example`.
- The AI output is untrusted: validate with zod, clamp lengths, and fall back to a built-in challenge pool if the call fails or output is invalid.
- No PII in logs.

---

## 3. Backend (Cloudflare Worker)

Stack: TypeScript, **Hono** router, **zod**, D1 (SQLite), R2 bucket `MEDIA`, Cron Trigger every hour (`0 * * * *`),
**vitest** with `@cloudflare/vitest-pool-workers` for tests. `wrangler` as a devDependency (use `npx wrangler`).

### D1 schema (`backend/migrations/0001_init.sql`)

```
users(id TEXT PK, apple_sub TEXT UNIQUE NOT NULL, display_name TEXT NOT NULL, avatar_emoji TEXT, created_at INTEGER)
sessions(token_hash TEXT PK, user_id TEXT, expires_at INTEGER, created_at INTEGER)
devices(id TEXT PK, user_id TEXT, apns_token TEXT UNIQUE, created_at INTEGER)
groups(id TEXT PK, name TEXT, owner_id TEXT, invite_code TEXT UNIQUE, challenges_per_week INTEGER, theme TEXT,
       language TEXT, timezone TEXT, created_at INTEGER)
group_members(group_id TEXT, user_id TEXT, joined_at INTEGER, PRIMARY KEY(group_id, user_id))
weeks(id TEXT PK, group_id TEXT, starts_at INTEGER, ends_at INTEGER, vote_deadline INTEGER,
      status TEXT CHECK(status IN ('open','closed')), reminder_sent INTEGER DEFAULT 0, UNIQUE(group_id, starts_at))
challenges(id TEXT PK, week_id TEXT, title TEXT, description TEXT, difficulty TEXT, points INTEGER, position INTEGER)
submissions(id TEXT PK, challenge_id TEXT, user_id TEXT, media_key TEXT, media_type TEXT CHECK(media_type IN ('photo','video')),
            caption TEXT, status TEXT CHECK(status IN ('pending','accepted','rejected','expired')),
            eligible_voters INTEGER, created_at INTEGER, decided_at INTEGER)
votes(submission_id TEXT, voter_id TEXT, approve INTEGER, created_at INTEGER, PRIMARY KEY(submission_id, voter_id))
point_events(id TEXT PK, group_id TEXT, week_id TEXT, user_id TEXT, kind TEXT CHECK(kind IN ('challenge','first_bonus','weekly_winner','streak')),
             points INTEGER, submission_id TEXT, created_at INTEGER)
rate_limits(key TEXT PK, tokens REAL, updated_at INTEGER)
```
Add sensible indexes. Timestamps are Unix **seconds**. IDs are `crypto.randomUUID()`.

### REST API (JSON, camelCase keys)

| Method | Path | Body / notes | Response |
|---|---|---|---|
| GET | `/health` | | `{ok:true}` |
| POST | `/auth/apple` | `{identityToken, nonce, displayName?}` | `{token, user}` |
| POST | `/auth/logout` | auth required; deletes the presented session | `{ok:true}` |
| GET | `/me` | | `{user}` |
| PATCH | `/me` | `{displayName?, avatarEmoji?}` | `{user}` |
| DELETE | `/me` | deletes account + their media (App Store requirement) | `{ok:true}` |
| POST | `/devices` | `{apnsToken}` | `{ok:true}` |
| GET | `/groups` | groups I'm in | `{groups:[Group]}` |
| POST | `/groups` | `{name, challengesPerWeek?, theme?, language?, timezone}` | `{group}` — also generates the current week immediately |
| POST | `/groups/join` | `{inviteCode}` | `{group}` |
| GET | `/groups/:id` | | `{group, members:[Member]}` |
| PATCH | `/groups/:id` | owner only; `{name?, challengesPerWeek?, theme?, language?, timezone?}` (applies from next week) | `{group}` |
| POST | `/groups/:id/leave` | | `{ok:true}` |
| GET | `/groups/:id/week` | current week | `{week, challenges:[ChallengeWithMyStatus]}` |
| GET | `/groups/:id/feed?cursor=` | recent submissions in the group, newest first, page 20 | `{items:[Submission], nextCursor}` |
| GET | `/groups/:id/votes/pending` | pending submissions in the group, not mine, that I haven't voted on, oldest first | `{items:[Submission]}` |
| GET | `/groups/:id/leaderboard?scope=week\|all` | | `{entries:[{user, points, rank, streak}]}` |
| POST | `/challenges/:id/submissions` | **multipart/form-data**: `media` file, `mediaType` (`photo`/`video`), `caption?` | `{submission}` |
| GET | `/submissions/:id` | | `{submission}` |
| POST | `/submissions/:id/vote` | `{approve: boolean}` | `{submission}` |
| GET | `/media/:key` | auth + membership check, streams R2 object, supports `Range` for video | bytes |

Shapes:
```
User        {id, displayName, avatarEmoji}
Group       {id, name, inviteCode, challengesPerWeek, theme, language, timezone, ownerId, memberCount}
Member      {user, joinedAt}
Week        {id, startsAt, endsAt, voteDeadline, status}
ChallengeWithMyStatus {id, title, description, difficulty, points, position,
                       myStatus: 'todo'|'pending'|'accepted'|'rejected', acceptedCount}
Submission  {id, challengeId, challengeTitle, user, mediaUrl, mediaType, caption, status,
             approvals, rejections, eligibleVoters, myVote: boolean|null, createdAt, decidedAt,
             voters:[User]}
```
`voters` lists the members that voted on the proof, in vote order. It stays `[]` while the
tally is hidden — i.e. until the submission is decided (`accepted`/`rejected`) or the caller has
already voted on it — and is populated for decided proofs and for voters.
`mediaUrl` is the relative path `/media/<key>`; the client prefixes the base URL and sends the bearer token.
Errors: `{error: {code, message}}` with the proper HTTP status.

### Cron (hourly)
For each group, using its timezone:
1. If no `open` week exists for the current local Monday → close the previous week (expire pending submissions after the vote deadline,
   award weekly winner + streak points), then create the new week and generate challenges. Must be **idempotent** (UNIQUE(group_id, starts_at)).
2. Sunday ≥ 18:00 local and `reminder_sent = 0` → push a reminder to members with challenges left, set `reminder_sent = 1`.
3. Expire pending submissions whose week's `vote_deadline` has passed.

### DeepSeek
`POST https://api.deepseek.com/chat/completions`, model `deepseek-chat`, `response_format: {type: "json_object"}`.
Ask for `{"challenges":[{"title","description","difficulty"}]}` with exactly N items and a mix of difficulties. Include
the theme, the language, and the previous 3 weeks' titles to avoid repeats. Validate with zod; fall back to a pool on failure.

### APNs
Module `src/push.ts`: ES256 JWT (WebCrypto, `.p8` key), `POST https://api.push.apple.com/3/device/<token>` (sandbox host when `APNS_ENV=sandbox`).
Remove device tokens that return 410. Make push failures non-fatal. If push secrets are missing, log and skip.

### Tests (vitest, must pass)
Voting thresholds (N = 0, 1, 2, 3, 4, 7), first-finisher bonus, weekly-winner ties, streak bonus, week-boundary math across timezones,
membership authorization (non-member gets 403 on group, submission, media), and AI output validation + fallback.

---

## 4. iOS app (SwiftUI)

- iOS 18+, Swift 6, SwiftUI, `@Observable` models, async/await `URLSession`. **No third-party dependencies.**
- XcodeGen `ios/project.yml` → target `Dares`, bundle id `com.mathys.dares`, Sign in with Apple + Push Notifications capabilities
  (entitlements file), `NSCameraUsageDescription`, `NSMicrophoneUsageDescription`.
- `API_BASE_URL` set in an `.xcconfig` (Debug: `http://localhost:8787`, Release: placeholder `https://dares.example.workers.dev`).
  Allow local networking in ATS for Debug only.
- Session token stored in the **Keychain** (small `KeychainStore` wrapper).
- Strings via `Localizable.xcstrings`, English only for now.

### Screens
1. **Sign in**: Sign in with Apple button (nonce: random string, send SHA-256 to Apple, raw nonce to the server), then a display-name + emoji step on first launch.
2. **Groups list**: my groups + "Create group" (name, challenges per week stepper 3–10, optional theme) + "Join with code".
3. **Group home** (tabs or segmented control):
   - **Challenges**: this week's list with difficulty badge, points, my status chip, and a countdown to Sunday 23:59.
     Tap a challenge → detail with a "Prove it" button.
   - **Vote**: pending submissions from others that I haven't voted on (badge count). Full-screen media (photo, or looping video with AVKit),
     caption, Approve / Reject buttons, live progress "1/2 approvals · 0/2 rejections".
   - **Feed**: all recent submissions with status.
   - **Leaderboard**: This week / All time toggle, ranks, points, 🔥 streaks.
   - **Settings** (gear): invite code with ShareLink, members, owner-editable settings, leave group.
4. **Camera capture**: **camera-only** with `UIImagePickerController` (`sourceType = .camera`, media types image + movie,
   `videoMaximumDuration = 30`), wrapped in `UIViewControllerRepresentable`. Never offer the photo library. Compress the photo to JPEG (quality 0.8, max 2048 px).
   Preview → caption → upload with a progress indicator (multipart).
   On the Simulator (no camera) show a clear "Camera not available on Simulator" message, with a `#if DEBUG` option to use a bundled sample image so the flow can be tested.
5. **Profile**: edit name/emoji, sign out, delete account.

### Notifications
Request permission after sign-in, register for remote notifications, `POST /devices`. Tapping a push deep-links to the group / submission
(payload keys: `groupId`, `submissionId?`).

### Design
Clean, playful, native: SF Symbols, `.borderedProminent` buttons, a vivid accent color (e.g. orange), large titles,
difficulty colors (easy green / medium orange / hard red), haptics on vote and on accept. Support Dark Mode and Dynamic Type.

### Code layout
```
ios/project.yml
ios/Dares/App/          DaresApp.swift, AppState.swift, RootView.swift
ios/Dares/Networking/   APIClient.swift, Models.swift, Endpoints.swift, Multipart.swift
ios/Dares/Auth/         SignInView.swift, AppleSignIn.swift, KeychainStore.swift
ios/Dares/Groups/ ...   Challenges/ ... Voting/ ... Feed/ ... Leaderboard/ ... Camera/ ... Profile/
ios/Dares/Resources/    Assets.xcassets, Localizable.xcstrings, Dares.entitlements, Info.plist
ios/DaresTests/         decoding tests for every API model against sample JSON from this spec
```

---

## 5. v2 additions — Sunday League (approved 2026-11-04)

Visual + vocabulary: see DESIGN.md (v2) and design/screens.html. App display name: **Gauntlet**.

### Club forfeit
- `groups.forfeit TEXT` (≤ 60 chars, default `"Buys the round 🍺"`), editable by the owner (`PATCH /groups/:id {forfeit}`), returned in `Group.forfeit`.
  Display only (shown on the relegation line, the receipt and the Wooden Spoon award); never enforced.

### Matchweek numbers
- `Week.number` = 1-based index of the week since the group was created (first generated week = 1). Add to the `Week` shape.

### Title race (points curves)
`GET /groups/:id/stats/race` → cumulative points per member per closed+current week, season = since group creation.
```
{ weeks:[{id, number, startsAt}],
  series:[{user, cumulative:[int], perWeek:[int]}],   // arrays aligned with weeks
  me:{bestWeek:{number, points}, avgPerWeek:int, streak:int} }
```
Members who joined later get 0 for earlier weeks. Built from `point_events` only.

### Full-time receipt (weekly recap)
`GET /groups/:id/weeks/:weekId/receipt` (members only; current or past week) →
```
{ week:{id, number, startsAt, endsAt}, club:{name, forfeit},
  player:{user, rank, rankDelta, total},
  lines:[{label, points, struck:boolean}],   // one per challenge I submitted (accepted → points; rejected → 0, struck, label suffixed " · VAR: NO GOAL"), then bonuses (first_bonus, streak, weekly_winner)
  manOfTheMatch:User|null, woodenSpoon:User|null }
```
`GET /groups/:id/weeks?limit=10` → `{weeks:[Week]}` closed weeks, newest first, so the app can open older receipts.

### Monthly awards ("Awards night")
- Computed by the hourly cron on the **first Monday of each month at 19:00 group-local time** ("Awards night") for the previous calendar month: all weeks whose `starts_at` falls in that month (group tz). By then every such week is closed and past its vote deadline (the last week starting in month M always ends by the Sunday before the first Monday of M+1, deadline Monday 12:00); still assert `vote_deadline <= now` for each and skip the run (retry next hour) otherwise. Idempotent (`UNIQUE(group_id, month, award)`). Skip months with no closed weeks. Push "🏆 <Month> Awards is live" to members.
- Awards (ties → all tied members win; a member with 0 relevant activity can't win, except Wooden Spoon):
  | key | rule | bonus |
  |---|---|---|
  | `player_of_the_month` | most points in the month | **+50** (point_events kind `monthly_award`, week_id = last week of that month) |
  | `golden_boot` | most accepted submissions | 0 |
  | `toughest_ref` | most `approve=0` votes cast | 0 |
  | `comeback_kid` | biggest climb in all-time rank between start and end of month (min ▲1) | 0 |
  | `first_to_score` | most first_bonus events | 0 |
  | `wooden_spoon` | fewest points in the month (members present all month) | 0 |
- Table `monthly_awards(id, group_id, month TEXT 'YYYY-MM', award TEXT, user_id, value INTEGER, created_at)`; `point_events.kind` gains `'monthly_award'` (SQLite: rebuild the table in migration 0002 to widen the CHECK).
- `GET /groups/:id/awards?month=YYYY-MM` (default latest) →
  `{ month, awards:[{award, winners:[User], value, nominees:[{user, value}], stats?}] }` (nominees = top 3 by that metric; awards returned in ceremony order)
  `stats` is present only on `player_of_the_month`: `{points, goals, redCards, firstToScore, bestWeek}`
  for that month (goals = accepted submissions, redCards = rejected submissions, firstToScore = `first_bonus`
  events, bestWeek = max points in a single week of the month). Every other award omits `stats`.
  Ceremony order: `wooden_spoon, comeback_kid, toughest_ref, first_to_score, golden_boot, player_of_the_month`.
- `GET /groups/:id/awards/months` → `{months:['YYYY-MM']}` newest first.
- `GET /me/trophies` → `{trophies:[{groupId, groupName, month, award, value}]}` (trophy cabinet).

### AI challenge tone
DeepSeek prompt: challenges are "fixtures" for a Sunday-league-style friend club: fun, social, provable on camera, a few football-flavoured (e.g. "Score a Panenka", "Ref a kids' match") but most doable by non-footballers; safe, legal, consensual, non-humiliating. Fallback pool updated in the same tone.

---

## 6. v3 features — safety, banter, captain, house fixture (approved 2026-11-04)

All new tables in migration `0004_v3.sql`. All endpoints: auth + club membership checks, zod strict bodies, bound params, rate limits on every write.
Shape additions are additive (existing clients keep working).

### 6.1 House rules (App Store 1.2)
- `users.terms_accepted_at INTEGER NULL`; `POST /me/accept-terms` → `{user}`. `User` (for /me only) gains `termsAccepted: boolean`.
  Every write endpoint except `/auth/apple`, `/me` (GET/PATCH/DELETE) and `/me/accept-terms` returns `403 {error:{code:"terms_required"}}` until accepted.

### 6.2 Report, block, delete, remove
- `DELETE /submissions/:id` — submitter only, any status. Deletes the R2 object, votes, reactions, comments and the submission's point_events (challenge, first_bonus, captain). The first-finisher bonus is NOT reassigned. → `{ok:true}`
- `POST /submissions/:id/report` and `POST /comments/:id/report` — `{reason:'nudity'|'violence'|'harassment'|'dangerous'|'spam'|'other', note?:string≤200}`. One report per (reporter, target); reporting your own content → 400.
  The target is immediately hidden **for the reporter**. When distinct reporters ≥ `max(2, ceil(memberCount/3))` the target becomes `removed` (submission status `'removed'`; comment deleted) and is hidden for everyone; a removed submission's point_events are deleted. The club owner gets a push "A proof was removed after reports". Table `reports(id, reporter_id, target_type, target_id, group_id, reason, note, created_at, UNIQUE(reporter_id,target_type,target_id))`.
- Blocking: `POST /users/:id/block`, `DELETE /users/:id/block`, `GET /me/blocks` → `{users:[User]}`. Table `blocks(blocker_id, blocked_id, created_at, PK(blocker_id, blocked_id))`.
  For the blocker, the blocked user's submissions and comments are excluded from feed, `votes/pending`, comments and push notifications. Voting thresholds (`eligible_voters`) are unchanged. Blocking is one-way and silent.
- Owner removes a member: `POST /groups/:id/members/:userId/remove` (owner only, not self) → member deleted from the club, their pending submissions → `expired`, a row in `group_bans(group_id, user_id, created_at, PK)` so `POST /groups/join` with that club's code returns `403 banned`. `DELETE /groups/:id/members/:userId/ban` (owner) lifts it.
- `Submission.status` gains `'removed'` (never returned to clients except to the submitter, who sees it as removed).

### 6.3 Veto a fixture
- `POST /challenges/:id/veto` (toggle; current open week only; one per member). When vetoes ≥ `ceil(memberCount/2)` the fixture is **replaced** in place: a new challenge (DeepSeek, same difficulty, same position, fallback pool on failure) replaces it, the old challenge gets `vetoed_at`, its submissions → `expired` with their point_events removed. Max **2 replacements per club per week**; after that veto returns `409 veto_limit`.
  Response `{challenge:ChallengeWithMyStatus, replaced:boolean}`. Push "Fixture 03 was vetoed — new fixture is up".
- `ChallengeWithMyStatus` gains `vetoCount`, `vetoThreshold`, `myVeto:boolean`, `isNew:boolean` (replacement created < 24h ago), `isHouse:boolean`, `createdBy:User|null`, `isCaptain:boolean`.
  Table `vetoes(challenge_id, user_id, created_at, PK)`; `challenges` gains `vetoed_at`, `replaced_by`, `is_house`, `created_by`, `created_at`. Vetoed challenges are not returned by `/week`.

### 6.4 Notification preferences
- `GET /me/notification-prefs` / `PATCH /me/notification-prefs` → `{newWeek, voteNeeded, result, deadline, awards, banter}` booleans, default all true. Table `notification_prefs(user_id PK, …)`. Every push send checks the recipient's pref (banter = reactions + comments + house fixture announcements).

### 6.5 Reactions & comments ("banter")
- `POST /submissions/:id/reactions` `{emoji}` toggles my reaction; emoji ∈ `🔥 😂 🤡 🐐 😮 👏` (anything else → 400). One row per (user, submission, emoji). Table `reactions`.
- `Submission` gains `reactions:[{emoji, count, mine}]` (only the 6 allowed, zero-count omitted, fixed order above) and `commentCount`.
- `GET /submissions/:id/comments` → `{comments:[{id, user, text, createdAt, canDelete}]}` oldest first; `POST /submissions/:id/comments` `{text: 1–280 chars, trimmed}` → `{comment}`; `DELETE /comments/:id` (author or club owner). Table `comments(id, submission_id, user_id, text, created_at)`.
- Reactions/comments only on submissions of the requester's club that are not removed/hidden for them. Push to the submitter (banter pref), batched: at most one "banter" push per submission per 10 minutes.

### 6.6 Captain armband (×2)
- `PUT /groups/:id/week/captain` `{challengeId}` — choose one fixture of the current open week as my captain fixture. Can be changed until I have a submission (any status except rejected/expired) on the current captain fixture; then `409 captain_locked`. Table `captains(week_id, user_id, challenge_id, PK(week_id,user_id))`.
- When my submission on my captain fixture is accepted: extra point_event kind `'captain'` with points = the fixture's base points (first-finisher bonus is not doubled). Widen `point_events.kind` CHECK (table rebuild as in 0002).
- `Week` gains `myCaptainChallengeId: string|null`. Receipt line `"CAPTAIN ×2"` with the extra points. Race/awards totals include captain points automatically (ledger).

### 6.7 House fixture
- One extra member-written fixture per club per week. Allowed author: the previous week's Man of the Match (any tied winner, first come); in a club's first week, the owner. Window: until **Wednesday 23:59 group-local** of the current week.
- `POST /groups/:id/week/house-fixture` `{title 3–80, description ≤300, difficulty}` → `{challenge}`; position = last+1; `is_house=1`, `created_by`. Second attempt in the same week → `409 house_fixture_taken`. Vetoable like any fixture (a vetoed house fixture is NOT replaced). Push (banter) "Alex added a house fixture".
- `GET /groups/:id/week` gains `houseFixture:{allowed:boolean, deadline:number, author:User|null}`.

### 6.8 Invite link
- `GET /join/:code` → small HTML page (no JS required, CSP `default-src 'none'; style-src 'unsafe-inline'`) with the club name + member count, an "Open in Gauntlet" link `gauntlet://join/<code>` and a TestFlight placeholder link (env `TESTFLIGHT_URL`). Unknown code → generic 404 page (no enumeration difference in timing/content beyond 404). Rate limited per IP.
- `GET /.well-known/apple-app-site-association` → `{"applinks":{"details":[{"appIDs":["<APPLE_TEAM_ID>.com.mathys.dares"],"components":[{"/":"/join/*"}]}]}}` with `Content-Type: application/json` (env `APPLE_TEAM_ID`).
- `Group` gains `inviteUrl` (`<PUBLIC_BASE_URL>/join/<code>`, env `PUBLIC_BASE_URL`).
- iOS: associated domain `applinks:<API host>` + URL scheme `gauntlet`; both open a **join confirmation** screen (club name, members, "JOIN THE CLUB") — never auto-join.

### 6.9 Contract additions (2026-11-04, after v3 review)
- `GET /groups/preview/:code` (auth, terms not required, rate-limited with the same user+IP buckets as join) → `{group: Group}` using the normal Group JSON (no member list needed; `memberCount` included). Unknown or banned code → 404. Used by the iOS join confirmation screen. `GET /join/:code` stays HTML-only.
- `GET /groups/:id/bans` (owner only) → `{users:[User & {bannedAt:number}]}`.
- `Week.vetoesUsed: int` — replacements already used this week by the club (0–2).
