import { Hono } from 'hono';
import type { AppEnv, Env } from './types';
import { errorHandler, notFoundHandler } from './lib/errors';
import authRoutes from './routes/auth';
import meRoutes from './routes/me';
import deviceRoutes from './routes/devices';
import groupRoutes from './routes/groups';
import challengeRoutes from './routes/challenges';
import submissionRoutes from './routes/submissions';
import mediaRoutes from './routes/media';
import commentRoutes from './routes/comments';
import userRoutes from './routes/users';
import publicRoutes from './routes/public';
import { runCron } from './cron';

const app = new Hono<AppEnv>();

app.use('*', async (c, next) => {
  c.header('X-Content-Type-Options', 'nosniff');
  c.header('Referrer-Policy', 'no-referrer');
  c.header('X-Frame-Options', 'DENY');
  await next();
});

app.get('/health', (c) => c.json({ ok: true }));

// Public, unauthenticated: invite landing page + universal-link association.
app.route('/', publicRoutes);

app.route('/auth', authRoutes);
app.route('/me', meRoutes);
app.route('/devices', deviceRoutes);
app.route('/groups', groupRoutes);
app.route('/challenges', challengeRoutes);
app.route('/submissions', submissionRoutes);
app.route('/media', mediaRoutes);
app.route('/comments', commentRoutes);
app.route('/users', userRoutes);

app.onError(errorHandler);
app.notFound(notFoundHandler);

/**
 * Worker entry point. The HTTP API is Hono; the scheduled handler runs the
 * hourly rollover/finalization/reminder job.
 */
export default {
  fetch: app.fetch,
  async scheduled(
    controller: ScheduledController,
    env: Env,
    ctx: ExecutionContext,
  ): Promise<void> {
    const scheduledSeconds = Number.isFinite(controller.scheduledTime)
      ? Math.floor(controller.scheduledTime / 1000)
      : Math.floor(Date.now() / 1000);
    ctx.waitUntil(
      runCron(env, scheduledSeconds).catch((error: unknown) => {
        console.error('cron_failed', { name: error instanceof Error ? error.name : 'Error' });
      }),
    );
  },
} satisfies ExportedHandler<Env>;

export { app };
