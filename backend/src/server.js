import { loadEnvironment } from './config/env.js';
import { buildApp } from './app.js';

const environment = loadEnvironment();
const app = await buildApp({ environment });
await app.listen({ port: environment.PORT, host: '0.0.0.0' });
