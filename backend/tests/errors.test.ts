import { describe, expect, it } from 'vitest';
import express from 'express';
import request from 'supertest';
import pino from 'pino';
import { Writable } from 'node:stream';
import { errorHandler } from '../src/errors';
import { loadConfig } from '../src/config';
import { createLogger } from '../src/logger';

describe('configuration and internal errors', () => {
  it('hides database errors and stack traces from responses and logs', async () => {
    const logs: string[] = [];
    const logger = pino(
      new Writable({
        write(chunk, _encoding, callback) {
          logs.push(chunk.toString());
          callback();
        },
      }),
    );
    const app = express();
    app.set('env', 'production');
    app.get('/fail', async () => {
      throw new Error(
        'postgresql://secret:password@db/private sensitive-description',
      );
    });
    app.use(errorHandler(logger));
    const response = await request(app).get('/fail').expect(500);
    expect(response.body).toEqual({
      error: {
        code: 'INTERNAL_ERROR',
        message: 'An unexpected server error occurred.',
      },
    });
    expect(logs.join('')).toContain('server_error');
    expect(logs.join('')).not.toMatch(
      /postgresql|secret|password|sensitive-description/,
    );
  });
  it('rejects missing/placeholder secrets without printing environment values', () => {
    expect(() =>
      loadConfig({
        DATABASE_URL: 'postgresql://private-password@localhost/db',
        JWT_SECRET: 'secret',
      }),
    ).toThrow('JWT_SECRET');
    expect(() =>
      loadConfig({
        DATABASE_URL: 'postgresql://user:password@localhost/db',
        JWT_SECRET: 'replace-with-a-random-secret-at-least-32-characters',
      }),
    ).toThrow();
  });
  it('redacts credentials and request bodies from structured logs', () => {
    const logs: string[] = [];
    const logger = createLogger(
      { LOG_LEVEL: 'info' },
      new Writable({
        write(chunk, _encoding, callback) {
          logs.push(chunk.toString());
          callback();
        },
      }),
    );
    logger.info(
      {
        password: 'private-password',
        passwordHash: 'private-hash',
        token: 'private-token',
        authorization: 'private-header',
        DATABASE_URL: 'private-url',
        JWT_SECRET: 'private-secret',
        req: {
          headers: { authorization: 'private-header' },
          body: { description: 'private-description' },
        },
      },
      'redaction check',
    );
    expect(logs.join('')).toContain('[REDACTED]');
    expect(logs.join('')).not.toContain('private-');
  });
});
