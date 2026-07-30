import crypto from 'node:crypto';
import { authenticator } from 'otplib';

authenticator.options = { step: 30, window: 1 };

export function generateTotpSecret() {
  return authenticator.generateSecret();
}

export function totpUri(secret, email) {
  return authenticator.keyuri(email, 'AVERA', secret);
}

export function verifyTotp(code, secret) {
  return /^\d{6}$/.test(code) && authenticator.check(code, secret);
}

export function encryptSecret(secret, hexKey) {
  const key = Buffer.from(hexKey, 'hex');
  const iv = crypto.randomBytes(12);
  const cipher = crypto.createCipheriv('aes-256-gcm', key, iv);
  const encrypted = Buffer.concat([cipher.update(secret, 'utf8'), cipher.final()]);
  return [
    iv.toString('base64url'),
    cipher.getAuthTag().toString('base64url'),
    encrypted.toString('base64url'),
  ].join('.');
}

export function decryptSecret(value, hexKey) {
  const [iv, tag, encrypted] = value.split('.');
  const decipher = crypto.createDecipheriv(
    'aes-256-gcm',
    Buffer.from(hexKey, 'hex'),
    Buffer.from(iv, 'base64url'),
  );
  decipher.setAuthTag(Buffer.from(tag, 'base64url'));
  return Buffer.concat([
    decipher.update(Buffer.from(encrypted, 'base64url')),
    decipher.final(),
  ]).toString('utf8');
}

export function issueOpaqueToken(bytes = 32) {
  const raw = crypto.randomBytes(bytes).toString('base64url');
  return { raw, hash: hashSecret(raw) };
}

export function hashSecret(value) {
  return crypto.createHash('sha256').update(value).digest('hex');
}

export function generateRecoveryCodes(count = 10) {
  return Array.from({ length: count }, () => {
    const raw = crypto.randomBytes(8).toString('hex').toUpperCase();
    return `${raw.slice(0, 4)}-${raw.slice(4, 8)}-${raw.slice(8, 12)}-${raw.slice(12)}`;
  });
}

export function normalizeRecoveryCode(value) {
  return value.trim().replaceAll('-', '').toUpperCase();
}

export function hashRecoveryCode(value) {
  return hashSecret(normalizeRecoveryCode(value));
}
