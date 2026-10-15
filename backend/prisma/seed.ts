import 'dotenv/config';
import { PrismaClient } from '@prisma/client';
import bcrypt from 'bcrypt';

const db = new PrismaClient();

async function main() {
  if (process.env.NODE_ENV === 'production') {
    throw new Error('Development seed is disabled in production.');
  }
  const passwordHash = await bcrypt.hash('DevPassword123!', 12);
  const users = [
    {
      employeeId: 'EMP001',
      name: 'Alice Employee',
      email: 'alice@example.com',
      department: 'Engineering',
      jobTitle: 'Software Engineer',
      role: 'EMPLOYEE' as const,
    },
    {
      employeeId: 'EMP002',
      name: 'Bob Employee',
      email: 'bob@example.com',
      department: 'Finance',
      jobTitle: 'Accountant',
      role: 'EMPLOYEE' as const,
    },
    {
      employeeId: 'HR001',
      name: 'Hana HR',
      email: 'hr@example.com',
      department: 'Human Resources',
      jobTitle: 'HR Specialist',
      role: 'HR' as const,
    },
  ];
  for (const user of users) {
    await db.user.upsert({
      where: { email: user.email },
      create: { ...user, passwordHash },
      update: {},
    });
  }
  console.log('Development seed ready: two employees and one HR user.');
}

main()
  .catch(() => {
    console.error(
      'Seed failed. Check database availability and migration status.',
    );
    process.exitCode = 1;
  })
  .finally(() => db.$disconnect());
