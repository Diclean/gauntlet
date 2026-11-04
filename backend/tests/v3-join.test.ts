import { beforeEach, describe, expect, it } from 'vitest';
import { env } from 'cloudflare:test';
import { app } from '../src';
import {
  GROUP,
  TOKEN_1,
  U1,
  auth,
  insertGroup,
  insertMember,
  insertSession,
  insertUser,
  resetDb,
} from './fixtures';

/** 6.8 invite link page, universal-link association file and Group.inviteUrl. */

const PUBLIC_BASE = 'https://dares.example.workers.dev';
const NASTY_NAME = '<script>alert("pwn")</script> & "The Lads"';

async function seed(): Promise<void> {
  await resetDb(env.DB);
  await insertUser(env.DB, U1, 'Alice', '🦊');
  await insertSession(env.DB, U1, TOKEN_1);
  await insertGroup(env.DB, GROUP, U1, 'ABC234', NASTY_NAME);
  await insertMember(env.DB, GROUP, U1);
}

beforeEach(seed);

describe('GET /join/:code', () => {
  it('renders the club name HTML-escaped with a strict CSP and deep link', async () => {
    const response = await app.request('/join/ABC234', {}, env);
    expect(response.status).toBe(200);
    expect(response.headers.get('content-type')).toContain('text/html');
    expect(response.headers.get('content-security-policy')).toBe(
      "default-src 'none'; style-src 'unsafe-inline'",
    );

    const html = await response.text();
    expect(html).toContain('&lt;script&gt;alert(&quot;pwn&quot;)&lt;/script&gt;');
    expect(html).not.toContain('<script>alert');
    expect(html).toContain('gauntlet://join/ABC234');
    expect(html).toContain('https://testflight.apple.com/join/TEST42');
    expect(html).toContain('1 member');
  });

  it('accepts a lowercase code and returns a generic 404 for unknown or malformed codes', async () => {
    const lower = await app.request('/join/abc234', {}, env);
    expect(lower.status).toBe(200);

    for (const code of ['ZZZZZZ', 'abc', 'AAA111']) {
      const response = await app.request(`/join/${code}`, {}, env);
      expect(response.status, code).toBe(404);
      expect(response.headers.get('content-security-policy')).toBe(
        "default-src 'none'; style-src 'unsafe-inline'",
      );
      const html = await response.text();
      expect(html).toContain('Club not found');
      expect(html).not.toContain('<script');
    }
  });
});

describe('apple-app-site-association', () => {
  it('serves the universal-link association JSON as application/json', async () => {
    const response = await app.request('/.well-known/apple-app-site-association', {}, env);
    expect(response.status).toBe(200);
    expect(response.headers.get('content-type')).toContain('application/json');
    const body = (await response.json()) as {
      applinks: { details: Array<{ appIDs: string[]; components: Array<Record<string, string>> }> };
    };
    expect(body.applinks.details[0]!.appIDs).toEqual(['TESTTEAM42.com.mathys.dares']);
    expect(body.applinks.details[0]!.components).toEqual([{ '/': '/join/*' }]);
  });
});

describe('Group.inviteUrl', () => {
  it('is built from PUBLIC_BASE_URL and the invite code', async () => {
    const response = await app.request('/groups', { headers: auth(TOKEN_1) }, env);
    expect(response.status).toBe(200);
    const body = (await response.json()) as { groups: Array<{ inviteUrl: string }> };
    expect(body.groups[0]!.inviteUrl).toBe(`${PUBLIC_BASE}/join/ABC234`);

    const single = await app.request(`/groups/${GROUP}`, { headers: auth(TOKEN_1) }, env);
    const singleBody = (await single.json()) as { group: { inviteUrl: string } };
    expect(singleBody.group.inviteUrl).toBe(`${PUBLIC_BASE}/join/ABC234`);
  });
});
