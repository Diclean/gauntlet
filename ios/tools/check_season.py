#!/usr/bin/env python3
"""Checks the seeded season of the demo against the numbers of the approved mock."""

MEMBERS = ["Alex", "Lee", "Jo", "Sam", "Mika"]


def report(season, weeks=12):
    names = list(season.keys())
    totals = {m: sum(season[m]) for m in names}
    print("totals   ", {m: totals[m] for m in MEMBERS})
    per_week = []
    for w in range(weeks):
        row = {m: season[m][w] for m in names}
        ranked = sorted(row.items(), key=lambda kv: (-kv[1], kv[0]))
        rank = {}
        for i, (m, p) in enumerate(ranked):
            rank[m] = 1 + sum(1 for _, q in row.items() if q > p)
        per_week.append((row, rank))
        winners = [m for m in names if rank[m] == 1 and row[m] > 0]
        print(f"MW{w+1:>2}", {m: row[m] for m in MEMBERS}, "winner:", winners or "—")
    wins = {m: 0 for m in names}
    for row, rank in per_week:
        for m in names:
            if rank[m] == 1 and row[m] > 0:
                wins[m] += 1
    print("wins     ", {m: wins[m] for m in MEMBERS})
    # the form: the last five matchweeks, W = accepted and top half (rank <= floor(n/2))
    top_half = len(names) // 2
    forms = {}
    for m in names:
        form = []
        for row, rank in per_week[-5:]:
            if row[m] == 0:
                form.append("L")
            elif rank[m] <= top_half:
                form.append("W")
            else:
                form.append("D")
        forms[m] = "".join(form)
    print("form     ", {m: forms[m] for m in MEMBERS})
    # the streak: the consecutive closed matchweeks with an acceptance and a top half
    streaks = {}
    for m in names:
        count = 0
        for row, rank in reversed(per_week[:-1]):
            if row[m] > 0 and rank[m] <= top_half:
                count += 1
            else:
                break
        streaks[m] = count
    print("streak   ", {m: streaks[m] for m in MEMBERS})
    # the club form: the consecutive closed matchweeks in which everybody scored
    club = 0
    for row, _ in reversed(per_week[:-1]):
        if all(row[m] > 0 for m in names):
            club += 1
        else:
            break
    print("club form", club)
    print("cumulative at MW11 and MW12")
    for m in MEMBERS:
        c11 = sum(season[m][:11])
        c12 = sum(season[m])
        print(f"   {m}: {c11} -> {c12}")
    print("avg over the last eight weeks:",
          {m: round(sum(season[m][-8:]) / 8, 1) for m in MEMBERS})


if __name__ == "__main__":
    season = {
        "Alex": [0, 0, 0, 0, 40, 30, 25, 45, 45, 35, 30, 115],
        "Lee": [40, 0, 0, 0, 40, 30, 35, 40, 40, 35, 20, 60],
        "Jo": [0, 0, 0, 0, 45, 25, 15, 25, 30, 40, 15, 35],
        "Sam": [0, 0, 0, 0, 35, 45, 30, 5, 40, 5, 25, 10],
        "Mika": [15, 0, 0, 0, 0, 10, 5, 15, 5, 5, 5, 0],
    }
    report(season)
