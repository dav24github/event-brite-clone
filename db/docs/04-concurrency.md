# 04 · Concurrency: two buyers, one last ticket

<!--
How to fill this file (delete this comment when done):
- One section per experiment in labs/04-concurrency.sql. For each: what I ran, what I saw (paste the psql output of both sessions, short), why, and the fix.
- Write it so you can say it out loud in an interview in 2 minutes. The summary at the top is that answer.
-->

How the Eventbrite database stops overselling when many people buy at the same time. Every race here was reproduced in two `psql` sessions with [`labs/04-concurrency.sql`](../labs/04-concurrency.sql).

## Summary

_Five lines, in your words: the race, the two fixes, which one `reserve_tickets()` uses and why, and what the API still has to do. This is the interview answer._

## The race

_L1: read, then write. A timeline of the two sessions, the result (2 sales, counter says 1), and why the lock B waited on didn't help._

| Step | Session A | Session B |
|---|---|---|
| 1 | | |
| 2 | | |
| 3 | | |

## Fix 1: an atomic conditional `UPDATE`

_L2: the statement, `UPDATE 1` vs `UPDATE 0`, and why B gets 0 (READ COMMITTED re-checks the WHERE on the newest row version)._

## The safety net: a `CHECK`

_L3: what happened. Then: why the real schema has no such CHECK (D4, availability is computed), what protects it instead, and the trade-off._

## Fix 2: `SELECT … FOR UPDATE`, in `reserve_tickets()`

_L4: what B saw while waiting (pg_stat_activity) and after. Point to the lock in [`schema.sql`](../schema.sql)._

_The lock order `reserve_tickets()` uses (event `FOR SHARE` → ticket types `FOR UPDATE` in id order) and what each lock prevents. L5: checkout vs event cancel._

## Deadlocks

_L6: what happened, the error, and how a fixed lock order prevents it._

## Isolation levels

_L7 and L8. Fill the table from what you saw, and from the PostgreSQL docs (Transaction Isolation)._

| Anomaly | What it is | READ COMMITTED | REPEATABLE READ | SERIALIZABLE |
|---|---|---|---|---|
| Dirty read | | | | |
| Non-repeatable read | | | | |
| Phantom | | | | |
| Lost update | | | | |
| Write skew | | | | |

_Write skew (L8): the rule, why no lock met, the 40001 error, and the retry._

## Not waiting forever

_L9: `NOWAIT`, `lock_timeout`, `SKIP LOCKED`, and where each one will be used (job queues in S04, ticket drops in S06)._

## Savepoints

_L10, two or three lines._

## Optimistic vs pessimistic

_L11: the version column. When each one fits: a ticket drop on one hot row vs an organizer editing a form._

## MVCC

_L12: why a reader doesn't wait for a writer, in two or three lines._

## What the API (M2) must do

_For example: retry the whole transaction on `40001` and `40P01`; never compute availability in the app; an idempotency key so a double click doesn't buy twice._
