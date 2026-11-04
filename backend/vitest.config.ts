import { defineConfig } from 'vitest/config';
import { cloudflareTest, readD1Migrations } from '@cloudflare/vitest-pool-workers';

export default defineConfig(async () => {
  const migrations = await readD1Migrations('migrations');

  return {
    plugins: [
      cloudflareTest({
        wrangler: { configPath: './wrangler.toml' },
        miniflare: {
          bindings: {
            APPLE_BUNDLE_ID: 'com.mathys.dares',
            APPLE_JWKS_URL: 'https://appleid.apple.com/auth/keys',
            TEST_MIGRATIONS: migrations,
          },
          d1Databases: ['DB'],
          r2Buckets: ['MEDIA'],
        },
      }),
    ],
    test: {
      setupFiles: ['./tests/setup.ts'],
      testTimeout: 20_000,
      hookTimeout: 20_000,
    },
  };
});
