import Foundation

/// Sample data so every screen can be previewed without a running server.
enum MockData {
    static let me = User(id: "user-me", displayName: "Alex", avatarEmoji: "🦊")
    static let friend = User(id: "user-sam", displayName: "Sam", avatarEmoji: "🐻")
    static let other = User(id: "user-jo", displayName: "Jo", avatarEmoji: "🐢")

    static let group = Group(
        id: "group-1",
        name: "Weekend Warriors",
        inviteCode: "K7M2PQ",
        challengesPerWeek: 5,
        theme: "Outdoors only",
        language: "en",
        timezone: "Europe/Paris",
        ownerId: me.id,
        memberCount: 6
    )

    static let members: [Member] = [
        Member(user: me, joinedAt: Date().addingTimeInterval(-86_400 * 30)),
        Member(user: friend, joinedAt: Date().addingTimeInterval(-86_400 * 12)),
        Member(user: other, joinedAt: Date().addingTimeInterval(-86_400 * 3)),
    ]

    static var week: Week {
        let calendar = Calendar.current
        let start = calendar.date(byAdding: .day, value: -3, to: Date()) ?? Date()
        let end = calendar.date(byAdding: .day, value: 4, to: start) ?? Date()
        let deadline = calendar.date(byAdding: .hour, value: 12, to: end) ?? Date()
        return Week(id: "week-1", startsAt: start, endsAt: end, voteDeadline: deadline, status: .open)
    }

    static let challenges: [Challenge] = [
        Challenge(
            id: "challenge-1",
            title: "Sunrise on a hill",
            description: "Catch the sun coming up from a hill or a rooftop before 8am.",
            difficulty: .easy,
            points: 10,
            position: 1,
            myStatus: .accepted,
            acceptedCount: 2
        ),
        Challenge(
            id: "challenge-2",
            title: "Cook a stranger's recipe",
            description: "Pick a recipe from a country you have never visited and cook it.",
            difficulty: .medium,
            points: 25,
            position: 2,
            myStatus: .pending,
            acceptedCount: 1
        ),
        Challenge(
            id: "challenge-3",
            title: "No-phone afternoon",
            description: "Spend three hours without your phone and film the view you earned.",
            difficulty: .hard,
            points: 50,
            position: 3,
            myStatus: .todo,
            acceptedCount: 0
        ),
    ]

    static let submissions: [Submission] = [
        Submission(
            id: "submission-1",
            challengeId: "challenge-1",
            challengeTitle: "Sunrise on a hill",
            user: friend,
            mediaUrl: "/media/sample",
            mediaType: .photo,
            caption: "Worth the 5am alarm.",
            status: .pending,
            approvals: 1,
            rejections: 0,
            eligibleVoters: 3,
            myVote: nil,
            createdAt: Date().addingTimeInterval(-3_600),
            decidedAt: nil
        ),
        Submission(
            id: "submission-2",
            challengeId: "challenge-2",
            challengeTitle: "Cook a stranger's recipe",
            user: other,
            mediaUrl: "/media/sample",
            mediaType: .video,
            caption: "Tried a Korean dish.",
            status: .accepted,
            approvals: 2,
            rejections: 0,
            eligibleVoters: 3,
            myVote: true,
            createdAt: Date().addingTimeInterval(-86_400),
            decidedAt: Date().addingTimeInterval(-86_000)
        ),
    ]

    static let leaderboard: [LeaderboardEntry] = [
        LeaderboardEntry(user: friend, points: 120, rank: 1, streak: 4),
        LeaderboardEntry(user: me, points: 85, rank: 2, streak: 2),
        LeaderboardEntry(user: other, points: 60, rank: 3, streak: 1),
    ]
}
