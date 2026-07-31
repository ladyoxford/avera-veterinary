import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { z } from 'zod';
import { writeAudit } from '../audit/audit-service.js';
import { loadEnvironment } from '../config/env.js';
import { hashPassword } from '../security/passwords.js';
import { createPool, withTenantTransaction } from './pool.js';

const bootstrapInputSchema = z.object({
  name: z.string().trim().min(1, 'Platform Owner name is required.'),
  email: z.string().trim().email('Platform Owner email must be valid.'),
  password: z.string().min(16, 'Platform Owner password must be at least 16 characters.'),
});

export class PlatformOwnerAlreadyExistsError extends Error {
  constructor() {
    super('An active Platform Owner already exists. No account was created.');
    this.name = 'PlatformOwnerAlreadyExistsError';
  }
}

export function validateBootstrapInput(input) {
  const parsed = bootstrapInputSchema.safeParse(input);
  if (!parsed.success) {
    throw new Error(parsed.error.issues[0]?.message ?? 'Invalid Platform Owner bootstrap configuration.');
  }

  const { password } = parsed.data;
  if (
    !/[A-Z]/.test(password) ||
    !/[a-z]/.test(password) ||
    !/\d/.test(password) ||
    !/[^A-Za-z0-9]/.test(password)
  ) {
    throw new Error(
      'Platform Owner password must contain uppercase, lowercase, number, and symbol characters.',
    );
  }

  return {
    name: parsed.data.name,
    email: parsed.data.email.toLowerCase(),
    password,
  };
}

export async function bootstrapPlatformOwner({
  pool,
  name,
  email,
  password,
  passwordHasher = hashPassword,
}) {
  const input = validateBootstrapInput({ name, email, password });

  return withTenantTransaction(
    pool,
    { isPlatformOwner: true },
    async (client) => {
      await client.query(
        "SELECT pg_advisory_xact_lock(hashtext('avera.bootstrap.platform-owner'))",
      );

      const existing = await client.query(
        `SELECT user_id
           FROM users
          WHERE account_type = 'PlatformOwner'
            AND status = 'Active'
            AND deleted_at IS NULL
          LIMIT 1
          FOR UPDATE`,
      );
      if (existing.rows.length > 0) {
        throw new PlatformOwnerAlreadyExistsError();
      }

      const passwordHash = await passwordHasher(input.password);
      const inserted = await client.query(
        `INSERT INTO users
           (clinic_id, full_name, email, password_hash, account_type, status,
            requires_password_change, email_verified_at)
         VALUES
           (NULL, $1, $2, $3, 'PlatformOwner', 'Active', false, now())
         RETURNING user_id, full_name, email, account_type, status, clinic_id`,
        [input.name, input.email, passwordHash],
      );
      const owner = inserted.rows[0];

      await writeAudit(client, {
        clinicId: null,
        actingUserId: owner.user_id,
        targetType: 'user',
        targetId: owner.user_id,
        action: 'platform_owner.bootstrap_created',
        newSummary: {
          fullName: owner.full_name,
          email: owner.email,
          accountType: owner.account_type,
          status: owner.status,
        },
        reason: 'One-time production Platform Owner bootstrap.',
      });

      return owner;
    },
  );
}

export async function runPlatformOwnerBootstrap(rawEnvironment = process.env) {
  const environment = loadEnvironment(rawEnvironment);
  if (environment.NODE_ENV !== 'production') {
    throw new Error('Platform Owner bootstrap is restricted to NODE_ENV=production.');
  }

  const pool = createPool(environment.DATABASE_URL);
  try {
    return await bootstrapPlatformOwner({
      pool,
      name: rawEnvironment.BOOTSTRAP_PLATFORM_OWNER_NAME,
      email: rawEnvironment.BOOTSTRAP_PLATFORM_OWNER_EMAIL,
      password: rawEnvironment.BOOTSTRAP_PLATFORM_OWNER_PASSWORD,
    });
  } finally {
    await pool.end();
  }
}

export function safeBootstrapErrorMessage(error) {
  if (
    error instanceof PlatformOwnerAlreadyExistsError ||
    (error instanceof Error &&
      (error.message.startsWith('Platform Owner ') ||
        error.message.startsWith('Production cannot enable ')))
  ) {
    return error.message;
  }
  return 'Bootstrap could not be completed. Check the production service configuration and database status.';
}

const isMainModule =
  process.argv[1] &&
  path.resolve(process.argv[1]) === fileURLToPath(import.meta.url);

if (isMainModule) {
  try {
    await runPlatformOwnerBootstrap();
    console.log('Platform Owner created successfully.');
  } catch (error) {
    console.error(
      `Platform Owner bootstrap failed: ${safeBootstrapErrorMessage(error)}`,
    );
    process.exitCode = 1;
  }
}
