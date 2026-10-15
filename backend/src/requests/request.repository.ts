import { Prisma, type PrismaClient, type RequestStatus } from '@prisma/client';
import { safeUserSelect } from '../users/user.repository';
import type {
  CreateRequestInput,
  Pagination,
  ReviewInput,
} from './request.validation';

const include = {
  employee: { select: safeUserSelect },
  reviewer: { select: safeUserSelect },
} satisfies Prisma.HRRequestInclude;

export function createRequestRepository(db: PrismaClient) {
  return {
    create(employeeId: string, input: CreateRequestInput) {
      return db.hRRequest.create({
        data: {
          employeeId,
          type: input.type,
          subject: input.subject,
          description: input.description,
        },
        include,
      });
    },
    async list(
      filter: { employeeId?: string; status?: RequestStatus },
      pagination: Pagination,
    ) {
      const { page, pageSize } = pagination;
      const [data, total] = await db.$transaction(
        [
          db.hRRequest.findMany({
            where: filter,
            orderBy: [{ submittedAt: 'desc' }, { id: 'desc' }],
            skip: (page - 1) * pageSize,
            take: pageSize,
            include,
          }),
          db.hRRequest.count({ where: filter }),
        ],
        { isolationLevel: Prisma.TransactionIsolationLevel.RepeatableRead },
      );
      return {
        data,
        pagination: {
          page,
          pageSize,
          total,
          totalPages: Math.ceil(total / pageSize),
        },
      };
    },
    find(id: string, employeeId?: string) {
      return db.hRRequest.findFirst({
        where: { id, ...(employeeId ? { employeeId } : {}) },
        include,
      });
    },
    reviewPending(id: string, reviewerId: string, input: ReviewInput) {
      return db.$transaction(async (transaction) => {
        // Conditional UPDATE locks the row. PostgreSQL rechecks PENDING after a
        // concurrent writer commits, so exactly one reviewer can succeed.
        const result = await transaction.hRRequest.updateMany({
          where: { id, status: 'PENDING' },
          data: {
            status: input.status,
            hrComment: input.comment || null,
            reviewedBy: reviewerId,
            reviewedAt: new Date(),
          },
        });
        if (result.count === 0) {
          const exists = await transaction.hRRequest.findUnique({
            where: { id },
            select: { id: true },
          });
          return {
            outcome: exists
              ? ('already-reviewed' as const)
              : ('not-found' as const),
          };
        }
        const request = await transaction.hRRequest.findUniqueOrThrow({
          where: { id },
          include,
        });
        return { outcome: 'reviewed' as const, request };
      });
    },
  };
}

export type RequestRepository = ReturnType<typeof createRequestRepository>;
