import { createHash, randomBytes } from 'node:crypto';

export function issueRefreshToken() {
  const raw = randomBytes(48).toString('base64url');
  return { raw, hash: hashToken(raw) };
}

export function hashToken(token) {
  return createHash('sha256').update(token).digest('hex');
}
