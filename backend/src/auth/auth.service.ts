import bcrypt from 'bcrypt';
import jwt from 'jsonwebtoken';
import { randomBytes } from 'node:crypto';
import { z } from 'zod';
import type { Config } from '../config';
import { AppError } from '../errors';
import type { UserRepository } from '../users/user.repository';

const issuer = 'hr-request-api';
const audience = 'hr-request-client';
const claimsSchema = z.object({
  sub: z.uuid(),
  exp: z.number(),
  iat: z.number(),
});

export function createAuthService(users: UserRepository, config: Config) {
  const dummyHash = bcrypt.hash(randomBytes(32).toString('hex'), 12);
  return {
    async login(email: string, password: string) {
      const user = await users.findForLogin(email);
      const valid = await bcrypt.compare(
        password,
        user?.passwordHash ?? (await dummyHash),
      );
      if (!user || !valid)
        throw new AppError(
          401,
          'INVALID_CREDENTIALS',
          'Invalid email or password.',
        );
      const { passwordHash: _passwordHash, ...safeUser } = user;
      const token = jwt.sign({}, config.JWT_SECRET, {
        algorithm: 'HS256',
        subject: user.id,
        issuer,
        audience,
        expiresIn: config.JWT_EXPIRES_IN_SECONDS,
      });
      return {
        token,
        tokenType: 'Bearer',
        expiresIn: config.JWT_EXPIRES_IN_SECONDS,
        user: safeUser,
      };
    },
    async authenticate(token: string) {
      let userId: string;
      try {
        const claims = jwt.verify(token, config.JWT_SECRET, {
          algorithms: ['HS256'],
          issuer,
          audience,
        });
        userId = claimsSchema.parse(claims).sub;
      } catch {
        throw new AppError(
          401,
          'UNAUTHORIZED',
          'Invalid or expired authentication token.',
        );
      }
      // Current database role is authoritative, including after token issuance.
      const user = await users.findSafeById(userId);
      if (!user)
        throw new AppError(
          401,
          'UNAUTHORIZED',
          'Invalid authentication token.',
        );
      return user;
    },
  };
}

export type AuthService = ReturnType<typeof createAuthService>;
