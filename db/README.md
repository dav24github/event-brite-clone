# Eventbrite DB (M1)

PostgreSQL schema, seed data, constraint tests and queries for the Eventbrite clone. Plain SQL, no ORM.

> Work in progress: S01 Step 3. The full README comes in Step 5.

## Run

```bash
createdb eventbrite_lab                                    # once
psql -v ON_ERROR_STOP=1 -d eventbrite_lab -f db/run_all.sql # rebuild schema + seed
psql -d eventbrite_lab -f db/tests/constraint_tests.sql     # every statement must fail
```

## Layout

| Path | Step | What |
|---|---|---|
| `docs/01-business-rules.md` | 3.1 | actors, entities, rules (`BR-*`), decisions D1–D9 |
| `docs/02-design.md` | 3.2 | ERD + 1NF → 3NF check |
| `schema.sql` | 3.3 | types and tables, named constraints tagged with rule IDs |
| `seed.sql` | 3.4 | deterministic seed with planted edge cases |
| `tests/constraint_tests.sql` | 3.5 | one violation per constraint |
| `queries/` | 3.6 | 15 business questions |
| `docs/03-performance.md` | 4.2 | indexes and `EXPLAIN ANALYZE`, before/after |
| `docs/04-concurrency.md` | 4.3 | oversell race, locks, isolation levels |
