import { describe, expect, it } from 'vitest';
import {
  decideSubmission,
  requiredApprovals,
  requiredRejections,
} from '../src/business/voting';

describe('voting thresholds', () => {
  it('never accepts or auto-rejects a solo group (N = 0)', () => {
    expect(requiredApprovals(0)).toBe(0);
    expect(requiredRejections(0)).toBe(Number.POSITIVE_INFINITY);
    expect(decideSubmission({ approvals: 0, rejections: 0, eligibleVoters: 0 })).toBe('pending');
    expect(decideSubmission({ approvals: 5, rejections: 0, eligibleVoters: 0 })).toBe('pending');
    expect(decideSubmission({ approvals: 0, rejections: 5, eligibleVoters: 0 })).toBe('pending');
  });

  it('N = 1: one member decides', () => {
    expect(requiredApprovals(1)).toBe(1);
    expect(requiredRejections(1)).toBe(1);
    expect(decideSubmission({ approvals: 0, rejections: 0, eligibleVoters: 1 })).toBe('pending');
    expect(decideSubmission({ approvals: 1, rejections: 0, eligibleVoters: 1 })).toBe('accepted');
    expect(decideSubmission({ approvals: 0, rejections: 1, eligibleVoters: 1 })).toBe('rejected');
  });

  it('N = 2: two approvals or one rejection', () => {
    expect(requiredApprovals(2)).toBe(2);
    expect(requiredRejections(2)).toBe(1);
    expect(decideSubmission({ approvals: 1, rejections: 0, eligibleVoters: 2 })).toBe('pending');
    expect(decideSubmission({ approvals: 2, rejections: 0, eligibleVoters: 2 })).toBe('accepted');
    expect(decideSubmission({ approvals: 1, rejections: 1, eligibleVoters: 2 })).toBe('rejected');
  });

  it('N = 3: two approvals or two rejections', () => {
    expect(requiredApprovals(3)).toBe(2);
    expect(requiredRejections(3)).toBe(2);
    expect(decideSubmission({ approvals: 1, rejections: 1, eligibleVoters: 3 })).toBe('pending');
    expect(decideSubmission({ approvals: 2, rejections: 1, eligibleVoters: 3 })).toBe('accepted');
    expect(decideSubmission({ approvals: 1, rejections: 2, eligibleVoters: 3 })).toBe('rejected');
  });

  it('N = 4: two approvals or two rejections', () => {
    expect(requiredApprovals(4)).toBe(2);
    expect(requiredRejections(4)).toBe(2);
    expect(decideSubmission({ approvals: 1, rejections: 1, eligibleVoters: 4 })).toBe('pending');
    expect(decideSubmission({ approvals: 2, rejections: 1, eligibleVoters: 4 })).toBe('accepted');
    expect(decideSubmission({ approvals: 1, rejections: 2, eligibleVoters: 4 })).toBe('rejected');
  });

  it('N = 7: two approvals or four rejections', () => {
    expect(requiredApprovals(7)).toBe(2);
    expect(requiredRejections(7)).toBe(4);
    expect(decideSubmission({ approvals: 1, rejections: 3, eligibleVoters: 7 })).toBe('pending');
    expect(decideSubmission({ approvals: 2, rejections: 3, eligibleVoters: 7 })).toBe('accepted');
    expect(decideSubmission({ approvals: 1, rejections: 4, eligibleVoters: 7 })).toBe('rejected');
  });

  it('treats the approval threshold as first when both are present', () => {
    expect(decideSubmission({ approvals: 2, rejections: 2, eligibleVoters: 4 })).toBe('accepted');
  });

  it('is safe with weird counts', () => {
    expect(decideSubmission({ approvals: -1, rejections: -1, eligibleVoters: 2 })).toBe('pending');
    expect(requiredApprovals(-4)).toBe(0);
    expect(requiredRejections(-4)).toBe(Number.POSITIVE_INFINITY);
  });
});
