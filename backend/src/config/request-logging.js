const sensitiveAccountPaths = [
  '/activate-clinic-admin',
  '/activate-staff',
  '/reset-password',
];

export function sanitizeRequestUrl(value) {
  const url = String(value ?? '');
  const sensitivePath = sensitiveAccountPaths.find((path) => url.startsWith(path));
  return sensitivePath ?? url;
}

export function requestLogSerializer(request) {
  return {
    method: request.method,
    url: sanitizeRequestUrl(request.url),
    host: request.headers?.host,
    remoteAddress: request.socket?.remoteAddress,
    remotePort: request.socket?.remotePort,
  };
}
