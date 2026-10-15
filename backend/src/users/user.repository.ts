import { Prisma, type PrismaClient } from '@prisma/client';

export const safeUserSelect = {
  id: true,
  employeeId: true,
  name: true,
  email: true,
  department: true,
  jobTitle: true,
  role: true,
  createdAt: true,
  updatedAt: true,
} satisfies Prisma.UserSelect;

export type SafeUser = Prisma.UserGetPayload<{ select: typeof safeUserSelect }>;

export function createUserRepository(db: PrismaClient) {
  return {
    findForLogin: (email: string) =>
      db.user.findUnique({
        where: { email },
        select: { ...safeUserSelect, passwordHash: true },
      }),
    findSafeById: (id: string) =>
      db.user.findUnique({ where: { id }, select: safeUserSelect }),
  };
}

export type UserRepository = ReturnType<typeof createUserRepository>;
