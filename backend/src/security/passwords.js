import bcrypt from 'bcryptjs';

const cost = 12;

export function validatePassword(password) {
  if (password.length < 12 || !/[A-Z]/.test(password) || !/[a-z]/.test(password) || !/\d/.test(password) || !/[^A-Za-z0-9]/.test(password)) {
    return 'Use at least 12 characters with upper-case, lower-case, a number, and a symbol.';
  }
  return null;
}

export function hashPassword(password) {
  return bcrypt.hash(password, cost);
}

export function verifyPassword(password, hash) {
  return bcrypt.compare(password, hash);
}
