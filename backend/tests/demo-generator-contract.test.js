import test from 'node:test';
import assert from 'node:assert/strict';
import { parseDemoOptions } from '../src/demo/demo-config.js';
import { SeededRandom } from '../src/demo/random-seed.js';
import { loadEnvironment } from '../src/config/env.js';

test('demo options are deterministic and allow safe size overrides', () => {
  const first = parseDemoOptions(['--size=small', '--seed=2026', '--patients=12']);
  const second = parseDemoOptions(['--size=small', '--seed=2026', '--patients=12']);
  assert.deepEqual(first, second);
  assert.equal(first.config.patients, 12);
  const randomA = new SeededRandom(first.seed);
  const randomB = new SeededRandom(second.seed);
  assert.deepEqual(Array.from({ length: 12 }, () => randomA.int(100000)), Array.from({ length: 12 }, () => randomB.int(100000)));
});

test('enterprise generation requires an explicit confirmation flag', () => {
  assert.throws(() => parseDemoOptions(['--size=enterprise']), /confirm-enterprise/);
  assert.equal(parseDemoOptions(['--size=enterprise', '--confirm-enterprise=true']).size, 'enterprise');
});

test('production configuration rejects the demo generator', () => {
  const secure = 'a'.repeat(32);
  assert.throws(() => loadEnvironment({
    NODE_ENV: 'production', DATABASE_URL: 'https://database.example.test', JWT_ACCESS_SECRET: secure, JWT_REFRESH_SECRET: secure,
    ENABLE_DEMO_DATA_GENERATOR: 'true', ENABLE_LOCAL_DEVELOPMENT_AUTH: 'false',
  }), /Production cannot enable the demo data generator/);
});
