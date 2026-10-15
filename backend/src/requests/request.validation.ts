import { RequestStatus, RequestType } from '@prisma/client';
import { z } from 'zod';

export const createRequestSchema = z
  .object({
    type: z.enum(RequestType),
    subject: z
      .string()
      .trim()
      .min(1)
      .max(160)
      .refine(
        (value) => !value.includes('\0'),
        'Text must not contain NUL characters.',
      ),
    description: z
      .string()
      .trim()
      .min(1)
      .max(5000)
      .refine(
        (value) => !value.includes('\0'),
        'Text must not contain NUL characters.',
      ),
  })
  .strict();

export const reviewSchema = z
  .object({
    status: z.enum(['APPROVED', 'REJECTED']),
    comment: z
      .string()
      .trim()
      .max(2000)
      .refine(
        (value) => !value.includes('\0'),
        'Text must not contain NUL characters.',
      )
      .optional(),
  })
  .strict();

export const idSchema = z.object({ id: z.uuid() }).strict();
const page = z
  .string()
  .regex(/^[1-9]\d*$/)
  .transform(Number)
  .pipe(z.number().int().max(10000))
  .default(1);
const pageSize = z
  .string()
  .regex(/^[1-9]\d*$/)
  .transform(Number)
  .pipe(z.number().int().max(100))
  .default(20);
export const paginationSchema = z.object({ page, pageSize }).strict();
export const hrListSchema = paginationSchema.extend({
  status: z.enum(RequestStatus).optional(),
});

export type CreateRequestInput = z.infer<typeof createRequestSchema>;
export type ReviewInput = z.infer<typeof reviewSchema>;
export type Pagination = z.infer<typeof paginationSchema>;
