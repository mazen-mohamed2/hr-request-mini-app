import express from 'express';
import helmet from 'helmet';
import cors from 'cors';
import { rateLimit } from 'express-rate-limit';
import { randomUUID } from 'node:crypto';
import type { PrismaClient } from '@prisma/client';
import type { Logger } from 'pino';
import type { Config } from './config';
import { createUserRepository } from './users/user.repository';
import { createAuthService } from './auth/auth.service';
import { createRequestRepository } from './requests/request.repository';
import { createRequestService } from './requests/request.service';
import { createRoutes } from './routes';
import { AppError, errorHandler, notFound } from './errors';

export function createApp(db: PrismaClient, config: Config, logger: Logger) {
  const app = express();
  app.disable('x-powered-by');
  app.disable('etag');
  // No trust proxy by default: untrusted forwarded IP headers cannot bypass limits.
  app.use(helmet());
  app.use((req, res, next) => {
    const requestId = randomUUID();
    const start = performance.now();
    res.setHeader('X-Request-Id', requestId);
    res.setHeader('Cache-Control', 'no-store');
    res.on('finish', () => {
      // Log route templates instead of raw URLs, query strings, or request data.
      logger.info(
        {
          requestId,
          method: req.method,
          route: req.route ? `${req.baseUrl}${req.route.path}` : 'unmatched',
          statusCode: res.statusCode,
          durationMs: Math.round(performance.now() - start),
        },
        'HTTP request',
      );
    });
    next();
  });
  app.use(
    cors({
      origin(origin, callback) {
        if (!origin || config.CORS_ORIGINS.includes(origin))
          callback(null, true);
        else
          callback(
            new AppError(403, 'CORS_FORBIDDEN', 'Origin is not allowed.'),
          );
      },
      methods: ['GET', 'POST', 'PATCH', 'OPTIONS'],
      allowedHeaders: ['Content-Type', 'Authorization'],
      credentials: false,
    }),
  );
  const loginLimiter = rateLimit({
    windowMs: 15 * 60 * 1000,
    limit: config.LOGIN_RATE_LIMIT_MAX,
    standardHeaders: 'draft-8',
    legacyHeaders: false,
    // Direct local server: forwarded headers are ignored, never trusted as client IPs.
    validate: { xForwardedForHeader: false },
    message: {
      error: {
        code: 'RATE_LIMITED',
        message: 'Too many login attempts. Try again later.',
      },
    },
  });
  // Limit malformed login bodies too, before the JSON parser.
  app.use('/api/auth/login', loginLimiter);
  app.use(express.json({ limit: '32kb' }));
  const users = createUserRepository(db);
  const auth = createAuthService(users, config);
  const requests = createRequestService(createRequestRepository(db), logger);
  app.use('/api', createRoutes(auth, requests));
  app.use(notFound);
  app.use(errorHandler(logger));
  return app;
}
