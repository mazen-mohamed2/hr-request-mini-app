import type { RequestStatus } from '@prisma/client';
import type { Logger } from 'pino';
import { AppError } from '../errors';
import type { RequestRepository } from './request.repository';
import type {
  CreateRequestInput,
  Pagination,
  ReviewInput,
} from './request.validation';

export function createRequestService(
  requests: RequestRepository,
  logger: Logger,
) {
  return {
    create: (employeeId: string, input: CreateRequestInput) =>
      requests.create(employeeId, input),
    listEmployee: (employeeId: string, pagination: Pagination) =>
      requests.list({ employeeId }, pagination),
    listHr: (pagination: Pagination, status?: RequestStatus) =>
      requests.list({ status }, pagination),
    async get(id: string, employeeId?: string) {
      const request = await requests.find(id, employeeId);
      // Missing and someone else's request have the same private-resource response.
      if (!request)
        throw new AppError(404, 'REQUEST_NOT_FOUND', 'Request not found.');
      return request;
    },
    async review(id: string, reviewerId: string, input: ReviewInput) {
      const result = await requests.reviewPending(id, reviewerId, input);
      if (result.outcome === 'not-found')
        throw new AppError(404, 'REQUEST_NOT_FOUND', 'Request not found.');
      if (result.outcome === 'already-reviewed')
        throw new AppError(
          409,
          'ALREADY_REVIEWED',
          'Only pending requests may be reviewed.',
        );
      logger.info(
        {
          event: 'hr_request_reviewed',
          requestId: id,
          reviewerId,
          status: input.status,
        },
        'HR request reviewed',
      );
      return result.request;
    },
  };
}

export type RequestService = ReturnType<typeof createRequestService>;
