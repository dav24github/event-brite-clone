# Eventbrite Clone

An event-ticketing platform. Organizers create events and sell tickets; attendees discover events and get digital tickets. It's my main full-stack project, and I build it one milestone at a time.

> **Status:** restarted on 2026-10-01, database-first. Milestone **M1 (database)** is in progress.

## Milestones

| # | Milestone | Status |
| --- | --- | --- |
| M1 | Database: business rules, ERD, PostgreSQL schema, seed data, queries, constraint tests, performance and concurrency labs | in progress |
| M2 | Core API (NestJS): events, ticket types, auth and roles, concurrency-safe reservations, tests, CI | planned |
| M3 | MVP live: Next.js frontend, end-to-end tests, Docker, CI/CD, monitoring | planned |
| M4 | Paid tickets: Stripe, webhooks, background jobs, emails with QR tickets | planned |
| M5 | AI features: event drafting, semantic search, event Q&A, with evals | planned |
| M6 | Ticket drops at scale: holds, caching, rate limits, live availability, load tests | planned |

Full scope by release: [docs/scope.md](docs/scope.md) · Decisions: [docs/adr/](docs/adr/)

## Repository layout

```
db/         PostgreSQL schema, seed data, queries, tests and design docs (M1)
backend/    NestJS API (M2+)
frontend/   Next.js app (M3+)
docs/       scope, API design, architecture decision records
```

## How I use AI on this project

I write the code for anything I'm still learning, and use AI as a reviewer and tutor. Where AI generated code, I reviewed it and can explain it line by line.
