import 'dotenv/config';

export function testDatabaseUrl() {
  const value = process.env.TEST_DATABASE_URL;
  if (!value)
    throw new Error(
      'TEST_DATABASE_URL is required. Copy .env.example to .env and start the test database.',
    );
  const url = new URL(value);
  if (
    !['postgres:', 'postgresql:'].includes(url.protocol) ||
    !['localhost', '127.0.0.1', '[::1]'].includes(url.hostname) ||
    !url.pathname.endsWith('_test') ||
    url.searchParams.get('schema') !== 'public'
  ) {
    throw new Error(
      'Tests require a local PostgreSQL database ending in _test with schema=public.',
    );
  }
  if (process.env.DATABASE_URL) {
    const developmentUrl = new URL(process.env.DATABASE_URL);
    if (
      url.port === developmentUrl.port &&
      url.pathname === developmentUrl.pathname
    )
      throw new Error('Test and development databases must be separate.');
  }
  return value;
}
