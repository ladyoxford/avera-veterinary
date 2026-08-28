import {
  createHash,
  createPublicKey,
  verify as verifySignature,
} from 'node:crypto';

const googleIssuer = new Set([
  'accounts.google.com',
  'https://accounts.google.com',
]);
const appleIssuer = 'https://appleid.apple.com';
const clockSkewSeconds = 60;

export class ProviderTokenVerifier {
  constructor({ environment, fetchImpl = globalThis.fetch }) {
    this.environment = environment;
    this.fetchImpl = fetchImpl;
    this.appleKeys = null;
    this.appleKeysExpiresAt = 0;
  }

  async verify({ provider, idToken, nonce }) {
    if (provider === 'google') return this.#verifyGoogle(idToken);
    if (provider === 'apple') return this.#verifyApple(idToken, nonce);
    throw providerError('provider_not_supported', 'This sign-in provider is unavailable.');
  }

  async #verifyGoogle(idToken) {
    const audiences = configuredValues(this.environment.GOOGLE_OAUTH_CLIENT_IDS);
    if (audiences.length === 0) {
      throw providerError(
        'google_not_configured',
        'Google sign-in has not been configured for this AVERA environment.',
        503,
      );
    }
    const response = await this.fetchImpl(
      `https://oauth2.googleapis.com/tokeninfo?id_token=${encodeURIComponent(idToken)}`,
      { headers: { 'User-Agent': 'AVERA-Backend/1.0' } },
    );
    if (!response.ok) {
      throw providerError('provider_token_invalid', 'Google could not verify this sign-in.', 401);
    }
    const claims = await response.json();
    if (
      !googleIssuer.has(claims.iss) ||
      !audiences.includes(claims.aud) ||
      !isFutureTimestamp(claims.exp) ||
      String(claims.email_verified) !== 'true' ||
      typeof claims.sub !== 'string' ||
      typeof claims.email !== 'string'
    ) {
      throw providerError('provider_token_invalid', 'Google returned an invalid identity.', 401);
    }
    return {
      provider: 'google',
      subject: claims.sub,
      email: normalizeEmail(claims.email),
      emailVerified: true,
      isPrivateRelay: false,
    };
  }

  async #verifyApple(idToken, nonce) {
    const audiences = configuredValues(this.environment.APPLE_OAUTH_CLIENT_IDS);
    if (audiences.length === 0) {
      throw providerError(
        'apple_not_configured',
        'Apple sign-in has not been configured for this AVERA environment.',
        503,
      );
    }
    if (!nonce) {
      throw providerError('provider_nonce_required', 'Apple sign-in must include a secure nonce.');
    }
    const parts = String(idToken).split('.');
    if (parts.length !== 3) {
      throw providerError('provider_token_invalid', 'Apple returned an invalid identity.', 401);
    }
    const header = decodeJson(parts[0]);
    const claims = decodeJson(parts[1]);
    if (header.alg !== 'RS256' || typeof header.kid !== 'string') {
      throw providerError('provider_token_invalid', 'Apple returned an unsupported identity token.', 401);
    }
    const key = (await this.#applePublicKeys()).find((item) => item.kid === header.kid);
    if (!key) {
      throw providerError('provider_token_invalid', 'Apple identity signing key was not found.', 401);
    }
    const verified = verifySignature(
      'RSA-SHA256',
      Buffer.from(`${parts[0]}.${parts[1]}`),
      createPublicKey({ key, format: 'jwk' }),
      Buffer.from(parts[2], 'base64url'),
    );
    const expectedNonce = createHash('sha256').update(nonce).digest('hex');
    if (
      !verified ||
      claims.iss !== appleIssuer ||
      !audiences.includes(claims.aud) ||
      !isFutureTimestamp(claims.exp) ||
      claims.nonce !== expectedNonce ||
      typeof claims.sub !== 'string'
    ) {
      throw providerError('provider_token_invalid', 'Apple could not verify this sign-in.', 401);
    }
    const email = typeof claims.email === 'string' ? normalizeEmail(claims.email) : null;
    const emailVerified = claims.email_verified === true || claims.email_verified === 'true';
    return {
      provider: 'apple',
      subject: claims.sub,
      email,
      emailVerified,
      isPrivateRelay: email?.endsWith('@privaterelay.appleid.com') === true,
    };
  }

  async #applePublicKeys() {
    if (this.appleKeys && Date.now() < this.appleKeysExpiresAt) return this.appleKeys;
    const response = await this.fetchImpl('https://appleid.apple.com/auth/keys', {
      headers: { 'User-Agent': 'AVERA-Backend/1.0' },
    });
    if (!response.ok) {
      throw providerError('provider_verification_unavailable', 'Apple sign-in verification is unavailable.', 503);
    }
    const body = await response.json();
    this.appleKeys = Array.isArray(body.keys) ? body.keys : [];
    this.appleKeysExpiresAt = Date.now() + 60 * 60 * 1000;
    return this.appleKeys;
  }
}

function configuredValues(value) {
  return String(value ?? '')
    .split(',')
    .map((item) => item.trim())
    .filter(Boolean);
}

function decodeJson(value) {
  try {
    return JSON.parse(Buffer.from(value, 'base64url').toString('utf8'));
  } catch (_) {
    throw providerError('provider_token_invalid', 'The provider identity token is malformed.', 401);
  }
}

function isFutureTimestamp(value) {
  const timestamp = Number(value);
  return Number.isFinite(timestamp) && timestamp + clockSkewSeconds > Date.now() / 1000;
}

function normalizeEmail(value) {
  return String(value).trim().toLowerCase();
}

function providerError(code, message, statusCode = 400) {
  const error = new Error(message);
  error.code = code;
  error.statusCode = statusCode;
  return error;
}
