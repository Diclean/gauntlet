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
             approvals, rejections, eligibleVoters, myVote: boolean|null, createdAt, decidedAt}
```
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
