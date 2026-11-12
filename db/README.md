# Eventbrite DB (M1)

The PostgreSQL database for the Eventbrite clone: business rules, design, schema, seed data, constraint tests and business queries. Plain SQL, no ORM. Built database-first, so the rules that must never break (no overselling, no reactivating a cancelled ticket, no editing a price after sale) are enforced by the database itself, not only by the API that will sit on top of it.

> **Status:** schema, seed, constraint tests, business queries and window functions are done. Next: indexes and `EXPLAIN ANALYZE` (4.2), then the concurrency lab write-up (4.3).

## What's in it

- **8 tables:** `users`, `organizers`, `categories`, `venues`, `events`, `ticket_types`, `reservations`, `tickets`. Every constraint is named and tagged with the business rule it enforces (`-- BR-T3`).
- **20 triggers and 17 functions** for the rules a `CHECK` can't express: allowed status transitions (draft → published → cancelled/completed), publish checks, cancelling an event cascading to its reservations and tickets, immutable columns, and no hard deletes of reservations or tickets.
- **`reserve_tickets()`**, the checkout in one transaction. It locks the event `FOR SHARE` and each ticket type `FOR UPDATE` in id order, so two buyers can't both get the last ticket, a checkout can't slip past an event being cancelled, and the locks can't deadlock. Both races were reproduced and tested in two `psql` sessions.
- **A deterministic seed:** 1,000 users, 123 events, about 3,000 reservations and 7,700 tickets, the same on every run (`setseed`). Four planted edge cases have `[Edge]` titles: a sold-out ticket type, an event with no sales, a cancelled event, and a user who is both organizer and attendee.
- **105 constraint tests:** one deliberate violation per constraint, trigger and function rule, each with the error it must raise.
- **15 business queries** for attendees, organizers and the platform (browse, my tickets, sell-through, daily reservations in the event's time zone, repeat attendees…), each with its expected result on the seed. Three are verified by writing them two different ways and comparing with `EXCEPT`.

## Run

Needs PostgreSQL 16 or later (built on 18). From the repo root:

```bash
createdb -U postgres eventbrite_lab                                          # once
psql -U postgres -v ON_ERROR_STOP=1 -d eventbrite_lab -f db/run_all.sql       # rebuild schema + seed (~15 s)
psql -U postgres -d eventbrite_lab -f db/tests/constraint_tests.sql           # every test must fail with its expected error
psql -U postgres -d eventbrite_lab -f db/queries/q08-sell-through.sql         # any query; compare with its Expected: line
```

`run_all.sql` drops and recreates the `eventbrite` schema, so it's safe to re-run. Run the tests and the queries on a fresh `run_all.sql`: the tests change some rows on purpose.

## Design

The ERD (Mermaid, renders on GitHub) and the 1NF → 3NF check are in [docs/02-design.md](docs/02-design.md). The main decisions, each with its reason, are D1–D9 in [docs/01-business-rules.md](docs/01-business-rules.md#4-decisions), for example:

- an organizer is a 1:1 extension of a user, sharing its id (D1);
- one reservation holds many tickets, and each ticket has its own random QR code (D2, D8);
- available tickets are computed, not stored, and protected by a row lock (D4);
- times are `TIMESTAMPTZ` plus the event's IANA time zone (D7);
- reservations and tickets are never deleted; accounts are anonymized instead (D9).

## Layout

| Path | Step | What |
|---|---|---|
| [docs/01-business-rules.md](docs/01-business-rules.md) | 3.1 | actors, entities, rules (`BR-*`), decisions D1–D9 |
| [docs/02-design.md](docs/02-design.md) | 3.2 | ERD + 1NF → 3NF check |
| [docs/03-schema-checklist.md](docs/03-schema-checklist.md) | 3.3 | every rule sorted by table and mechanism; what's enforced where |
| [schema.sql](schema.sql) | 3.3 | types, tables, indexes, triggers and functions |
| [seed.sql](seed.sql) | 3.4 | deterministic seed with planted edge cases |
| [tests/constraint_tests.sql](tests/constraint_tests.sql) | 3.5 | 105 tests, one violation each |
| [queries/](queries/) | 3.6 | 15 business questions, with expected results ([index](queries/README.md)) |
| [queries/w01-window-functions.sql](queries/w01-window-functions.sql) | 4.1 | running totals, top-N per group, `LAG` |
| `docs/05-performance.md` | 4.2 | indexes and `EXPLAIN ANALYZE`, before/after *(next)* |
| `docs/04-concurrency.md` | 4.3 | oversell race, locks, isolation levels *(next)* |

## Not in the database (on purpose)

Some rules belong to the API (M2), and the checklist marks them `app`: rejecting a local time that falls in a daylight-saving gap or overlap, showing drafts only to their organizer, and showing an online event's link only to ticket holders.
