import type { RequestHandler } from 'express';
import type { RequestService } from './request.service';
import {
  createRequestSchema,
  hrListSchema,
  idSchema,
  paginationSchema,
  reviewSchema,
} from './request.validation';

export function createRequestController(service: RequestService) {
  return {
    create: (async (req, res) => {
      const input = createRequestSchema.parse(req.body);
      res.status(201).json({ data: await service.create(req.user!.id, input) });
    }) satisfies RequestHandler,
    listEmployee: (async (req, res) => {
      res.json(
        await service.listEmployee(
          req.user!.id,
          paginationSchema.parse(req.query),
        ),
      );
    }) satisfies RequestHandler,
    getEmployee: (async (req, res) => {
      res.json({
        data: await service.get(idSchema.parse(req.params).id, req.user!.id),
      });
    }) satisfies RequestHandler,
    listHr: (async (req, res) => {
      const { status, ...pagination } = hrListSchema.parse(req.query);
      res.json(await service.listHr(pagination, status));
    }) satisfies RequestHandler,
    getHr: (async (req, res) => {
      res.json({ data: await service.get(idSchema.parse(req.params).id) });
    }) satisfies RequestHandler,
    review: (async (req, res) => {
      const { id } = idSchema.parse(req.params);
      const input = reviewSchema.parse(req.body);
      res.json({ data: await service.review(id, req.user!.id, input) });
    }) satisfies RequestHandler,
  };
}
