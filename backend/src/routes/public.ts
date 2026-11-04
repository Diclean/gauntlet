import { Hono } from 'hono';
import type { Context } from 'hono';
import type { AppEnv } from '../types';
import { first } from '../lib/db';
import { rateLimit } from '../middleware/rate-limit';

const app = new Hono<AppEnv>();

const CODE_PATTERN = /^[A-Z2-9]{6}$/u;
const CSP = "default-src 'none'; style-src 'unsafe-inline'";

const STYLE = `
  :root { color-scheme: light dark; }
  body { margin: 0; min-height: 100vh; display: grid; place-items: center;
         font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
         background: #0b0b0f; color: #f5f5f7; }
  main { width: min(88vw, 420px); padding: 32px 24px; border-radius: 20px;
         background: #17171d; box-shadow: 0 20px 60px rgba(0,0,0,.45); text-align: center; }
  h1 { font-size: 1.6rem; margin: 0 0 8px; }
  p { color: #a1a1aa; margin: 0 0 24px; }
  a { display: block; padding: 14px 18px; border-radius: 12px; margin: 10px 0;
      text-decoration: none; font-weight: 600; }
  a.primary { background: #f97316; color: #0b0b0f; }
  a.secondary { border: 1px solid #3f3f46; color: #f5f5f7; }
  .badge { font-size: 2rem; }
`;

function escapeHtml(value: string): string {
  return value
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

function page(title: string, bodyHtml: string): string {
  return `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>${escapeHtml(title)}</title>
  <style>${STYLE}</style>
</head>
<body>
  <main>${bodyHtml}</main>
</body>
</html>`;
}

function htmlResponse(c: Context<AppEnv>, html: string, status: 200 | 404): Response {
  const response = c.html(html, status);
  response.headers.set('Content-Security-Policy', CSP);
  response.headers.set('Cache-Control', 'no-store');
  return response;
}

function notFoundPage(): string {
  return page(
    'Club not found',
    `<div class="badge">⚽️</div>
     <h1>Club not found</h1>
     <p>This invite link is invalid or has expired.</p>`,
  );
}

/**
 * GET /join/:code — tiny public invite page (no JS). Unknown codes get the same
 * generic 404 page; the member count and club name are the only dynamic parts.
 */
app.get(
  '/join/:code',
  rateLimit({ bucket: 'join-page', capacity: 120, refillPerSecond: 2, by: 'ip' }),
  async (c) => {
    const raw = c.req.param('code').trim().toUpperCase();
    if (!CODE_PATTERN.test(raw)) {
      return htmlResponse(c, notFoundPage(), 404);
    }

    const group = await first<{ name: string; invite_code: string; member_count: number }>(
      c.env.DB.prepare(
        `SELECT g.name, g.invite_code,
                (SELECT COUNT(*) FROM group_members m WHERE m.group_id = g.id) AS member_count
           FROM groups g
          WHERE g.invite_code = ?`,
      ).bind(raw),
    );
    if (!group) return htmlResponse(c, notFoundPage(), 404);

    const code = escapeHtml(group.invite_code);
    const name = escapeHtml(group.name);
    const testflight = (c.env.TESTFLIGHT_URL ?? '').trim();
    const testflightLink = testflight
      ? `<a class="secondary" href="${escapeHtml(testflight)}">Get the app on TestFlight</a>`
      : '<a class="secondary" href="https://testflight.apple.com/">Get the app on TestFlight</a>';

    const html = page(
      `${name} — join the club`,
      `<div class="badge">⚽️</div>
       <h1>${name}</h1>
       <p>${group.member_count} member${group.member_count === 1 ? '' : 's'} · You have been invited to join this club.</p>
       <a class="primary" href="gauntlet://join/${code}">Open in Gauntlet</a>
       ${testflightLink}`,
    );
    return htmlResponse(c, html, 200);
  },
);

/**
 * GET /.well-known/apple-app-site-association — universal links for /join/*.
 */
app.get('/.well-known/apple-app-site-association', (c) => {
  const teamId = (c.env.APPLE_TEAM_ID ?? 'XXXXXXXXXX').trim() || 'XXXXXXXXXX';
  const body = {
    applinks: {
      details: [
        {
          appIDs: [`${teamId}.com.mathys.dares`],
          components: [{ '/': '/join/*' }],
        },
      ],
    },
  };
  return c.body(JSON.stringify(body), 200, {
    'Content-Type': 'application/json',
    'Cache-Control': 'public, max-age=3600',
  });
});

export default app;
