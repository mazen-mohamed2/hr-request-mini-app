import 'dotenv/config';
import { PrismaClient } from '@prisma/client';
import { createApp } from './app';
import { loadConfig } from './config';
import { createLogger } from './logger';

async function main() {
  const config = loadConfig(process.env);
  const logger = createLogger(config);
  const db = new PrismaClient();
  await db.$connect();
  const server = createApp(db, config, logger).listen(config.PORT, () => {
    logger.info({ port: config.PORT }, 'HR Request API listening');
  });
  let stopping = false;
  const shutdown = () => {
    if (stopping) return;
    stopping = true;
    const timeout = setTimeout(() => process.exit(1), 10000);
    timeout.unref();
    server.close(() => {
      void db.$disconnect().finally(() => {
        clearTimeout(timeout);
        process.exit(0);
      });
    });
  };
  process.on('SIGTERM', shutdown);
  process.on('SIGINT', shutdown);
  server.on('error', () => {
    logger.error({ event: 'listen_failed' }, 'HTTP listener failed');
    void db.$disconnect().finally(() => process.exit(1));
  });
}

void main().catch(() => {
  // Do not print driver errors or environment values on startup failure.
  console.error(
    'Backend startup failed. Check environment configuration and database availability.',
  );
  process.exitCode = 1;
});
