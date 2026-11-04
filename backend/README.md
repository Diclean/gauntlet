# Dares backend — Cloudflare Worker

TypeScript Worker for **Dares**, the weekly friend-group challenge app. It owns sign-in,
groups, weekly challenge generation, camera-proof uploads, voting, the points ledger,
APNs pushes and media streaming.

- **Runtime:** Cloudflare Workers
- **Router / validation:** [Hono](https://hono.dev) + [zod](https://zod.dev)
- **Storage:** D1 (SQLite) + R2 (private proof media)
- **Scheduling:** Cron Trigger every hour (`0 * * * *`)
- **Tests:** vitest with `@cloudflare/vitest-pool-workers` (real workerd + real D1/R2 bindings)

The source of truth for product behaviour is [`../SPEC.md`](../SPEC.md). Do not change
`SPEC.md` or `ios/` from this package.

---

## Quick start (local)

Prerequisites: Node.js 22.12+ and npm.

```bash
cd backend
npm install

cp .dev.vars.example .dev.vars
# edit .dev.vars; DEEPSEEK/APNs keys are optional locally (fallbacks/skips)

npx wrangler d1 migrations apply DB --local
npm run dev
```

The Worker listens on <http://localhost:8787>. Health check:

```bash
curl http://localhost:8787/health
# {"ok":true}
```

`npm run dev` uses the local D1 database in `.wrangler/state` and a local R2 bucket.
`APPLE_BUNDLE_ID` defaults to `com.mathys.dares` for the iOS debug build.

### Useful scripts

```bash
npm run typecheck          # tsc --noEmit
npm test                   # vitest run (applies migrations itself in workerd)
npm run db:migrate:local   # npx wrangler d1 migrations apply DB --local
npm run db:migrate:remote  # npx wrangler d1 migrations apply DB --remote
npm run deploy             # npx wrangler deploy
```

> `.npmrc` sets `legacy-peer-deps=true` because npm 10.9's peer resolver crashes on the
> vitest 4 / vitest-pool-workers peer graph (`Cannot read properties of null (reading
> 'edgesOut')`). This is required for a plain `npm install` to work with this toolchain.

---

## Deploy

1. Create the resources (once):

   ```bash
   npx wrangler d1 create dares
   npx wrangler r2 bucket create dares-media
   ```

2. Put the returned D1 `database_id` into `wrangler.toml` (replacing the placeholder
   `00000000-0000-0000-0000-000000000000`). Update `name` / bucket name if desired.

3. Apply the schema remotely:

   ```bash
   npx wrangler d1 migrations apply DB --remote
   ```

4. Set secrets (never commit them):

   ```bash
   npx wrangler secret put DEEPSEEK_API_KEY
   npx wrangler secret put APNS_KEY_P8     # full .p8 contents
   npx wrangler secret put APNS_KEY_ID
   npx wrangler secret put APNS_TEAM_ID
   npx wrangler secret put APPLE_BUNDLE_ID # com.mathys.dares
   # optional: npx wrangler secret put APNS_ENV   # "sandbox" for dev builds
   ```

5. Deploy:

   ```bash
   npm run deploy
   ```

6. Point the iOS Release `API_BASE_URL` at the deployed
   `https://<worker>.<subdomain>.workers.dev` URL.

The hourly cron is deployed automatically with `[triggers] crons = ["0 * * * *"]`.
`wrangler dev` also runs the scheduled handler when you use the dashboard's trigger;
for manual testing use `npx wrangler dev --test-scheduled` and request
`/__scheduled?cron=0+*+*+*+*`.

### APNs

`src/push.ts` builds an ES256 JWT from `APNS_KEY_P8` (PKCS#8 `.p8`), caches it for
50 minutes, and posts to `api.push.apple.com` (or `api.sandbox.push.apple.com` when
`APNS_ENV=sandbox`). Device tokens returning `410 Unregistered` are deleted. Missing
secrets or any network failure is logged and skipped; push can never fail a request.

---

## API

All endpoints return JSON with camelCase keys. Errors are
`{"error":{"code":"...","message":"..."}}` with a meaningful HTTP status.
Everything except `GET /health` and `POST /auth/apple` requires
`Authorization: Bearer <session token>`.

| Method | Path | Notes |
|---|---|---|
| GET | `/health` | `{ok:true}` |
| POST | `/auth/apple` | `{identityToken, nonce, displayName?}` → `{token, user}` |
| POST | `/auth/logout` | auth required; deletes the presented session → `{ok:true}` |
| GET | `/me` | `{user, termsAccepted}` |
| PATCH | `/me` | `{displayName?, avatarEmoji?}` |
| DELETE | `/me` | deletes account, submissions and R2 media |
| POST | `/me/accept-terms` | `{user}`; required before any other write |
| GET | `/me/notification-prefs` | `{newWeek,voteNeeded,result,deadline,awards,banter}` (all default on) |
| PATCH | `/me/notification-prefs` | partial boolean update, returns the full set |
| GET | `/me/blocks` | `{users:[User]}` |
| POST | `/users/:id/block` | one-way, silent block |
| DELETE | `/users/:id/block` | lift a block |
| POST | `/devices` | `{apnsToken}` |
| GET | `/groups` | groups I belong to |
| POST | `/groups` | creates group and generates the current week immediately |
| POST | `/groups/join` | `{inviteCode}` |
| GET | `/groups/preview/:code` | auth required, terms not required; `{group}` (normal Group JSON) for the join confirmation screen; unknown/banned code → 404 |
| GET | `/groups/:id` | `{group, members}`; `Group.forfeit` included |
| PATCH | `/groups/:id` | owner only; `{name?, challengesPerWeek?, theme?, language?, timezone?, forfeit?}` (challenge settings apply to the next generated week) |
| POST | `/groups/:id/leave` | transfers ownership or deletes an empty group |
| POST | `/groups/:id/members/:userId/remove` | owner only; removes + bans a member, expires their pending proofs |
| DELETE | `/groups/:id/members/:userId/ban` | owner only; lifts the ban |
| GET | `/groups/:id/bans` | owner only; `{users:[{...User,bannedAt}]}` newest ban first |
| GET | `/groups/:id/week` | current week + `ChallengeWithMyStatus[]` + `houseFixture` |
| PUT | `/groups/:id/week/captain` | `{challengeId}`; locked once I submitted on my captain fixture |
| POST | `/groups/:id/week/house-fixture` | `{title 3-80, description?, difficulty}`; author + Wednesday deadline rules |
| GET | `/groups/:id/weeks?limit=10` | `{weeks:[Week]}` closed weeks newest first, matchweek `number` included |
| GET | `/groups/:id/weeks/:weekId/receipt` | full-time receipt (current or past week, members only) |
| GET | `/groups/:id/stats/race` | `{weeks, series, me}` cumulative title-race curves |
| GET | `/groups/:id/awards?month=YYYY-MM` | `{month, awards}`; defaults to the latest stored month |
| GET | `/groups/:id/awards/months` | `{months:['YYYY-MM']}` newest first |
| GET | `/groups/:id/feed?cursor=` | newest first, 20 per page |
| GET | `/groups/:id/votes/pending` | others' pending proofs I haven't voted on, still-votable weeks, oldest first |
| GET | `/groups/:id/leaderboard?scope=week\|all` | `{entries:[{user,points,rank,streak}]}` |
| GET | `/me/trophies` | `{trophies:[{groupId,groupName,month,award,value}]}` |
| POST | `/challenges/:id/submissions` | multipart: `media`, `mediaType`, `caption?` |
| POST | `/challenges/:id/veto` | toggle my veto; replaces the fixture at the threshold (max 2/week) |
| GET | `/submissions/:id` | members of the submission's group only |
| DELETE | `/submissions/:id` | submitter only; removes media, votes, reactions, comments and its ledger rows |
| POST | `/submissions/:id/vote` | `{approve:boolean}` |
| POST | `/submissions/:id/report` | `{reason, note?}`; hides for me, removes at the club threshold |
| POST | `/submissions/:id/reactions` | `{emoji}` from 🔥 😂 🤡 🐐 😮 👏 (toggle) |
| GET | `/submissions/:id/comments` | `{comments:[{id,user,text,createdAt,canDelete}]}` oldest first |
| POST | `/submissions/:id/comments` | `{text 1-280}` (trimmed) |
| DELETE | `/comments/:id` | comment author or club owner |
| POST | `/comments/:id/report` | same moderation threshold as proofs |
| GET | `/media/:key` | auth + membership checked, R2 stream, `Range` supported |
| GET | `/join/:code` | public HTML invite page (strict CSP, escaped club name) |
| GET | `/.well-known/apple-app-site-association` | universal links for `/join/*` |

### Uploads

- `mediaType=photo`: JPEG/HEIC/HEIF, max **10 MB**.
- `mediaType=video`: MP4/MOV, max **50 MB** (the 30-second limit is enforced by the
  iOS camera picker; server-side duration parsing is intentionally out of scope).
- R2 keys are random UUIDs (`<submissionId>.<ext>`), never user input.
- One `pending` submission per `(user, challenge)` is enforced by a partial unique
  index; accepted challenges cannot be resubmitted, rejected/expired ones can while
  the week is open.
- `eligible_voters` is captured at submission time as `memberCount - 1`.

### Media streaming

`GET /media/:key` checks the submission's group membership **before** touching R2.
Responses are `Cache-Control: private, no-store` and support a single byte range
(`bytes=start-end` and `bytes=-suffix`), returning `206` with `Content-Range`, or
`416` with `Content-Range: bytes */size` for an unsatisfiable range.

### v2 "Sunday League" shapes

- `Group.forfeit`: display-only club forfeit, ≤ 60 chars, default `"Buys the round 🍺"`.
  Owner-editable through `PATCH /groups/:id`; never enforced.
- `Week.number`: 1-based matchweek index in the group, assigned `max + 1` on creation
  (migration 0002 backfills existing weeks in `starts_at` order).
- Race:
  `{weeks:[{id,number,startsAt}], series:[{user,cumulative:[int],perWeek:[int]}],
  me:{bestWeek:{number,points},avgPerWeek:int,streak:int}}`. Arrays are aligned with
  `weeks`; late joiners get `0` for earlier matchweeks. Built from `point_events` only.
- Receipt:
  `{week:{id,number,startsAt,endsAt,vetoesUsed}, club:{name,forfeit},
  player:{user,rank,rankDelta,total}, lines:[{label,points,struck}],
  manOfTheMatch:User|null, woodenSpoon:User|null}`. One line per challenge the caller
  submitted; rejected/expired lines are struck and suffixed `" · VAR: NO GOAL"`, then
  aggregated `first_bonus` / `streak` / `weekly_winner` bonus lines.
- Awards:
  `{month, awards:[{award,winners:[User],value,nominees:[{user,value}]}]}` in ceremony
  order `wooden_spoon, comeback_kid, toughest_ref, first_to_score, golden_boot,
  player_of_the_month`. `GET /me/trophies` returns every won award across groups.
- `GET /groups/:id/weeks` is wrapped as `{weeks:[Week]}` for consistency with every
  other list endpoint (`{groups}`, `{items}`, `{entries}`) and returns closed weeks
  only; the current week is served by `GET /groups/:id/week`.

### v3 shapes (safety, banter, captain, house fixture)

- **Terms gate:** `users.terms_accepted_at`; every write except `/me` (GET/PATCH/DELETE)
  and `/me/accept-terms` returns `403 {"error":{"code":"terms_required"}}` until accepted.
- **Moderation:** reports are one per reporter/target; a target is hidden for its reporter
  immediately and removed for everyone at `max(2, ceil(memberCount/3))` distinct reporters.
  Removal deletes the submission's `challenge`/`first_bonus`/`captain` ledger rows.
  Blocks are one-way and never change `eligible_voters`. The owner can remove + ban a
  member; banned users get `403 banned` from `POST /groups/join` until unbanned.
- **Veto:** `ChallengeWithMyStatus` adds `vetoCount`, `vetoThreshold`, `myVeto`, `isNew`,
  `isHouse`, `createdBy`, `isCaptain`. A vetoed fixture is replaced in place (same
  difficulty/position) at `ceil(memberCount/2)` vetoes, at most twice per club per week;
  a vetoed house fixture is simply withdrawn. `Week.vetoesUsed` (0–2) is the number of
  replacements already used this week, present on every `Week` JSON (week endpoint,
  weeks list and receipt).
- **Join preview:** `GET /groups/preview/:code` (auth, terms not required) returns the
  normal `Group` JSON (`memberCount` and `inviteUrl` included) for the iOS join
  confirmation screen. Unknown, malformed and banned-caller codes all return
  `404 not_found`; it shares the join user + IP rate-limit buckets. `GET /join/:code`
  stays HTML-only.
- **Ban list:** `GET /groups/:id/bans` (owner only) returns
  `{users:[{...User, bannedAt}]}` newest ban first.
- **Reactions/comments:** `Submission` adds `reactions:[{emoji,count,mine}]` (six fixed
  emojis, zero-count omitted) and `commentCount`. Banter pushes are throttled to one per
  submission per 10 minutes and respect the `banter` notification pref.
- **Captain:** `Week.myCaptainChallengeId`; accepted captain-fixture proofs earn an extra
  `captain` point event equal to the fixture's base points (receipt line `CAPTAIN ×2`).
- **House fixture:** one member-written fixture per club per week, authored by the previous
  week's Man of the Match (the owner in the club's first week) until Wednesday 23:59
  group-local. `GET /groups/:id/week` adds `houseFixture:{allowed,deadline,author}`.
- **Invite link:** `Group.inviteUrl = <PUBLIC_BASE_URL>/join/<inviteCode>`.

---

## Week + cron semantics

- Weeks are Monday 00:00:00 → Sunday 23:59:59 in the group's IANA timezone. All
  boundary math uses `Intl.DateTimeFormat` (DST-aware), never the host timezone.
- On the first cron tick of a new local Monday:
  - prior open weeks are marked `closed`,
  - the current week is inserted (`UNIQUE(group_id, starts_at)` makes this
    idempotent) and its challenges are generated with DeepSeek (or the fallback pool),
  - `weeks.status` is `closed` from that point, but **votes remain open until**
    `vote_deadline` (Monday 00:00 + 12h) so Sunday-night proofs can still be judged.
- Weekly-winner (+50, ties all win) and streak points (`+5 × min(streak, 10)` for
  streak ≥ 2) are awarded when the vote deadline passes, not at Monday 00:00, so
  grace-period votes are counted. `point_events` has a unique expression index, so
  repeated cron ticks cannot double-award.
- Pending submissions are expired after their week's `vote_deadline`.
- **Monthly awards:** on the **first Monday of the month at/after 19:00 group-local**,
  the previous calendar month's awards are computed from **all** weeks whose
  `starts_at` falls in that month — including the last one (e.g. Mon Oct 27 → Sun
  Nov 2) whose vote deadline is the following Monday 12:00. Every one of those weeks
  must be closed and past `vote_deadline`; otherwise the run is skipped and the next
  hourly tick retries. A `monthly_award_runs(group_id, month)` guard is inserted in
  the same D1 batch as the award and ledger rows, making the run truly one-shot per
  group/month even for a zero-award month or a later data change. Ties create one
  `monthly_awards` row per winner; Player of the Month winners also get a +50
  `point_events` row (`kind = 'monthly_award'`) on the month's last week. A single
  "🏆 <Month> Awards is live" push is sent only when the guard row is newly inserted
  and the month actually has awards; zero-award runs record the guard without a push.
  Push failures never fail the cron.
- Sunday ≥ 18:00 local, members with unaccepted challenges get one reminder push;
  `weeks.reminder_sent` is set atomically before sending to avoid retry spam.
- Sessions older than their expiry and rate-limit rows older than two days are
  cleaned up by the same cron.

## Security notes

- **Sign in with Apple only.** The identity token is verified against Apple's JWKS
  (`RS256`, `iss`, `aud`, `exp`, `iat` sanity, and the SHA-256 nonce binding). Keys
  are cached in-isolate for an hour and refreshed once on an unknown `kid`. Each
  verified nonce is burned in `used_nonces` (SHA-256 of the raw client nonce,
  i.e. the token's `nonce` claim, with expiry = token `exp`), so a captured
  token cannot be replayed; expired rows are purged by the hourly cron.
- Session tokens are 32 random bytes, base64url-encoded for the client and stored
  **only as SHA-256 hashes** in D1. Lifetime is 60 days. `POST /auth/logout`
  deletes exactly the presented session row.
- Every group/submission/media route re-checks membership. Non-members receive
  `403`, not data.
- All SQL uses bound parameters. Request bodies use strict zod schemas, so unknown
  fields are rejected. JSON bodies are capped at 64 KB both by declared
  `Content-Length` and by a streaming byte counter before `JSON.parse`. AI output
  is untrusted: parsed defensively, validated with zod, clamped, and
  topped up/fallback to a built-in safe pool.
- Uploads require a numeric `Content-Length` (411 otherwise) and are rejected
  before `formData()` when the declared size exceeds the 50 MB video cap; the
  post-buffer file size check remains. Members are limited to 30 submissions per
  rolling 24 hours (`429 upload_quota`).
- D1-backed token buckets rate-limit auth (per hashed IP), join (per user **and**
  per IP), create, submit and vote. Each refill+debit is one conditional SQL
  statement (`RETURNING tokens`), so concurrent requests cannot overspend a
  bucket. Only Cloudflare's `cf-connecting-ip` is trusted; `x-forwarded-for` is
  never read and raw addresses are never stored or logged.
- Proof media is deleted from R2 (best-effort, after the D1 change commits) on
  every terminal transition: rejected by votes, expired by cron/veto/member
  removal, removed by reports, submitter deletion, and account/group deletion.
- **APNs token rebinding:** `devices.apns_token` is the primary key, so one device
  token maps to at most one user row. `POST /devices` is authenticated and
  deliberately re-binds an existing token to the current user (the device just
  proved who owns it); `push.ts` selects tokens per recipient user, so a token is
  never delivered to two users.
- Logs contain error names/status counts only — no tokens, emails, names or media keys.

## Layout

```
backend/
  migrations/0001_init.sql     D1 schema + indexes
  migrations/0002_v2.sql       forfeit, matchweek numbers, monthly awards, widened ledger
  migrations/0003_monthly_award_runs.sql  one-shot (group, month) awards guard
  migrations/0004_v3.sql       terms, reports/blocks/bans, vetoes, prefs, banter, captains
  migrations/0005_security.sql one first_bonus per challenge, one-shot Apple nonces
  src/
    index.ts                   Hono app + scheduled handler
    cron.ts                    hourly rollover/finalization/reminder/awards job
    deepseek.ts                fixtures prompt, zod validation, fallback pools
    push.ts                    APNs ES256 JWT + device cleanup
    auth/                      Apple JWKS verification, hashed sessions
    middleware/                auth, validation, rate limiting, errors, waitUntil
    routes/                    auth, me, devices, groups, challenges, submissions, media, comments, users, public
    business/                  PURE voting, points, race, awards, receipt, week/month math
    services/                  DB joins/serializers, weeks, fixtures, moderation, banter, stats, awards, account deletion
    lib/                       crypto, D1 helpers, typed API errors
  tests/                       voting, points, time, AI, authz/media, cron, v2 race/awards/receipt
```

---

## Known deviations / TODOs

1. **Weekly winner/streak timing:** the spec's cron section says "close the previous
   week and award" at Monday 00:00, while votes are allowed until Monday 12:00. To
   make grace-period votes count, this Worker closes the week at rollover and awards
   winner/streak at the vote deadline. See `src/cron.ts`.
2. **HEIC:** HEIC/HEIF photos are accepted and stored as-is. The iOS client compresses
   capture to JPEG (quality 0.8, 2048 px) before upload, so no server-side transcode
   is needed. If a client uploads HEIC directly, it is served as `image/heic`.
3. **Video duration:** the 30-second cap is enforced by `UIImagePickerController` on
   the client; the Worker enforces the 50 MB size cap and MP4/MOV content types.
4. **Group timezone edits:** `PATCH /groups/:id` updates settings immediately for the
   next generated week. Changing the timezone near a rollover can make the next cron
   tick compute a different local Monday; the API never mutates an existing week.
5. `@cloudflare/vitest-pool-workers` is deprecated upstream in favour of
   `@cloudflare/vitest-plugin`; it is kept here because it is the spec-requested
   test runner. The installed version works with vitest 4 via its `cloudflareTest()`
   plugin API.
6. APNs is implemented but not integration-tested: tests do not have a real `.p8`
   key. Missing-secret and token-cleanup paths are exercised by the non-fatal design.
7. **Monthly award ties:** SPEC §5 asks for `UNIQUE(group_id, month, award)` *and*
   "ties → all tied members win". Those conflict for a row-per-winner table, so
   `monthly_awards` uses `UNIQUE(group_id, month, award, user_id)`, which still makes
   repeated cron ticks idempotent and can represent every tied winner.
8. **Award nominees:** the spec's table stores winners only. `GET /groups/:id/awards`
   recomputes the top-3 nominees from current data (falling back to the winners if the
   month's context is no longer available).
9. **Award months with zero awards:** `GET /groups/:id/awards/months` lists months
   from `monthly_awards`, so a month whose run recorded no awards is not offered as
   an awards page even though its `monthly_award_runs` guard exists.
