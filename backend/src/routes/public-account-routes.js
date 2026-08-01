import { readFile } from 'node:fs/promises';

const assetLinks = readFile(
  new URL('../../public/.well-known/assetlinks.json', import.meta.url),
  'utf8',
);
const activationPage = readFile(
  new URL('../../public/activate-clinic-admin.html', import.meta.url),
  'utf8',
);

export async function publicAccountRoutes(app) {
  app.get('/.well-known/assetlinks.json', async (_, reply) => {
    return reply
      .type('application/json; charset=utf-8')
      .header('Cache-Control', 'public, max-age=3600')
      .send(await assetLinks);
  });

  app.get('/activate-clinic-admin', async (_, reply) => {
    return reply
      .type('text/html; charset=utf-8')
      .header('Cache-Control', 'no-store, max-age=0')
      .header('Referrer-Policy', 'no-referrer')
      .header('X-Robots-Tag', 'noindex, nofollow')
      .header(
        'Content-Security-Policy',
        "default-src 'none'; style-src 'unsafe-inline'; script-src 'unsafe-inline'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'",
      )
      .send(await activationPage);
  });
}
