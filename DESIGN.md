# Design guide — "Sunday League" (v2, approved 2026-11-04)

App name: **Gauntlet** (keep it in ONE constant; trademark clearance still to do).
Audience: young people, 5-a-side / Sunday-league friend groups, group-chat culture.
Concept: **each friend group is a club, each week is a matchweek, voting is VAR.** Everything speaks football.
Pixel reference: [`design/screens.html`](design/screens.html) — the approved mock of the 8 key screens. Match it.

## 1. Vocabulary (UI copy, English)
| Product concept | In-app word |
|---|---|
| Group | **Club** (crest + name, e.g. "SUNDAY LEAGUE FC") |
| Week | **Matchweek N** (N = week index since the club was created) |
| Week deadline | **Full time in 4D 22:55** |
| Challenge / dare | **Fixture** (numbered 01–10) |
| Submit proof | **Prove it** |
| Pending vote | **In VAR** |
| Vote screen | **VAR check** — buttons **Goal ⚽** / **No goal** |
| Accepted | **FT ✓** pill; big moment screen **GOAL! · VAR confirms** |
| Rejected | **Red ✕** pill (red card) ; **No goal** stamp |
| Not done | **To play** |
| Leaderboard | **The Table** — tabs **Matchweek N** / **Season** |
| Weekly winner | **Man of the Match** |
| Last place | **Wooden Spoon** — sits in the **Relegation zone — buys the round 🍺** (forfeit text editable per club in settings) |
| Streak | **Form** (last 5 weeks W/D/L squares) + 🔥 N-week streak |
| Group streak | **Club form — everyone scored 🔥 N weeks** |
| First-finisher bonus | **First to score +10** |
| Weekly recap | **Full-time receipt** |
Form squares: **W** = ≥1 accepted that week and finished top half, **D** = ≥1 accepted, **L** = none accepted.

## 2. Color tokens (no others)
| Token | Hex | Meaning |
|---|---|---|
| `ink` | #0B0B0C | dark backgrounds, text on light |
| `paper` | #FFFFFF | light backgrounds (The Table), text on dark |
| `card` (yellow card) | #FFD60A | primary CTA, "In VAR", leader row, current tab |
| `red` (red card) | #E5202E | rejected, No goal, relegation, badges |
| `pitch` | #00C46A | accepted, Goal, GOAL! screen background |
| `flame` | #FF6B00 | streak numbers only |
| `receipt` | #FBFBF7 | receipt paper only |
Dark-first: Matchday, VAR and Receipt screens are ink; The Table is paper; GOAL! is pitch green.

## 3. Type
- **Display: Anton** (OFL, bundle `Anton-Regular.ttf`) — UPPERCASE, for titles, fixture names, buttons, scores, numbers in the table. Use `.custom("Anton-Regular", size:, relativeTo:)` so Dynamic Type works.
- Fixture numbers 01–05: Anton, **outlined** (stroke only, no fill).
- **Labels / meta / receipt: monospace** (SF Mono / `.monospaced()`), UPPERCASE, letter-spaced (~0.1em), 8–10pt.
- Body text (captions): SF Pro. Never Light/Thin.

## 4. Shape & surface
- 2pt solid borders (white on dark, ink on light). **Square corners** on cards, pills and buttons (radius 0–2). Phone-level rounding only from the system.
- **Hard offset shadows** only (`4,4, blur 0`, white on dark / ink on light) on primary CTA, VAR card, polaroid, Club form box.
- Slight rotations are part of the identity: VAR card ±5°, Goal/No-goal buttons ±2°, GOAL! −5°, +25 sticker +8°, polaroid +4°, stamps −14°.
- Tab bar: 4 tabs **MATCH · VAR · FEED · TABLE**, mono 9pt labels, active tab in yellow (on dark) / ink (on light), red count badge on VAR. Floating capsule bar.

## 5. Screens (see design/screens.html)
1. **Matchday** (Week tab, ink): club crest + name + my avatar → "MATCHWEEK 12" (number in yellow) → 3-cell scoreboard (Full time in · You scored x/5 · Rank) → fixtures list (outlined number, Anton title, mono "DIFFICULTY · PTS", status pill) → sticky yellow **PROVE IT →** CTA (opens the next "to play" fixture, or the tapped one).
2. **VAR check** (Vote tab, ink): "VAR CHECK" + "● 2 OF 5" live chip → stacked cards, top card full-bleed proof, tilted; **drag right = Goal (green GOAL stamp fades in), left = No goal (red NO GOAL stamp)**, spring back if released early; who/time, fixture title, caption at the bottom on a dark gradient → "← NO GOAL · SWIPE · GOAL →" hint → two big buttons (accessibility + no-swipe users). 4 s **Undo** toast after a call. Tally hidden until you've called it.
3. **GOAL! moment** (full-screen cover when MY proof gets accepted, pitch green): huge rotated "GOAL!" + "VAR CONFIRMS", polaroid of the proof, yellow "+25" sticker, "CONFIRMED BY 🐢 JO + 🐧 LEE · 2/2 CALLS · DECISION FINAL", bonus chips (First to score +10, 🔥 streak), "BACK TO MATCHDAY". Success haptic + stamp slam animation. Rejected version: red background, "NO GOAL", "VAR OVERTURNED", "Prove it again" if the week is still open.
4. **The Table** (paper): "THE TABLE", segmented Matchweek N / Season, table columns # · PLAYER (emoji + Anton name + ▲▼ movement) · W · FORM (5 squares) · PTS; leader row yellow; dashed red **relegation line** above the last place with the club's forfeit text; **Club form** box at the bottom.
5. **Full-time receipt** (ink background, receipt paper with zig-zag top/bottom edges): club + "FULL-TIME RECEIPT" + matchweek dates + player; one line per fixture with points (rejected ones struck through with "VAR: NO GOAL"); bonuses; TOTAL in Anton; rank + movement; black **Man of the Match** bar; outlined **Wooden Spoon** bar; barcode; footer "NO REFUNDS ON RED CARDS. SCREENSHOT IT. SEND IT TO THE GC."; yellow **Share to the group chat ↗** (render the receipt with `ImageRenderer` → `ShareLink` image). Shown automatically on Monday for last week, and reachable from The Table.
Other screens (groups list = "Your clubs", create/join club, settings, profile, onboarding, feed, camera) reuse the same tokens: ink backgrounds, Anton titles, mono labels, square bordered rows, yellow primary CTA. Feed = grid of proofs with FT/VAR/RED pills, blurred until you've posted this matchweek.

### Screens 6–8 (approved, see design/screens.html)
6. **Title race** (inside the Table tab, ink, segmented ALL PLAYERS / ME VS RIVAL / PER WEEK): line chart of cumulative points per member per matchweek (`GET /groups/:id/stats/race`). Leader line yellow 3pt with a 6pt ink halo, my rival (the member directly above/below me) white 2pt, everyone else white at 27% opacity 2pt. Direct labels at line ends (emoji + Anton name, points for the top 2). Dashed vertical marker + "LEAD CHANGE" note where #1 changed. Drag on the chart → crosshair + white tooltip box with hard yellow shadow ("MW12 · +115 FOR ALEX"). Below: "YOUR POINTS PER MATCHWEEK" bars (my best week in yellow with its value), then 3 stat chips (Best week · Avg / week · Form 🔥). Use Swift Charts, styled to match. ME VS RIVAL = only my line + rival line. PER WEEK = grouped bars of points per week for me vs rival.
7. **Awards night** (full-screen, ink): opens from a push on the first Monday of the month at 19:00, from a banner on Matchday ("🏆 NOVEMBER AWARDS IS LIVE"), or from Table. Header "● LIVE FROM THE GROUP CHAT" + "NOVEMBER" / outlined "AWARDS"; 6-segment progress bar; a yellow envelope card (rotated −2°, flap + black "G" seal) showing "AWARD n OF 6", the award name, "AND THE WINNER IS…"; nominees row (top 3, emoji + name + value). Tap → envelope flap opens, card flips to the winner (spring + `.success` haptic), then "NEXT AWARD". Ceremony order: Wooden Spoon → Comeback Kid → Toughest Ref → First to Score → Golden Boot → Player of the Month.
8. **Player of the Month card** (yellow background, end of ceremony): black pennant-shaped card rotated −3° with white ribbon "PLAYER OF THE MONTH · NOV 2026", huge yellow points, big emoji avatar, Anton name, club + shirt number, 2×2 stat grid (Goals, Red cards, First to score, Best week); red "+50" sticker; "ALSO TONIGHT" list of the other 5 winners; buttons TROPHY CABINET / SHARE ↗ (ImageRenderer → ShareLink).
**Trophy cabinet** (Profile): grid of won trophies (icon square + award name + month + club), empty state "No silverware yet. Next ceremony: first Monday of the month."
Award icons: 🥄 Wooden spoon, 📈 Comeback kid, 🟨 Toughest ref, ⚡ First to score, 🥾 Golden boot, 🏆 Player of the month.

## 6. Anti-AI-slop rules (still hard rules)
No gradients except the dark scrim on photos, no glassmorphism in content, no soft blurry shadows, no rounded-card grids, no sparkle icons, no purple/blue, no SF-only typography, no marketing copy, no guilt countdown copy, no swipe-only voting, no action button inside the tab bar.

## 7. Motion & haptics
Springs (response 0.35, damping 0.7) for the VAR card, stamps (scale 1.4→1.0) and GOAL! entrance. Routine navigation: system default. Haptics only: call made (`.impact(.medium)`), GOAL (`.success`), NO GOAL (`.error`). Respect Reduce Motion.

## 8. Demo mode
Keep the existing DemoAPIClient; reseed copy to the new vocabulary (club "Sunday League FC", fixtures like "Score a Panenka", "Ref a kids' match", "Sunrise on a hill", "Cook a stranger's recipe", "Sunset swim"), and seed last week's receipt so screen 5 is reachable.

## 10. v3 UI (same tokens/type/shapes — no new colors)
- **House rules** (onboarding, after name/emoji, before clubs): ink screen, Anton "HOUSE RULES", numbered list (01 Real proof only, live camera. 02 No nudity, no hate, no dangerous stunts. 03 Bad content gets reported and removed. 04 Abusers get blocked and kicked.), checkbox square + yellow "I'M IN" CTA. Required to continue.
- **Proof "⋯" menu** (SF `ellipsis`, on VAR card, feed item, proof detail): Report proof → reason sheet (6 reasons as square bordered rows, optional note) → toast "Reported. It's hidden for you."; Block <name> (destructive confirm); Delete my proof (mine only, destructive confirm "Points for this fixture will be removed").
- **Banter** (feed item + proof detail, and on the VAR card only after you've called it): reaction row of square bordered chips "🔥 3" (mono count), my reactions filled yellow; a "BANTER · 4" chip opens a bottom sheet (ink, Anton "BANTER", comments as rows: emoji avatar + Anton name + mono time + SF Pro text; input bar with square border + yellow send button `arrow.up`). Long-press own comment / owner → Delete; others → Report.
- **Captain armband**: yellow square badge with Anton "C" on the fixture row's left of the pill; on fixture detail a bordered toggle "MAKE CAPTAIN · ×2" (locked state shows SF `lock.fill` + "LOCKED — YOU'VE PLAYED IT"). Matchday scoreboard third cell can show "CAPTAIN 03". GOAL! moment shows an extra chip "CAPTAIN ×2 +25". Receipt line "CAPTAIN ×2".
- **House fixture**: row pill "HOUSE" (white outline, SF `house.fill`) + mono "BY ALEX" under the title. When I'm allowed: a dashed-border row at the end of the list "+ ADD THE HOUSE FIXTURE · UNTIL WED 23:59" → sheet: title, description, difficulty segmented (EASY 10 / MEDIUM 25 / HARD 50), yellow "DROP IT".
- **Veto**: on fixture detail, red outlined button "VETO THIS FIXTURE" + mono progress "2 / 3 VETOES"; my veto filled red ("VETOED — TAP TO UNDO"). Replaced fixture shows a yellow "NEW" pill for 24h. When the weekly limit is hit: disabled with "2 VETOES USED THIS WEEK".
- **Club settings (owner)**: member rows get a "⋯" → "Remove from club" (destructive confirm); "Banned" section with "Unban".
- **Profile → Notifications**: 6 rows (Matchday drop, VAR calls, Your results, Sunday reminder, Awards night, Banter) with square toggles (ink/yellow). **Profile → Blocked**: list with Unblock.
- **Invite**: settings show the invite link + ShareLink ("Join Sunday League FC on Gauntlet: <link>"); join confirmation screen per SPEC 6.8.
