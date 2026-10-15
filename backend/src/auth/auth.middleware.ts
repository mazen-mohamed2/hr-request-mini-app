import type { RequestHandler } from 'express';
import type { Role } from '@prisma/client';
import type { AuthService } from './auth.service';
import type { SafeUser } from '../users/user.repository';
import { AppError } from '../errors';

declare global {
  namespace Express {
    interface Request {
      user?: SafeUser;
    }
  }
}

export function authenticate(auth: AuthService): RequestHandler {
  return async (req, _res, next) => {
    const match = /^Bearer ([^\s]+)$/i.exec(req.headers.authorization ?? '');
    if (!match?.[1])
      throw new AppError(
        401,
        'UNAUTHORIZED',
        'Bearer authentication is required.',
      );
    req.user = await auth.authenticate(match[1]);
    next();
  };
}

export function requireRole(role: Role): RequestHandler {
  return (req, _res, next) => {
    if (!req.user)
      throw new AppError(401, 'UNAUTHORIZED', 'Authentication is required.');
    if (req.user.role !== role)
      throw new AppError(
        403,
        'FORBIDDEN',
        'You do not have permission to perform this action.',
      );
    next();
  };
}
