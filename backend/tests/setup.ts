import { applyD1Migrations, env } from 'cloudflare:test';
import { beforeAll } from 'vitest';

// Each test worker gets the real migration SQL, so schema drift is caught.
beforeAll(async () => {
  await applyD1Migrations(env.DB, env.TEST_MIGRATIONS);
});
