import { afterAll, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import request from 'supertest';
import { PrismaClient, type User } from '@prisma/client';
import bcrypt from 'bcrypt';
import jwt from 'jsonwebtoken';
import { randomUUID } from 'node:crypto';
import { Writable } from 'node:stream';
import pino from 'pino';
import { createApp } from '../src/app';
import { loadConfig } from '../src/config';
import { testDatabaseUrl } from './test-database';

const databaseUrl = testDatabaseUrl();
const config = loadConfig({
  NODE_ENV: 'test',
  DATABASE_URL: databaseUrl,
  JWT_SECRET: 'test-only-secret-that-is-at-least-32-characters',
  CORS_ORIGINS: 'http://localhost:5173',
  LOGIN_RATE_LIMIT_MAX: '1000',
});
const logs: string[] = [];
const logger = pino(
  { level: 'info' },
  new Writable({
    write(chunk, _encoding, callback) {
      logs.push(chunk.toString());
      callback();
    },
  }),
);
const db = new PrismaClient({ datasourceUrl: databaseUrl });
const app = createApp(db, config, logger);
const password = 'TestPassword123!';
let alice: User;
let bob: User;
let hr: User;
let aliceToken: string;
let bobToken: string;
let hrToken: string;

const input = {
  type: 'EMPLOYMENT_LETTER',
  subject: 'Employment confirmation',
  description: 'Please issue my employment letter.',
};
function bearer(token: string) {
  return { Authorization: `Bearer ${token}` };
}
async function login(email: string) {
  const response = await request(app)
    .post('/api/auth/login')
    .send({ email, password })
    .expect(200);
  return response.body.token as string;
}
async function create(token = aliceToken) {
  const response = await request(app)
    .post('/api/requests')
    .set(bearer(token))
    .send(input)
    .expect(201);
  return response.body.data as { id: string; employeeId: string };
}

beforeAll(async () => {
  await db.hRRequest.deleteMany();
  await db.user.deleteMany();
  const passwordHash = await bcrypt.hash(password, 12);
  const common = {
    passwordHash,
    department: 'Engineering',
    jobTitle: 'Engineer',
  };
  alice = await db.user.create({
    data: {
      ...common,
      name: 'Alice',
      email: 'alice@test.example',
      employeeId: 'TEST001',
      role: 'EMPLOYEE',
    },
  });
  bob = await db.user.create({
    data: {
      ...common,
      name: 'Bob',
      email: 'bob@test.example',
      employeeId: 'TEST002',
      role: 'EMPLOYEE',
    },
  });
  hr = await db.user.create({
    data: {
      ...common,
      name: 'HR',
      email: 'hr@test.example',
      employeeId: 'TESTHR',
      role: 'HR',
    },
  });
  [aliceToken, bobToken, hrToken] = await Promise.all([
    login(alice.email),
    login(bob.email),
    login(hr.email),
  ]);
});
beforeEach(async () => {
  await db.hRRequest.deleteMany();
  logs.length = 0;
});
afterAll(async () => {
  await db.hRRequest.deleteMany();
  await db.user.deleteMany();
  await db.$disconnect();
});

describe('authentication and profile', () => {
  it.each(['EMPLOYEE', 'HR'])(
    'logs in %s with safe user information and an expiring JWT',
    async (role) => {
      const user = role === 'HR' ? hr : alice;
      const response = await request(app)
        .post('/api/auth/login')
        .send({ email: `  ${user.email.toUpperCase()}  `, password })
        .expect(200);
      expect(response.body.user).toMatchObject({ id: user.id, role });
      expect(JSON.stringify(response.body)).not.toContain('passwordHash');
      const claims = jwt.verify(response.body.token, config.JWT_SECRET, {
        algorithms: ['HS256'],
        issuer: 'hr-request-api',
        audience: 'hr-request-client',
      }) as jwt.JwtPayload;
      expect(claims.sub).toBe(user.id);
      expect(claims.exp! - claims.iat!).toBe(3600);
    },
  );
  it.each(['wrong-password', 'unknown-user'])(
    'rejects %s with the same credentials error',
    async (scenario) => {
      const response = await request(app)
        .post('/api/auth/login')
        .send({
          email:
            scenario === 'unknown-user' ? 'missing@test.example' : alice.email,
          password: 'incorrect',
        })
        .expect(401);
      expect(response.body).toEqual({
        error: {
          code: 'INVALID_CREDENTIALS',
          message: 'Invalid email or password.',
        },
      });
    },
  );
  it.each([undefined, 'bad-token', 'Basic abc'])(
    'rejects missing or malformed authentication: %s',
    async (value) => {
      const call = request(app).get('/api/me');
      if (value)
        call.set(
          'Authorization',
          value === 'bad-token' ? `Bearer ${value}` : value,
        );
      await call.expect(401);
    },
  );
  it.each([
    'expired',
    'wrong-secret',
    'wrong-audience',
    'wrong-algorithm',
    'missing-expiry',
    'deleted-user',
  ])('rejects %s JWTs', async (scenario) => {
    const token = jwt.sign(
      {},
      scenario === 'wrong-secret' ? 'different-secret' : config.JWT_SECRET,
      {
        algorithm: scenario === 'wrong-algorithm' ? 'HS384' : 'HS256',
        subject: scenario === 'deleted-user' ? randomUUID() : alice.id,
        issuer: 'hr-request-api',
        audience:
          scenario === 'wrong-audience' ? 'other-client' : 'hr-request-client',
        ...(scenario === 'missing-expiry'
          ? {}
          : { expiresIn: scenario === 'expired' ? -10 : 3600 }),
      },
    );
    await request(app).get('/api/me').set(bearer(token)).expect(401);
  });
  it.each(['employee', 'hr'])(
    'returns the authenticated %s profile',
    async (role) => {
      const response = await request(app)
        .get('/api/me')
        .set(bearer(role === 'hr' ? hrToken : aliceToken))
        .expect(200);
      expect(response.body.data.id).toBe(role === 'hr' ? hr.id : alice.id);
      expect(JSON.stringify(response.body)).not.toContain('passwordHash');
    },
  );
  it('reads current roles from the database instead of trusting stale token roles', async () => {
    await db.user.update({ where: { id: hr.id }, data: { role: 'EMPLOYEE' } });
    try {
      await request(app)
        .get('/api/hr/requests')
        .set(bearer(hrToken))
        .expect(403);
    } finally {
      await db.user.update({ where: { id: hr.id }, data: { role: 'HR' } });
    }
  });
  it('stores bcrypt hashes rather than plaintext', async () => {
    const user = await db.user.findUniqueOrThrow({ where: { id: alice.id } });
    expect(user.passwordHash).toMatch(/^\$2[ab]\$12\$/);
    expect(user.passwordHash).not.toBe(password);
    expect(await bcrypt.compare(password, user.passwordHash)).toBe(true);
  });
  it.each([
    { email: 'invalid', password },
    { email: 'alice@test.example', password: '' },
    { email: 'alice@test.example', password: 'é'.repeat(37) },
    { email: 'alice@test.example', password, role: 'HR' },
  ])('validates login input', async (body) => {
    await request(app).post('/api/auth/login').send(body).expect(400);
  });
});

describe('employee flow and ownership', () => {
  it('creates a trimmed pending request owned by the authenticated employee', async () => {
    const before = Date.now();
    const response = await request(app)
      .post('/api/requests')
      .set(bearer(aliceToken))
      .send({
        ...input,
        subject: '  Letter  ',
        description: '  Please issue a letter.  ',
      })
      .expect(201);
    expect(response.body.data).toMatchObject({
      employeeId: alice.id,
      status: 'PENDING',
      subject: 'Letter',
      description: 'Please issue a letter.',
      hrComment: null,
      reviewedAt: null,
      reviewedBy: null,
    });
    expect(
      new Date(response.body.data.submittedAt).getTime(),
    ).toBeGreaterThanOrEqual(before - 10);
    expect(
      (
        await db.hRRequest.findUniqueOrThrow({
          where: { id: response.body.data.id },
        })
      ).employeeId,
    ).toBe(alice.id);
    expect(JSON.stringify(response.body)).not.toContain('passwordHash');
  });
  it('lists only own requests, newest first, with pagination', async () => {
    const first = await create();
    const second = await create();
    await create(bobToken);
    await db.hRRequest.update({
      where: { id: first.id },
      data: { submittedAt: new Date('2025-01-01') },
    });
    const response = await request(app)
      .get('/api/requests?page=1&pageSize=1')
      .set(bearer(aliceToken))
      .expect(200);
    expect(response.body.data.map((entry: { id: string }) => entry.id)).toEqual(
      [second.id],
    );
    expect(response.body.pagination).toEqual({
      page: 1,
      pageSize: 1,
      total: 2,
      totalPages: 2,
    });
    const page2 = await request(app)
      .get('/api/requests?page=2&pageSize=1')
      .set(bearer(aliceToken))
      .expect(200);
    expect(page2.body.data[0].id).toBe(first.id);
  });
  it('opens own request and conceals another employee request with the same 404 as a missing ID', async () => {
    const own = await create();
    await request(app)
      .get(`/api/requests/${own.id}`)
      .set(bearer(aliceToken))
      .expect(200);
    const privateResponse = await request(app)
      .get(`/api/requests/${own.id}`)
      .set(bearer(bobToken))
      .expect(404);
    const missingResponse = await request(app)
      .get(`/api/requests/${randomUUID()}`)
      .set(bearer(bobToken))
      .expect(404);
    expect(privateResponse.body).toEqual(missingResponse.body);
  });
  it.each([
    'employeeId',
    'userId',
    'role',
    'status',
    'submittedAt',
    'reviewerId',
    'reviewedBy',
    'hrComment',
    'id',
  ])('rejects mass assignment of %s', async (field) => {
    await request(app)
      .post('/api/requests')
      .set(bearer(aliceToken))
      .send({ ...input, [field]: bob.id })
      .expect(400);
    expect(await db.hRRequest.count()).toBe(0);
  });
  it.each([
    { ...input, type: 'INVALID' },
    { ...input, subject: '   ' },
    { ...input, subject: 'a'.repeat(161) },
    { ...input, subject: 'letter\u0000subject' },
    { ...input, description: ' ' },
    { ...input, description: 'x'.repeat(5001) },
    { ...input, description: 'letter\u0000description' },
    { subject: 'Missing fields' },
  ])('rejects invalid request input', async (body) => {
    await request(app)
      .post('/api/requests')
      .set(bearer(aliceToken))
      .send(body)
      .expect(400);
  });
  it.each([
    '/api/requests?page=0',
    '/api/requests?pageSize=101',
    '/api/requests?page=1.5',
    '/api/requests?page=1&page=2',
    '/api/requests?employeeId=someone',
    '/api/requests/not-a-uuid',
    '/api/requests/%E0%A4%A',
  ])('validates params and query: %s', async (path) => {
    await request(app).get(path).set(bearer(aliceToken)).expect(400);
  });
  it('prevents HR from creating requests through employee routes', async () => {
    await request(app)
      .post('/api/requests')
      .set(bearer(hrToken))
      .send(input)
      .expect(403);
  });
});

describe('HR review and authorization', () => {
  it('forbids employees on every HR endpoint and cannot change state', async () => {
    const own = await create();
    await request(app)
      .get('/api/hr/requests')
      .set(bearer(aliceToken))
      .expect(403);
    await request(app)
      .get(`/api/hr/requests/${own.id}`)
      .set(bearer(aliceToken))
      .expect(403);
    await request(app)
      .patch(`/api/hr/requests/${own.id}/review`)
      .set(bearer(aliceToken))
      .send({ status: 'APPROVED' })
      .expect(403);
    expect(
      (await db.hRRequest.findUniqueOrThrow({ where: { id: own.id } })).status,
    ).toBe('PENDING');
  });
  it('requires authentication on employee and HR routes', async () => {
    await request(app).get('/api/requests').expect(401);
    await request(app).post('/api/requests').send(input).expect(401);
    await request(app).get(`/api/requests/${randomUUID()}`).expect(401);
    await request(app).get('/api/hr/requests').expect(401);
    await request(app).get(`/api/hr/requests/${randomUUID()}`).expect(401);
    await request(app)
      .patch(`/api/hr/requests/${randomUUID()}/review`)
      .send({ status: 'APPROVED' })
      .expect(401);
  });
  it('lists pending requests across employees and retrieves detail safely', async () => {
    const pending = await create();
    const reviewed = await create(bobToken);
    await request(app)
      .patch(`/api/hr/requests/${reviewed.id}/review`)
      .set(bearer(hrToken))
      .send({ status: 'APPROVED' })
      .expect(200);
    const response = await request(app)
      .get('/api/hr/requests?status=PENDING')
      .set(bearer(hrToken))
      .expect(200);
    expect(response.body.data.map((item: { id: string }) => item.id)).toEqual([
      pending.id,
    ]);
    const all = await request(app)
      .get('/api/hr/requests')
      .set(bearer(hrToken))
      .expect(200);
    expect(all.body.pagination.total).toBe(2);
    const detail = await request(app)
      .get(`/api/hr/requests/${pending.id}`)
      .set(bearer(hrToken))
      .expect(200);
    expect(detail.body.data.employee).toMatchObject({
      id: alice.id,
      employeeId: alice.employeeId,
    });
    expect(JSON.stringify(detail.body)).not.toContain('passwordHash');
  });
  it.each(['APPROVED', 'REJECTED'])(
    'persists %s, reviewer, timestamp and optional comment visible to the employee',
    async (status) => {
      const own = await create();
      const response = await request(app)
        .patch(`/api/hr/requests/${own.id}/review`)
        .set(bearer(hrToken))
        .send({ status, comment: '  Reviewed by HR  ' })
        .expect(200);
      expect(response.body.data).toMatchObject({
        status,
        reviewedBy: hr.id,
        hrComment: 'Reviewed by HR',
        reviewer: { id: hr.id },
      });
      expect(response.body.data.reviewedAt).toBeTruthy();
      const persisted = await db.hRRequest.findUniqueOrThrow({
        where: { id: own.id },
      });
      expect(persisted).toMatchObject({
        status,
        hrComment: 'Reviewed by HR',
        reviewedBy: hr.id,
      });
      const employeeView = await request(app)
        .get(`/api/requests/${own.id}`)
        .set(bearer(aliceToken))
        .expect(200);
      expect(employeeView.body.data).toMatchObject({
        status,
        hrComment: 'Reviewed by HR',
      });
      const employeeList = await request(app)
        .get('/api/requests')
        .set(bearer(aliceToken))
        .expect(200);
      expect(employeeList.body.data[0]).toMatchObject({
        status,
        hrComment: 'Reviewed by HR',
      });
      await request(app)
        .patch(`/api/hr/requests/${own.id}/review`)
        .set(bearer(hrToken))
        .send({
          status: status === 'APPROVED' ? 'REJECTED' : 'APPROVED',
          comment: 'overwrite',
        })
        .expect(409);
      expect(
        await db.hRRequest.findUniqueOrThrow({ where: { id: own.id } }),
      ).toEqual(persisted);
    },
  );
  it('allows review without comment', async () => {
    const own = await create();
    const response = await request(app)
      .patch(`/api/hr/requests/${own.id}/review`)
      .set(bearer(hrToken))
      .send({ status: 'APPROVED' })
      .expect(200);
    expect(response.body.data.hrComment).toBeNull();
  });
  it('allows only one concurrent review', async () => {
    const own = await create();
    const responses = await Promise.all(
      ['APPROVED', 'REJECTED'].map((status) =>
        request(app)
          .patch(`/api/hr/requests/${own.id}/review`)
          .set(bearer(hrToken))
          .send({ status, comment: status }),
      ),
    );
    expect(responses.map((response) => response.status).sort()).toEqual([
      200, 409,
    ]);
    const winner = responses.find((response) => response.status === 200)!;
    const persisted = await db.hRRequest.findUniqueOrThrow({
      where: { id: own.id },
    });
    expect(persisted.status).toBe(winner.body.data.status);
    expect(persisted.hrComment).toBe(winner.body.data.hrComment);
  });
  it.each([
    { status: 'PENDING' },
    { status: 'APPROVED', comment: 'x'.repeat(2001) },
    { status: 'APPROVED', comment: 'HR\u0000comment' },
    { status: 'REJECTED', reviewedBy: 'someone' },
    { status: 'REJECTED', reviewedAt: '2020-01-01' },
    {},
  ])('rejects invalid reviews', async (body) => {
    const own = await create();
    await request(app)
      .patch(`/api/hr/requests/${own.id}/review`)
      .set(bearer(hrToken))
      .send(body)
      .expect(400);
    expect(
      (await db.hRRequest.findUniqueOrThrow({ where: { id: own.id } })).status,
    ).toBe('PENDING');
  });
  it('validates HR filters and IDs, and handles missing requests', async () => {
    await request(app)
      .get('/api/hr/requests?status=UNKNOWN')
      .set(bearer(hrToken))
      .expect(400);
    await request(app)
      .get('/api/hr/requests/not-a-uuid')
      .set(bearer(hrToken))
      .expect(400);
    await request(app)
      .get(`/api/hr/requests/${randomUUID()}`)
      .set(bearer(hrToken))
      .expect(404);
    await request(app)
      .patch(`/api/hr/requests/${randomUUID()}/review`)
      .set(bearer(hrToken))
      .send({ status: 'APPROVED' })
      .expect(404);
  });
});

describe('HTTP security and errors', () => {
  it('adds Helmet and no-store headers', async () => {
    const response = await request(app)
      .get('/api/me')
      .set(bearer(aliceToken))
      .expect(200);
    expect(response.headers['x-content-type-options']).toBe('nosniff');
    expect(response.headers['content-security-policy']).toBeTruthy();
    expect(response.headers['cache-control']).toBe('no-store');
    expect(response.headers['x-powered-by']).toBeUndefined();
  });
  it('permits configured browser origins and mobile clients, rejects other browser origins', async () => {
    const response = await request(app)
      .get('/api/me')
      .set(bearer(aliceToken))
      .set('Origin', 'http://localhost:5173')
      .expect(200);
    expect(response.headers['access-control-allow-origin']).toBe(
      'http://localhost:5173',
    );
    await request(app)
      .get('/api/me')
      .set(bearer(aliceToken))
      .set('Origin', 'https://untrusted.example')
      .expect(403);
    await request(app)
      .options('/api/requests')
      .set('Origin', 'http://localhost:5173')
      .set('Access-Control-Request-Method', 'POST')
      .expect(204);
  });
  it('rate limits login including malformed JSON and ignores spoofed forwarded IPs', async () => {
    const limited = createApp(
      db,
      { ...config, LOGIN_RATE_LIMIT_MAX: 2 },
      logger,
    );
    await request(limited)
      .post('/api/auth/login')
      .set('Content-Type', 'application/json')
      .send('{broken')
      .expect(400);
    await request(limited)
      .post('/api/auth/login')
      .send({ email: alice.email, password: 'wrong' })
      .expect(401);
    const response = await request(limited)
      .post('/api/auth/login')
      .set('X-Forwarded-For', '203.0.113.42')
      .send({ email: alice.email, password })
      .expect(429);
    expect(response.body.error.code).toBe('RATE_LIMITED');
    expect(response.headers['retry-after']).toBeTruthy();
  });
  it('returns consistent JSON for invalid JSON, oversized payloads, and unknown routes', async () => {
    const malformed = await request(app)
      .post('/api/auth/login')
      .set('Content-Type', 'application/json')
      .send('{bad')
      .expect(400);
    expect(malformed.body.error.code).toBe('INVALID_BODY');
    await request(app)
      .post('/api/auth/login')
      .send({ password: 'x'.repeat(40000) })
      .expect(400);
    const missing = await request(app).get('/unknown').expect(404);
    expect(missing.body.error.code).toBe('NOT_FOUND');
  });
  it('logs HTTP requests and review actions without credentials, query values, or descriptions', async () => {
    await login(alice.email);
    const own = await create();
    await request(app)
      .patch(`/api/hr/requests/${own.id}/review`)
      .set(bearer(hrToken))
      .send({ status: 'APPROVED', comment: 'private HR comment' })
      .expect(200);
    await request(app)
      .get('/api/requests?secret=private-query-value')
      .set(bearer(aliceToken))
      .expect(400);
    const output = logs.join('');
    expect(output).toContain('HTTP request');
    expect(output).toContain('hr_request_reviewed');
    for (const secret of [
      password,
      aliceToken,
      hrToken,
      config.JWT_SECRET,
      alice.passwordHash,
      input.description,
      'private HR comment',
      'private-query-value',
      'Authorization',
    ])
      expect(output).not.toContain(secret);
  });
});
