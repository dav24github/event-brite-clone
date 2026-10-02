# ADR-0001: Restart the project, database-first

- **Status:** accepted
- **Date:** 2026-10-01

## Context

There were two earlier attempts. In August 2026 I built NestJS + GraphQL resolvers, auth with a Redis cache, uploads and a multi-tenant design. In September 2026 I built a Prisma schema with two migrations, Better Auth wiring and an empty events module. Neither has a single commit, and neither reached a working ticket flow.

Both started from the framework and a broad architecture: GraphQL *and* REST, Redis Redlock, two payment gateways, queues, WebSockets and multi-tenancy. That plan was ahead of my skills. I couldn't yet justify or maintain most of it, and it contradicted my own MVP requirements.

Since then I've studied relational design and SQL, and the most valuable next step is to apply that myself.

## Options considered

1. Continue the September attempt.
2. Restart: design the database by hand in SQL first, then build the API on top of it.

## Decision

Option 2. First I design the database in plain SQL in `db/`, with business rules, constraints, tests, and performance and concurrency labs. The API (M2) maps onto that schema afterwards. Both earlier attempts stay in `_archive/` (ignored by git) for reference.

## Consequences

- The first milestone is data only. There's no UI or API to show until M2–M3. Accepted.
- Every later feature from the original requirements stays in `docs/scope.md`, scheduled by milestone.
- **This is the last restart.** From now on, a wrong design gets fixed with a migration and an ADR, not by starting over.
