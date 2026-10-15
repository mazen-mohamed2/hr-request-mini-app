-- CreateSchema
CREATE SCHEMA IF NOT EXISTS "public";

-- CreateEnum
CREATE TYPE "Role" AS ENUM ('EMPLOYEE', 'HR');

-- CreateEnum
CREATE TYPE "RequestType" AS ENUM ('EMPLOYMENT_LETTER', 'SALARY_CERTIFICATE', 'PERSONAL_INFORMATION_CHANGE', 'OTHER');

-- CreateEnum
CREATE TYPE "RequestStatus" AS ENUM ('PENDING', 'APPROVED', 'REJECTED');

-- CreateTable
CREATE TABLE "User" (
    "id" UUID NOT NULL,
    "employeeId" VARCHAR(40) NOT NULL,
    "name" VARCHAR(120) NOT NULL,
    "email" VARCHAR(254) NOT NULL,
    "passwordHash" VARCHAR(60) NOT NULL,
    "department" VARCHAR(120) NOT NULL,
    "jobTitle" VARCHAR(120) NOT NULL,
    "role" "Role" NOT NULL DEFAULT 'EMPLOYEE',
    "createdAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(3) NOT NULL,

    CONSTRAINT "User_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "HRRequest" (
    "id" UUID NOT NULL,
    "employeeId" UUID NOT NULL,
    "type" "RequestType" NOT NULL,
    "subject" VARCHAR(160) NOT NULL,
    "description" VARCHAR(5000) NOT NULL,
    "status" "RequestStatus" NOT NULL DEFAULT 'PENDING',
    "hrComment" VARCHAR(2000),
    "reviewedBy" UUID,
    "submittedAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "reviewedAt" TIMESTAMPTZ(3),
    "createdAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(3) NOT NULL,

    CONSTRAINT "HRRequest_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "User_employeeId_key" ON "User"("employeeId");

-- CreateIndex
CREATE UNIQUE INDEX "User_email_key" ON "User"("email");

-- CreateIndex
CREATE INDEX "HRRequest_employeeId_submittedAt_id_idx" ON "HRRequest"("employeeId", "submittedAt" DESC, "id" DESC);

-- CreateIndex
CREATE INDEX "HRRequest_status_submittedAt_id_idx" ON "HRRequest"("status", "submittedAt" DESC, "id" DESC);

-- CreateIndex
CREATE INDEX "HRRequest_submittedAt_id_idx" ON "HRRequest"("submittedAt" DESC, "id" DESC);

-- AddForeignKey
ALTER TABLE "HRRequest" ADD CONSTRAINT "HRRequest_employeeId_fkey" FOREIGN KEY ("employeeId") REFERENCES "User"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "HRRequest" ADD CONSTRAINT "HRRequest_reviewedBy_fkey" FOREIGN KEY ("reviewedBy") REFERENCES "User"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
