import { z } from 'zod';

const schema = z.object({
  NODE_ENV: z.enum(['development', 'test', 'staging', 'production']).default('development'),
  PORT: z.coerce.number().int().positive().default(8080),
  DATABASE_URL: z.string().url(),
  JWT_ACCESS_SECRET: z.string().min(32),
  JWT_REFRESH_SECRET: z.string().min(32),
  TOTP_ENCRYPTION_KEY: z.string().regex(/^[a-fA-F0-9]{64}$/).optional(),
  ACCESS_TOKEN_TTL_SECONDS: z.coerce.number().int().positive().default(900),
  REFRESH_TOKEN_TTL_DAYS: z.coerce.number().int().positive().default(30),
  ALLOWED_ORIGINS: z.string().default('http://localhost:3000'),
  ENABLE_LOCAL_DEVELOPMENT_AUTH: z.enum(['true', 'false']).default('false'),
  ENABLE_DEMO_DATA_GENERATOR: z.enum(['true', 'false']).default('false'),
  PAYSTACK_MODE: z.enum(['test', 'live']).optional(),
  PAYSTACK_SECRET_KEY: z.string().min(1).optional(),
  PAYSTACK_PUBLIC_KEY: z.string().min(1).optional(),
  PAYSTACK_WEBHOOK_SECRET: z.string().min(1).optional(),
  PAYSTACK_CALLBACK_URL: z.string().url().optional(),
  PAYSTACK_CURRENCY: z.string().length(3).default('NGN'),
  APP_PAYMENT_CALLBACK_URL: z.string().url().optional(),
  APP_REGISTRATION_PAYMENT_CALLBACK_URL: z.string().url().optional(),
  APP_DEEP_LINK_SCHEME: z.string().regex(/^[a-z][a-z0-9+.-]*$/).default('avera'),
  REGISTRATION_PAYMENT_TOKEN_TTL_MINUTES: z.coerce.number().int().positive().default(1440),
  REGISTRATION_DRAFT_TOKEN_TTL_MINUTES: z.coerce.number().int().positive().default(10080),
  PAYSTACK_STARTER_MONTHLY_PLAN_CODE: z.string().optional(),
  PAYSTACK_STARTER_ANNUAL_PLAN_CODE: z.string().optional(),
  PAYSTACK_PROFESSIONAL_MONTHLY_PLAN_CODE: z.string().optional(),
  PAYSTACK_PROFESSIONAL_ANNUAL_PLAN_CODE: z.string().optional(),
  PAYSTACK_ENTERPRISE_MONTHLY_PLAN_CODE: z.string().optional(),
  PAYSTACK_ENTERPRISE_ANNUAL_PLAN_CODE: z.string().optional(),
  ACTIVATION_TOKEN_TTL_MINUTES: z.coerce.number().int().positive().default(1440),
  AVERA_ACTIVATION_BASE_URL: z.string().min(1).default('https://accounts.averavet.sbs/activate-clinic-admin'),
  AVERA_STAFF_ACTIVATION_BASE_URL: z.string().min(1).default('https://accounts.averavet.sbs/activate-staff'),
  RESEND_API_KEY: z.string().min(1).optional(),
  ACTIVATION_EMAIL_FROM: z.string().min(3).optional(),
  SUPABASE_URL: z.string().url().optional(),
  SUPABASE_SERVICE_ROLE_KEY: z.string().min(20).optional(),
  PROFILE_PHOTO_BUCKET: z.string().min(1).default('profile-photos'),
  LOG_LEVEL: z.string().default('info'),
});

export function loadEnvironment(raw = process.env) {
  const environment = schema.parse(raw);
  if (environment.NODE_ENV === 'production' && environment.ENABLE_LOCAL_DEVELOPMENT_AUTH === 'true') {
    throw new Error('Production cannot enable local development authentication.');
  }
  if (environment.NODE_ENV === 'production' && environment.ENABLE_DEMO_DATA_GENERATOR === 'true') {
    throw new Error('Production cannot enable the demo data generator.');
  }
  if (environment.NODE_ENV === 'production' && !environment.TOTP_ENCRYPTION_KEY) {
    throw new Error('Production requires TOTP_ENCRYPTION_KEY.');
  }
  try {
    new URL(environment.AVERA_ACTIVATION_BASE_URL);
  } catch (_) {
    throw new Error('AVERA_ACTIVATION_BASE_URL must be a valid HTTPS or application deep-link URL.');
  }
  return {
    ...environment,
    TOTP_ENCRYPTION_KEY:
      environment.TOTP_ENCRYPTION_KEY ??
      Buffer.from(environment.JWT_REFRESH_SECRET.padEnd(32, '0').slice(0, 32))
        .toString('hex'),
    localDevelopmentAuth: environment.ENABLE_LOCAL_DEVELOPMENT_AUTH === 'true',
    demoDataGeneratorEnabled: environment.ENABLE_DEMO_DATA_GENERATOR === 'true',
    allowedOrigins: environment.ALLOWED_ORIGINS.split(',').map((value) => value.trim()),
    paymentCallbackUrl:
      environment.PAYSTACK_CALLBACK_URL ?? environment.APP_PAYMENT_CALLBACK_URL,
    registrationPaymentCallbackUrl:
      environment.APP_REGISTRATION_PAYMENT_CALLBACK_URL ??
      `${environment.APP_DEEP_LINK_SCHEME}://app/payments/registration-callback`,
  };
}
