import assert from 'node:assert/strict';
import { mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { after, test } from 'node:test';

import { configFromEnv } from './database.js';

const directory = mkdtempSync(join(tmpdir(), 'mastodon-db-ca-'));
const caPath = join(directory, 'rds.pem');
const ca = 'test CA file contents';
writeFileSync(caPath, ca);
after(() => rmSync(directory, { recursive: true, force: true }));

test('verified DB field connections load the shared libpq CA file', () => {
  const config = configFromEnv(
    { DB_SSLMODE: 'verify-full', PGSSLROOTCERT: caPath },
    'production',
  );
  assert.deepEqual(config.ssl, { ca });
});

test('missing configured CA files fail instead of falling back to unverified TLS', () => {
  assert.throws(
    () =>
      configFromEnv(
        {
          DB_SSLMODE: 'verify-full',
          PGSSLROOTCERT: join(directory, 'missing'),
        },
        'production',
      ),
    { code: 'ENOENT' },
  );
});

test('disabled TLS and no-verify do not load a CA or change their semantics', () => {
  for (const [mode, expected] of [
    ['disable', false],
    ['no-verify', { rejectUnauthorized: false }],
  ]) {
    const config = configFromEnv(
      { DB_SSLMODE: mode, PGSSLROOTCERT: join(directory, 'missing') },
      'production',
    );
    assert.deepEqual(config.ssl, expected);
  }
});

test('existing configurations without a CA file are unchanged', () => {
  assert.deepEqual(
    configFromEnv({ DB_SSLMODE: 'prefer' }, 'production').ssl,
    {},
  );
  assert.equal(configFromEnv({}, 'production').ssl, undefined);
});

test('DATABASE_URL TLS also uses the shared CA file', () => {
  const config = configFromEnv(
    {
      DATABASE_URL: 'postgresql://localhost/mastodon?ssl=true',
      PGSSLROOTCERT: caPath,
    },
    'production',
  );
  assert.deepEqual(config.ssl, { ca });
});

test('an explicit DATABASE_URL CA takes precedence over PGSSLROOTCERT', () => {
  const config = configFromEnv(
    {
      DATABASE_URL: `postgresql://localhost/mastodon?sslrootcert=${encodeURIComponent(caPath)}`,
      PGSSLROOTCERT: join(directory, 'missing'),
    },
    'production',
  );
  assert.equal(config.ssl.ca, ca);
});

test('DATABASE_URL can explicitly disable TLS even if DB_SSLMODE enables it', () => {
  const config = configFromEnv(
    {
      DATABASE_URL: 'postgresql://localhost/mastodon?sslmode=disable',
      DB_SSLMODE: 'verify-full',
      PGSSLROOTCERT: join(directory, 'missing'),
    },
    'production',
  );
  assert.equal(config.ssl, false);
});
