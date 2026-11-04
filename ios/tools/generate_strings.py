#!/usr/bin/env python3
"""Generates the English String Catalog (Localizable.xcstrings) for the Dares app."""
import json
import os

STRINGS = {
    # Errors
    "error.invalid_url": "The server address is invalid.",
    "error.invalid_response": "The server returned an unexpected answer.",
    "error.missing_token": "You are signed out. Please sign in again.",
    "error.unauthorized": "You are not allowed to do that.",
    "error.decoding": "The server answer could not be read.",
    "error.apple_credential": "Apple did not return a usable credential.",
    "error.apple_nonce": "The sign in nonce is missing. Please try again.",
    "error.apple_identity_token": "Apple did not return an identity token.",
    # Difficulty & status
    "difficulty.easy": "Easy",
    "difficulty.medium": "Medium",
    "difficulty.hard": "Hard",
    "status.todo": "To do",
    "status.pending": "Pending",
    "status.accepted": "Accepted",
    "status.rejected": "Rejected",
    "status.expired": "Expired",
    # Common
    "alert.error.title": "Something went wrong",
    "alert.ok": "OK",
    "action.cancel": "Cancel",
    "action.create": "Create",
    "action.join": "Join",
    "action.done": "Done",
    "action.close": "Close",
    "countdown.closed": "closed",
    # Sign in
    "signin.title": "Weekly Dares",
    "signin.subtitle": "Every week your group gets a fresh list of challenges. Film the proof, let your friends vote, win the points.",
    "signin.legal": "Dares only works with Sign in with Apple. Your proof photos and videos stay private to your group.",
    # Profile setup
    "setup.title": "Pick your look",
    "setup.name.section": "Display name",
    "setup.name.placeholder": "How should we call you?",
    "setup.emoji.section": "Avatar",
    "setup.save": "Save",
    # Groups
    "groups.title": "Groups",
    "groups.section": "Your groups",
    "groups.add": "Add a group",
    "groups.create": "Create a group",
    "groups.join": "Join with a code",
    "groups.empty.title": "No group yet",
    "groups.empty.message": "Create a group and invite your friends, or join an existing one with an invite code.",
    "groups.empty.action": "Create a group",
    # Tabs
    "tab.challenges": "Challenges",
    "tab.vote": "Vote",
    "tab.feed": "Feed",
    "tab.leaderboard": "Leaderboard",
    # Group
    "group.title": "Group",
    "group.section.name": "Name",
    "group.name.placeholder": "Weekend Warriors",
    "group.section.challenges": "Challenges per week",
    "group.challenges_per_week": "Challenges per week",
    "group.section.theme": "Theme (optional)",
    "group.theme.placeholder": "Outdoors only",
    "group.theme.hint": "Sent to the AI when the weekly challenges are generated (200 characters max).",
    "group.section.advanced": "Language & time zone",
    "group.language": "Language",
    "language.english": "English",
    "language.french": "French (coming soon)",
    "group.timezone": "Time zone",
    "group.create.title": "New group",
    "group.settings.title": "Group settings",
    # Join
    "join.title": "Join a group",
    "join.section.code": "Invite code",
    "join.code.placeholder": "ABC123",
    "join.hint": "Ask a friend for the 6 character invite code shown in their group settings.",
    # Challenges
    "challenges.section": "This week",
    "challenges.week.label": "Week closes in",
    "challenge.title": "Challenge",
    "challenge.prove_it": "Prove it",
    "challenge.already_accepted": "Accepted — nice one!",
    "challenge.already_submitted": "Your proof is waiting for the votes.",
    "challenge.camera_only": "Proof must be filmed live with the camera.",
    "challenge.limits": "Photo or video of 30 seconds max. Captions are optional.",
    # Vote
    "vote.section": "Waiting for your vote",
    "vote.empty.title": "Nothing to vote on",
    "vote.empty.message": "When a friend submits proof you will be asked to judge it here.",
    "vote.approve": "Approve",
    "vote.reject": "Reject",
    "vote.progress": "%d/%d approvals · %d/%d rejections",
    "vote.solo_group": "Invite friends to get votes — nobody else is in this group yet.",
    # Feed
    "feed.empty.title": "The feed is empty",
    "feed.empty.message": "Proofs from your group will show up here.",
    # Leaderboard
    "leaderboard.scope": "Leaderboard scope",
    "leaderboard.this_week": "This week",
    "leaderboard.all_time": "All time",
    "leaderboard.empty.title": "No points yet",
    "leaderboard.empty.message": "Points appear as soon as a proof is accepted.",
    # Settings
    "settings.invite.section": "Invite code",
    "settings.share": "Share",
    "settings.invite.hint": "Share this code so friends can join your group.",
    "settings.invite.share_text": "Join my Dares group with the code %@",
    "settings.members.section": "Members",
    "settings.owner": "Owner",
    "settings.owner.note": "Group settings apply from the next week.",
    "settings.group.section": "Group settings",
    "settings.save": "Save changes",
    "settings.leave": "Leave group",
    "settings.leave.confirm.title": "Leave this group?",
    "settings.leave.confirm.message": "You will not see its challenges any more.",
    # Capture
    "capture.title": "Film your proof",
    "capture.challenge.title": "Challenge",
    "capture.open_camera": "Open camera",
    "capture.camera_unavailable": "Camera not available on Simulator",
    "capture.camera_unavailable_hint": "The Simulator has no camera. Use a real iPhone to film proof, or pick a sample image below.",
    "capture.use_sample": "Use sample image",
    "capture.camera_only_note": "Dares never imports from your photo library — proof has to be filmed live.",
    "capture.caption.placeholder": "Caption (optional)",
    "capture.uploading": "Uploading your proof…",
    "capture.retake": "Retake",
    "capture.upload": "Upload proof",
    "capture.encoding_failed": "The photo could not be encoded.",
    "capture.video_too_large": "The video is too large (50 MB max).",
    "capture.cancelled": "Capture cancelled.",
    # Media
    "media.failed": "The proof could not be loaded.",
    # Profile
    "profile.title": "Profile",
    "profile.section.identity": "You",
    "profile.name.placeholder": "Display name",
    "profile.save": "Save",
    "profile.sign_out": "Sign out",
    "profile.delete": "Delete account",
    "profile.delete.hint": "Deleting your account removes your profile and every proof you uploaded.",
    "profile.delete.confirm.title": "Delete your account?",
    "profile.delete.confirm.message": "This cannot be undone.",
    # Demo mode
    "demo.badge": "DEMO",
    "demo.badge.accessibility": "Demo mode",
    "demo.try": "Try the demo",
    "demo.try.hint": "Runs offline on sample data. Nothing is sent to a server.",
    "demo.exit": "Exit demo",
    "demo.exit.hint": "The demo runs on this device only. Leaving it brings back the real sign in.",
    "demo.join.hint": "Demo invite code: PL4XZ9",
}


def main():
    catalog = {"sourceLanguage": "en", "strings": {}, "version": "1.0"}
    for key, value in sorted(STRINGS.items()):
        catalog["strings"][key] = {
            "extractionState": "manual",
            "localizations": {
                "en": {
                    "stringUnit": {
                        "state": "translated",
                        "value": value,
                    }
                }
            },
        }

    path = os.path.join(
        os.path.dirname(os.path.abspath(__file__)), "..", "Dares", "Resources", "Localizable.xcstrings"
    )
    path = os.path.normpath(path)
    with open(path, "w", encoding="utf-8") as handle:
        json.dump(catalog, handle, indent=2, ensure_ascii=False)
        handle.write("\n")
    print("wrote", path, "with", len(STRINGS), "strings")


if __name__ == "__main__":
    main()
