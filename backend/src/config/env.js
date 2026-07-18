import { z } from 'zod';

const schema = z.object({
  NODE_ENV: z.enum(['development', 'test', 'staging', 'production']).default('development'),
  PORT: z.coerce.number().int().positive().default(8080),
  DATABASE_URL: z.string().url(),
  JWT_ACCESS_SECRET: z.string().min(32),
  JWT_REFRESH_SECRET: z.string().min(32),
  ACCESS_TOKEN_TTL_SECONDS: z.coerce.number().int().positive().default(900),
  REFRESH_TOKEN_TTL_DAYS: z.coerce.number().int().positive().default(30),
  ALLOWED_ORIGINS: z.string().default('http://localhost:3000'),
  ENABLE_LOCAL_DEVELOPMENT_AUTH: z.enum(['true', 'false']).default('false'),
  ENABLE_DEMO_DATA_GENERATOR: z.enum(['true', 'false']).default('false'),
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
  return {
    ...environment,
    localDevelopmentAuth: environment.ENABLE_LOCAL_DEVELOPMENT_AUTH === 'true',
    demoDataGeneratorEnabled: environment.ENABLE_DEMO_DATA_GENERATOR === 'true',
    allowedOrigins: environment.ALLOWED_ORIGINS.split(',').map((value) => value.trim()),
  };
}
