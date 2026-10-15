import pino, { type DestinationStream } from 'pino';
import type { Config } from './config';

export function createLogger(
  config: Pick<Config, 'LOG_LEVEL'>,
  destination?: DestinationStream,
) {
  return pino(
    {
      level: config.LOG_LEVEL,
      redact: {
        paths: [
          'password',
          'passwordHash',
          'token',
          'authorization',
          'req.headers.authorization',
          'req.body',
          'DATABASE_URL',
          'JWT_SECRET',
        ],
        censor: '[REDACTED]',
      },
    },
    destination,
  );
}
