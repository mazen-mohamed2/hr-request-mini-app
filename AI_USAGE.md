# AI usage

I personally wrote and edited backend and Flutter implementation code. I owned the architecture, security decisions, important implementation choices, corrections and final validation. I reviewed AI output, changed code that needed work and checked the results before accepting it.

I used ChatGPT to break down requirements and discuss architecture, tradeoffs and security. I used OpenAI Codex extensively to speed up scaffolding, repetitive coding, tests, debugging, review and iteration. The initial backend and Flutter implementations, test scaffolding and integration runner were mostly AI-generated drafts. I worked on that code throughout development and remain responsible for every submitted line.

## Important instructions

These are shortened examples of instructions I used:

- "Enforce employee ownership on the server. Never trust employeeId from the request body."
- "Use the captured backend API contract for Flutter. Do not invent response shapes."
- "Test the production Dio client against real Express and PostgreSQL without mocking HTTP."
- "Review RBAC, IDOR, validation, concurrency and repository hygiene before submission."

## Issues I corrected

**NUL input validation.** Initial validation allowed PostgreSQL-incompatible NUL characters to reach the database and cause a server error. Validation now rejects them with 400 instead of 500. Backend regression tests cover NUL characters in subjects, descriptions and HR comments.

**HR pagination.** After another reviewer emptied the last pending page, the UI could show "Page 2 of 1." The fix clamps the page number and fetches the last valid page. A widget regression checks the page number and refreshed data.

**Integration runner reliability.** Inherited environment values and cleanup errors made the runner less predictable. It now sets isolated configuration, restores the previous environment, attempts cleanup steps independently and waits for PostgreSQL's TCP listener. Real integration runs and intentional failure checks verified error propagation and cleanup.

## How I checked the result

I ran backend typechecking, API/integration tests, the compiled build, formatting and npm audit. I also checked clean dependency installation, migrations and seed data. Security tests cover RBAC, IDOR, invalid/expired JWTs, privileged-field injection, repeated/concurrent review and safe validation errors and logs.

For Flutter, I ran dependency resolution, formatting, analysis and unit/widget/state tests. The live suite uses production Dio, repositories and Riverpod state over real HTTP with Express, Prisma and isolated PostgreSQL. Only token storage is simulated in that host test. I also checked setup from a clean submission copy.

Android/iOS native builds and secure storage on a device remain unverified because the required native tooling was unavailable.
