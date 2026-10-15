import type { RequestHandler } from 'express';
import { z } from 'zod';
import type { AuthService } from './auth.service';

const loginSchema = z
  .object({
    email: z.string().trim().toLowerCase().max(254).pipe(z.email()),
    // bcrypt only considers the first 72 bytes, so longer passwords are rejected.
    password: z
      .string()
      .min(1)
      .refine((value) => Buffer.byteLength(value, 'utf8') <= 72),
  })
  .strict();

export function loginController(auth: AuthService): RequestHandler {
  return async (req, res) => {
    const input = loginSchema.parse(req.body);
    res.json(await auth.login(input.email, input.password));
  };
}
