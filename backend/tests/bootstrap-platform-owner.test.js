import assert from 'node:assert/strict';
import test from 'node:test';
import {
  bootstrapPlatformOwner,
  PlatformOwnerAlreadyExistsError,
  safeBootstrapErrorMessage,
  validateBootstrapInput,
} from '../src/database/bootstrap-platform-owner.js';
import { verifyPassword } from '../src/security/passwords.js';

const validInput = {
  name: 'Primary Platform Owner',
  email: 'OWNER@AVERA.EXAMPLE',
  password: 'SecureBootstrap#2026',
};

function createPool({ existingOwner = null } = {}) {
  const calls = [];
  const client = {
    async query(sql, parameters = []) {
      calls.push({ sql, parameters });
      if (sql.includes("account_type = 'PlatformOwner'")) {
        return { rows: existingOwner ? [existingOwner] : [] };
      }
      if (sql.includes('INSERT INTO users')) {
        return {
          rows: [
            {
              user_id: 'c9f034c0-17bb-48f8-a8d2-8dfa2e649117',
              full_name: parameters[0],
              email: parameters[1],
              account_type: 'PlatformOwner',
              status: 'Active',
              clinic_id: null,
            },
          ],
        };
      }
      return { rows: [] };
    },
    release() {},
  };

  return {
    calls,
    pool: {
      async connect() {
        return client;
      },
    },
  };
}

test('first bootstrap creates an active tenantless Platform Owner and audit event', async () => {
  const harness = createPool();
  const owner = await bootstrapPlatformOwner({
    pool: harness.pool,
    ...validInput,
  });

  assert.equal(owner.account_type, 'PlatformOwner');
  assert.equal(owner.status, 'Active');
  assert.equal(owner.clinic_id, null);
  assert.equal(owner.email, 'owner@avera.example');
  assert.equal(
    harness.calls.filter((call) => call.sql.includes('INSERT INTO users')).length,
    1,
  );
  assert.equal(
    harness.calls.filter((call) => call.sql.includes('INSERT INTO audit_logs')).length,
    1,
  );
  assert.equal(harness.calls.some((call) => call.sql === 'COMMIT'), true);
});

test('bootstrap stores a bcrypt hash and never passes plaintext to persistence', async () => {
  const harness = createPool();
  await bootstrapPlatformOwner({
    pool: harness.pool,
    ...validInput,
  });

  const userInsert = harness.calls.find((call) =>
    call.sql.includes('INSERT INTO users'),
  );
  assert.ok(userInsert);
  const storedHash = userInsert.parameters[2];
  assert.notEqual(storedHash, validInput.password);
  assert.equal(await verifyPassword(validInput.password, storedHash), true);

  for (const call of harness.calls) {
    assert.equal(call.sql.includes(validInput.password), false);
    assert.equal(JSON.stringify(call.parameters).includes(validInput.password), false);
  }
});

test('second bootstrap attempt is rejected and creates nothing', async () => {
  const harness = createPool({
    existingOwner: { user_id: '6d32eb98-c169-4f21-a108-e094cdd4da9e' },
  });

  await assert.rejects(
    bootstrapPlatformOwner({
      pool: harness.pool,
      ...validInput,
    }),
    PlatformOwnerAlreadyExistsError,
  );
  assert.equal(
    harness.calls.some((call) => call.sql.includes('INSERT INTO users')),
    false,
  );
  assert.equal(
    harness.calls.some((call) => call.sql.includes('INSERT INTO audit_logs')),
    false,
  );
  assert.equal(harness.calls.some((call) => call.sql === 'ROLLBACK'), true);
});

test('invalid bootstrap passwords are rejected before opening a transaction', async () => {
  const invalidPasswords = [
    'Short#1Aa',
    'lowercaseonlypassword1#',
    'UPPERCASEONLYPASSWORD1#',
    'MissingNumberPassword#',
    'MissingSymbolPassword1',
  ];

  for (const password of invalidPasswords) {
    let connectionAttempted = false;
    await assert.rejects(
      bootstrapPlatformOwner({
        pool: {
          async connect() {
            connectionAttempted = true;
            throw new Error('Database must not be reached.');
          },
        },
        ...validInput,
        password,
      }),
      /password/i,
    );
    assert.equal(connectionAttempted, false);
  }
});

test('bootstrap validates and normalizes the name and email', () => {
  const input = validateBootstrapInput({
    ...validInput,
    name: '  Primary Platform Owner  ',
    email: '  OWNER@AVERA.EXAMPLE  ',
  });
  assert.equal(input.name, 'Primary Platform Owner');
  assert.equal(input.email, 'owner@avera.example');

  assert.throws(
    () => validateBootstrapInput({ ...validInput, name: '   ' }),
    /name is required/i,
  );
  assert.throws(
    () => validateBootstrapInput({ ...validInput, email: 'not-an-email' }),
    /email must be valid/i,
  );
});

test('unexpected bootstrap errors are not printed verbatim', () => {
  const secret = validInput.password;
  assert.equal(
    safeBootstrapErrorMessage(new Error(`Database rejected ${secret}`)).includes(
      secret,
    ),
    false,
  );
  assert.match(
    safeBootstrapErrorMessage(new PlatformOwnerAlreadyExistsError()),
    /already exists/i,
  );
});
