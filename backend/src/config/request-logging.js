const activationPath = '/activate-clinic-admin';

export function sanitizeRequestUrl(value) {
  const url = String(value ?? '');
  if (!url.startsWith(activationPath)) return url;
  return activationPath;
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
