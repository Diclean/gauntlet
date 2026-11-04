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
| GET | `/me` | `{user}` |
| PATCH | `/me` | `{displayName?, avatarEmoji?}` |
| DELETE | `/me` | deletes account, submissions and R2 media |
| POST | `/devices` | `{apnsToken}` |
| GET | `/groups` | groups I belong to |
| POST | `/groups` | creates group and generates the current week immediately |
| POST | `/groups/join` | `{inviteCode}` |
| GET | `/groups/:id` | `{group, members}` |
| PATCH | `/groups/:id` | owner only; settings apply to the next generated week |
| POST | `/groups/:id/leave` | transfers ownership or deletes an empty group |
| GET | `/groups/:id/week` | current week + `ChallengeWithMyStatus[]` |
| GET | `/groups/:id/feed?cursor=` | newest first, 20 per page |
| GET | `/groups/:id/votes/pending` | others' pending proofs I haven't voted on, still-votable weeks, oldest first |
| GET | `/groups/:id/leaderboard?scope=week\|all` | `{entries:[{user,points,rank,streak}]}` |
| POST | `/challenges/:id/submissions` | multipart: `media`, `mediaType`, `caption?` |
| GET | `/submissions/:id` | members of the submission's group only |
| POST | `/submissions/:id/vote` | `{approve:boolean}` |
| GET | `/media/:key` | auth + membership checked, R2 stream, `Range` supported |

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
- Sunday ≥ 18:00 local, members with unaccepted challenges get one reminder push;
  `weeks.reminder_sent` is set atomically before sending to avoid retry spam.
- Sessions older than their expiry and rate-limit rows older than two days are
  cleaned up by the same cron.

## Security notes

- **Sign in with Apple only.** The identity token is verified against Apple's JWKS
  (`RS256`, `iss`, `aud`, `exp`, `iat` sanity, and the SHA-256 nonce binding). Keys
  are cached in-isolate for an hour and refreshed once on an unknown `kid`.
- Session tokens are 32 random bytes, base64url-encoded for the client and stored
  **only as SHA-256 hashes** in D1. Lifetime is 60 days.
- Every group/submission/media route re-checks membership. Non-members receive
  `403`, not data.
- All SQL uses bound parameters. Request bodies use strict zod schemas, so unknown
  fields are rejected. AI output is untrusted: parsed defensively, validated with
  zod, clamped, and topped up/fallback to a built-in safe pool.
- D1-backed token buckets rate-limit auth (per hashed IP), join, create, submit and
  vote. Raw IP addresses are never stored or logged.
- Logs contain error names/status counts only — no tokens, emails, names or media keys.

## Layout

```
backend/
  migrations/0001_init.sql     D1 schema + indexes
  src/
    index.ts                   Hono app + scheduled handler
    cron.ts                    hourly rollover/finalization/reminder job
    deepseek.ts                prompt, zod validation, fallback pools
    push.ts                    APNs ES256 JWT + device cleanup
    auth/                      Apple JWKS verification, hashed sessions
    middleware/                auth, validation, rate limiting, errors, waitUntil
    routes/                    auth, me, devices, groups, challenges, submissions, media
    business/                  PURE voting, points/bonuses/streaks, week-boundary math
    services/                  DB joins/serializers, weeks, account deletion
    lib/                       crypto, D1 helpers, typed API errors
  tests/                       voting, points, time, AI, authz/media, cron
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
