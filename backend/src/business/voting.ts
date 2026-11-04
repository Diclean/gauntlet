/**
 * Pure voting rules. No DB, no clock, no I/O.
 *
 * N = eligible_voters = group members excluding the submitter at submission
 * time. Accepted when approvals >= min(2, N); rejected when
 * rejections >= ceil(N / 2). The first threshold reached is final.
 *
 * N == 0 is the solo-group edge case: neither threshold can ever be reached
 * (the spec says such submissions cannot be accepted). We deliberately return
 * `pending` rather than auto-rejecting on zero rejections.
 */

export type SubmissionDecision = 'accepted' | 'rejected' | 'pending';

export interface VoteCounts {
  approvals: number;
  rejections: number;
  eligibleVoters: number;
}

export function requiredApprovals(eligibleVoters: number): number {
  const n = Math.max(0, Math.floor(eligibleVoters));
  return Math.min(2, n);
}

export function requiredRejections(eligibleVoters: number): number {
  const n = Math.max(0, Math.floor(eligibleVoters));
  if (n === 0) return Number.POSITIVE_INFINITY;
  return Math.ceil(n / 2);
}

export function decideSubmission(counts: VoteCounts): SubmissionDecision {
  const n = Math.max(0, Math.floor(counts.eligibleVoters));
  if (n === 0) return 'pending';

  const approvals = Math.max(0, Math.floor(counts.approvals));
  const rejections = Math.max(0, Math.floor(counts.rejections));

  if (approvals >= requiredApprovals(n)) return 'accepted';
  if (rejections >= requiredRejections(n)) return 'rejected';
  return 'pending';
}
