# Design guide — "bold & brut"

Working name: **Gauntlet** (won the name tournament; trademark clearance still to do — keep the name in one constant). Tagline idea: *"Pics or it didn't happen."*
Direction: sport fanzine / hazard tape / rubber stamps. Loud, high contrast, confident. The **proof photo/video is the hero**;
the chrome around it is black, white and one loud yellow.

## 1. Anti-AI-slop rules (hard rules)
Never: purple/indigo/blue gradients, gradient text, glows/halos, glassmorphism cards in content, sparkle ✨ icons,
emoji as UI icons (use SF Symbols; emoji only for the user's avatar), Inter/one-font-everything, centered hero screens,
grids of identical rounded cards with soft wide shadows, eyebrow labels above every heading, pulsing dots,
uniform fade-ins, bouncy easing on routine sheets, marketing copy ("Supercharge your friendships"), countdown guilt copy,
haptics on every tap, capture/action buttons inside the tab bar, disabled/hidden tabs, swipe-only voting.

## 2. Color tokens (light / dark)
| Token | Light | Dark | Use |
|---|---|---|---|
| `ink` | #0E0E0E | #F5F5F2 | text, 2px borders |
| `paper` | #FFFFFF | #0E0E0E | background |
| `paper2` | #F2F2EE | #1A1A1A | secondary surfaces |
| `brand` (hazard yellow) | #FFE14D | #FFE14D | primary CTA background (with `ink` label), "your turn" highlights, ONLY those |
| `approve` | #12B76A | #32D583 | approve swipe/stamp |
| `reject` | #F04438 | #F97066 | reject swipe/stamp |
| `streak` | #FF6B00 | #FF8A33 | streak flame + streak numbers only |
| difficulty | easy #12B76A, medium #FF6B00, hard #F04438 | same | difficulty tag |
Provide increased-contrast variants. No other colors. Neutrals around photos so photos carry color.

## 3. Type
- **Display**: *Anton* (OFL, Google Fonts; bundle it) — uppercase, tight tracking, for screen titles, challenge titles,
  stamps, podium numbers. Scaled with Dynamic Type via `.custom("Anton-Regular", size:, relativeTo:)`.
- **Body/UI**: SF Pro (system). Never Light/Thin weights.
- **Numbers** (points, ranks, timers): SF Mono / `.monospacedDigit()`.
- Max two families + mono.

## 4. Shape & surface
- Borders: 2pt solid `ink`. Corner radius: **6pt** for cards/buttons, **0** for photos inside cards (crisp), full-bleed in viewers.
- Shadows: hard offset only (`4pt, 4pt, 0 blur, ink`) on primary buttons and the vote card — never soft blurry shadows.
- Vary layouts: challenge list is a **numbered list** (big Anton numerals 01–05), not a card grid.
- Liquid Glass (iOS 26): only system nav/tab bar and floating controls over media (`.clear` + 35% dim over bright photos).
  Never in content.

## 5. Signature elements
- **Rubber stamps**: ACCEPTED (green) / REJECTED (red) / PENDING (ink outline) — Anton, rotated −8°, double border, slight ink texture.
  Stamp slams in with a short scale 1.4→1.0 + `.success`/`.error` haptic when a decision lands.
- **Receipt strip**: the weekly recap is styled like a thermal receipt (mono, dashed separators, totals line, "THANK YOU, COME AGAIN").
  Shareable as a portrait image.
- **Hazard tape**: diagonal yellow/black stripe used ONLY for the "deadline Sunday" banner in the final 24h.

## 6. Screens & key interactions
- **Tab bar** (4, single-word labels, filled SF Symbols): **Week** (list.number), **Vote** (hand.thumbsup.fill, badge = pending count),
  **Feed** (square.grid.2x2.fill → actually photo.stack.fill), **Board** (trophy.fill). Group switcher + settings in the nav bar.
- **Prove it** button lives on the challenge detail as a big yellow CTA → full-screen camera cover. Never in the tab bar.
- **Voting**: full-bleed proof card stack. **Swipe right = approve, left = reject**, card tilts with a green/red stamp fading in by drag
  distance; spring physics. Always also show two big buttons (✓ / ✗) below, plus `accessibilityActions`. **Undo** toast for 4 s.
  Tally ("1/2 approvals") hidden until you've voted.
- **Feed**: you must have posted ≥1 proof this week to see others' proofs unblurred (BeReal rule); others are blurred with
  "Post one to unlock".
- **Board**: weekly podium (asymmetric heights, reveal animation), then plain ranked list with movement (↑2 / ↓1), streak flames.
  Toggle Week / All time.
- **Streaks**: counted in weeks. Missed week shown as a cracked block, never a red X. Group streak shown on Board header.
- **Onboarding**: 3 punchy slides max → Sign in with Apple (official black button, first, ≥44pt) → name + emoji → create/join group.
  Ask for notifications **after the first proof** is posted, not at launch.
- **Empty states**: written like a friend talks. "Nobody's posted yet. Be the first, set the bar." /
  "Waiting on Sam and 2 others to join" + re-invite. Design late, rejected, offline, and error states too.

## 7. Copy voice
Short, friendly, a bit cheeky, never corporate. Examples: "Prove it." · "Approved. +25" · "Nah, try again." ·
"3 dares left. Sunday's coming." · "Your crew is waiting on your vote."

## 8. Motion & haptics
Springs (response 0.35, damping 0.75) for cards, stamps, podium. Routine sheets: system default, no bounce.
Haptics only for: vote committed (`.impact(.medium)`), accepted (`.success`), rejected (`.error`), streak milestone (`.success`).
Respect Reduce Motion (cross-fade instead).

## 9. Demo mode (in the iOS app)
A `DemoAPIClient` conforming to the same protocol as the real client, with an in-memory store seeded with: 2 groups,
5 members with emoji avatars, a current week of 5 challenges in mixed states, 6 pending proofs to vote on (bundled sample images),
feed history, leaderboard with streaks. Every action works locally (submit, vote → thresholds → points, join/create group, leave).
Toggle: "Try the demo" link on the sign-in screen + a `-demo` launch argument. Clearly labelled "DEMO" in the nav bar.
