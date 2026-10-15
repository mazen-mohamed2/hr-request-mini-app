import { Router } from 'express';
import type { AuthService } from './auth/auth.service';
import { authenticate, requireRole } from './auth/auth.middleware';
import { loginController } from './auth/auth.controller';
import { createRequestController } from './requests/request.controller';
import type { RequestService } from './requests/request.service';

export function createRoutes(auth: AuthService, requests: RequestService) {
  const router = Router();
  const controller = createRequestController(requests);
  router.post('/auth/login', loginController(auth));
  router.use(authenticate(auth));
  router.get('/me', (req, res) => res.json({ data: req.user }));

  const employee = Router();
  employee.use(requireRole('EMPLOYEE'));
  employee.post('/', controller.create);
  employee.get('/', controller.listEmployee);
  employee.get('/:id', controller.getEmployee);
  router.use('/requests', employee);

  const hr = Router();
  hr.use(requireRole('HR'));
  hr.get('/', controller.listHr);
  hr.get('/:id', controller.getHr);
  hr.patch('/:id/review', controller.review);
  router.use('/hr/requests', hr);
  return router;
}
