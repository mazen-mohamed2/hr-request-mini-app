import type { ErrorRequestHandler, RequestHandler } from 'express';
import type { Logger } from 'pino';
import { ZodError } from 'zod';

export class AppError extends Error {
  constructor(
    public readonly status: number,
    public readonly code: string,
    message: string,
  ) {
    super(message);
  }
}

export const notFound: RequestHandler = (_req, _res, next) =>
  next(new AppError(404, 'NOT_FOUND', 'Route not found.'));

export function errorHandler(logger: Logger): ErrorRequestHandler {
  return (error: unknown, _req, res, _next) => {
    if (error instanceof ZodError) {
      res.status(400).json({
        error: {
          code: 'VALIDATION_ERROR',
          message: 'Invalid request input.',
          details: error.issues.map((issue) => ({
            path: issue.path.join('.'),
            code: issue.code,
          })),
        },
      });
      return;
    }
    if (error instanceof AppError) {
      res
        .status(error.status)
        .json({ error: { code: error.code, message: error.message } });
      return;
    }
    if (error instanceof URIError) {
      res.status(400).json({
        error: { code: 'INVALID_PATH', message: 'Invalid URL encoding.' },
      });
      return;
    }
    const bodyError = error as { type?: string } | null;
    if (
      bodyError?.type === 'entity.parse.failed' ||
      bodyError?.type === 'entity.too.large' ||
      bodyError?.type === 'charset.unsupported' ||
      bodyError?.type === 'encoding.unsupported'
    ) {
      res.status(400).json({
        error: {
          code: 'INVALID_BODY',
          message: 'Body must be valid JSON within the size limit.',
        },
      });
      return;
    }
    // Database/driver errors can embed SQL values and connection credentials.
    // Record classification only, never the raw error, message, body, or headers.
    logger.error(
      {
        event: 'server_error',
        category:
          error instanceof Error ? error.constructor.name : 'UnknownError',
      },
      'Unexpected server error',
    );
    res.status(500).json({
      error: {
        code: 'INTERNAL_ERROR',
        message: 'An unexpected server error occurred.',
      },
    });
  };
}
