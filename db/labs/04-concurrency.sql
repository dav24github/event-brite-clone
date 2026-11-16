-- =============================================================================
-- labs/04-concurrency.sql · transactions and concurrency lab (S01 step 4.3)
-- Two buyers, one last ticket. Reproduce each race in TWO psql sessions,
-- then fix it. The results go in docs/04-concurrency.md.
--
-- Run in eventbrite_lab, on a FRESH run_all.sql (L4 and L5 change seed rows):
--   open two terminals, side by side, both:
--     psql -U postgres -d eventbrite_lab
--     SET search_path TO eventbrite;
--   call the left one A and the right one B (\set PROMPT1 'A> ' helps)
--
-- How to read the steps:
--   A1, B1, A2 ... = run in that session, in that order. Don't skip ahead:
--   the whole point is the ORDER in which the two sessions run.
--   "waits" = the prompt doesn't come back. That's a lock. Go to the other session.
--   Copy each session's output (or a screenshot) into the doc as you go.
--
-- Default isolation level is READ COMMITTED: each statement sees the data
-- committed before IT started (not before the transaction started).
-- =============================================================================


-- -----------------------------------------------------------------------------
-- 0. Setup: a scratch table WITH a sold counter                    (session A)
-- -----------------------------------------------------------------------------
-- Why:      your real schema computes availability from active tickets (D4):
--           there's no `sold` column to UPDATE or CHECK. The textbook race and
--           fix 1 need one, so build a tiny copy of the "stored counter" design.
-- Steps:    CREATE SCHEMA lab;
--           lab.ticket_types (id INT PRIMARY KEY, name TEXT, capacity INT NOT NULL,
--                             sold INT NOT NULL DEFAULT 0)
--           lab.sales (sale_id INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
--                      ticket_type_id INT REFERENCES lab.ticket_types, buyer TEXT)
--           two rows: (1, 'General', 10, 9) and (2, 'VIP', 10, 0)
--           -> General has exactly ONE ticket left.
-- Reset between experiments:
--           UPDATE lab.ticket_types SET sold = 9 WHERE id = 1;  TRUNCATE lab.sales;


-- -----------------------------------------------------------------------------
-- L1 · The oversell: read, then write                       (lost update)
-- -----------------------------------------------------------------------------
-- What the app does: read sold, check sold < capacity in code, then write sold + 1.
-- A1: BEGIN;  SELECT sold, capacity FROM lab.ticket_types WHERE id = 1;   -> 9, 10: "1 left"
-- B1: BEGIN;  the same SELECT                                             -> also 9, 10
-- A2: UPDATE lab.ticket_types SET sold = 10 WHERE id = 1;    (9 + 1, computed "in the app")
--     INSERT INTO lab.sales (ticket_type_id, buyer) VALUES (1, 'A');
-- B2: the same UPDATE (sold = 10) and INSERT with buyer 'B'  -> waits (A holds the row lock)
-- A3: COMMIT;                                                -> B2 finishes
-- B3: COMMIT;
-- Check:    SELECT sold FROM lab.ticket_types WHERE id = 1;  -> 10
--           SELECT count(*) FROM lab.sales;                  -> 2
-- Expected: 2 tickets sold, the counter says 1. B's write overwrote A's:
--           a LOST UPDATE. With capacity 10, 11 people now hold a ticket.
-- Watch:    the lock in B2 didn't save you: B waited, then wrote a value it
--           computed from a stale read in B1.


-- -----------------------------------------------------------------------------
-- L2 · Fix 1: one atomic conditional UPDATE
-- -----------------------------------------------------------------------------
-- Idea:     no separate read. The check and the write are ONE statement:
--             UPDATE lab.ticket_types SET sold = sold + 1
--              WHERE id = 1 AND sold + 1 <= capacity;
--           psql prints UPDATE 1 (you got it) or UPDATE 0 (sold out). The app
--           inserts the sale only after UPDATE 1.
-- Steps:    reset, then
-- A1: BEGIN;  the conditional UPDATE                         -> UPDATE 1
-- B1: BEGIN;  the same                                       -> waits
-- A2: INSERT the sale for 'A';  COMMIT;
-- B1 returns:                                                -> UPDATE 0
-- B2: ROLLBACK;  (no sale: the app saw 0 rows)
-- Expected: sold = 10, one sale.
-- Why B got 0: under READ COMMITTED, a blocked UPDATE re-checks its WHERE
--           against the NEWEST version of the row once the lock is released
--           (sold is now 10, 10 + 1 <= 10 is false). Write this in the doc.


-- -----------------------------------------------------------------------------
-- L3 · The safety net: a CHECK
-- -----------------------------------------------------------------------------
-- Steps:    reset to sold = 10 (sold out), then
--           ALTER TABLE lab.ticket_types ADD CONSTRAINT ck_lab_sold_le_capacity
--             CHECK (sold <= capacity);
--           Run L1's buggy code again, but with SET sold = sold + 1 (no condition).
-- Expected: ERROR, violates ck_lab_sold_le_capacity. Even buggy code can't oversell.
-- For the doc: your real schema can't have this CHECK (no sold column, D4).
--           What protects it instead? (the FOR UPDATE lock in reserve_tickets(),
--           plus the quantity trigger.) What did you gain and lose with D4?


-- -----------------------------------------------------------------------------
-- L4 · Fix 2: SELECT ... FOR UPDATE, on the REAL schema
-- -----------------------------------------------------------------------------
-- Setup:    ticket type 241 = General of event 122 '[Edge] No Sales Workshop',
--           50 tickets, none sold. Make it the last ticket:
--             UPDATE ticket_types SET quantity = 1 WHERE ticket_type_id = 241;
-- A1: BEGIN;  SELECT reserve_tickets(1, 122, '{"241": 1}');   -> a reference code
-- B1: BEGIN;  SELECT reserve_tickets(2, 122, '{"241": 1}');   -> waits
-- A2: COMMIT;
-- B1 returns:                       -> ERROR: Not enough tickets available ...
-- B2: ROLLBACK;
-- Look:     while B waits, in a THIRD session:
--             SELECT pid, state, wait_event_type, left(query, 60)
--               FROM pg_stat_activity WHERE datname = 'eventbrite_lab';
--           B shows wait_event_type = Lock.
-- For the doc: point to the line in schema.sql that takes the lock
--           (reserve_tickets, ticket types FOR UPDATE in id order), and say why
--           it's the counting of active tickets AFTER the lock that makes it safe.


-- -----------------------------------------------------------------------------
-- L5 · Checkout vs event cancel                    (replay of the 3.3 test)
-- -----------------------------------------------------------------------------
-- Setup:    UPDATE ticket_types SET quantity = 50 WHERE ticket_type_id = 241;
-- A1: BEGIN;  SELECT reserve_tickets(3, 122, '{"241": 2}');   -> a code
-- B1: UPDATE events SET status = 'cancelled', cancelled_at = now(),
--            cancellation_reason = 'Lab' WHERE event_id = 122;   -> waits
-- A2: COMMIT;                       -> B1 finishes
-- Check:    the reservation A made is now cancelled, and its 2 tickets too
--           (the cancel cascade trigger ran AFTER A's commit).
-- Why:      reserve_tickets() locks the event FOR SHARE; the UPDATE needs a
--           stronger lock, so it waits. Without it: a confirmed reservation on a
--           cancelled event.


-- -----------------------------------------------------------------------------
-- L6 · A deadlock, and the lock order that prevents it
-- -----------------------------------------------------------------------------
-- A1: BEGIN;  UPDATE lab.ticket_types SET sold = sold + 1 WHERE id = 1;
-- B1: BEGIN;  UPDATE lab.ticket_types SET sold = sold + 1 WHERE id = 2;
-- A2: UPDATE ... WHERE id = 2;                               -> waits for B
-- B2: UPDATE ... WHERE id = 1;                               -> waits for A ... about
--     1 second later (deadlock_timeout): ERROR: deadlock detected. One of the two
--     is aborted; the other one continues.
-- A3/B3: ROLLBACK; in both.
-- Fix:      both lock in the SAME order before writing:
--             SELECT id FROM lab.ticket_types WHERE id IN (1, 2) ORDER BY id FOR UPDATE;
--           Repeat A1..B2 with that first: B just waits, no deadlock.
-- For the doc: reserve_tickets() locks ticket types "in id order" for exactly this
--           reason (a checkout with types 12 and 13 vs one with 13 and 12).


-- -----------------------------------------------------------------------------
-- L7 · Non-repeatable read: READ COMMITTED vs REPEATABLE READ
-- -----------------------------------------------------------------------------
-- A1: BEGIN;  SELECT sold FROM lab.ticket_types WHERE id = 2;         -> 0
-- B1: UPDATE lab.ticket_types SET sold = 5 WHERE id = 2;    (autocommit, no BEGIN)
-- A2: the same SELECT                                                 -> 5
-- A3: COMMIT;
-- Same thing, but A1 is BEGIN ISOLATION LEVEL REPEATABLE READ;
--           A2 still sees the old value: the snapshot is taken at the first
--           statement and kept until COMMIT.
-- Try:      under REPEATABLE READ, A2 = UPDATE ... SET sold = sold + 1 WHERE id = 2
--           after B changed the row -> ERROR: could not serialize access due to
--           concurrent update. Postgres refuses the lost update instead of allowing it.


-- -----------------------------------------------------------------------------
-- L8 · Write skew: SERIALIZABLE, and the retry
-- -----------------------------------------------------------------------------
-- Rule:     an event may sell at most 10 tickets IN TOTAL across General and VIP.
--           The app checks it by counting lab.sales, then inserts one sale.
-- Setup:    TRUNCATE lab.sales; insert 9 sales (any types)  -> 1 left in total
-- A1: BEGIN ISOLATION LEVEL REPEATABLE READ;  SELECT count(*) FROM lab.sales;  -> 9
-- B1: the same                                                                -> 9
-- A2: INSERT a sale on type 1;   B2: INSERT a sale on type 2;
-- A3: COMMIT;   B3: COMMIT;       -> both succeed: 11 sales. That's WRITE SKEW:
--           each one read the same data and wrote a DIFFERENT row, so no lock
--           ever met.
-- Now repeat with BEGIN ISOLATION LEVEL SERIALIZABLE;
--           -> B3 (or an earlier B statement): ERROR: could not serialize access
--              ..., SQLSTATE 40001.
-- Retry:    B: ROLLBACK; then run B's whole transaction again from BEGIN.
--           Now the count is 10, the app refuses. That retry loop is the APP's
--           job (M2): on 40001, retry the whole transaction a few times.
-- For the doc: the other fix is a lock on something both must touch (the event
--           row FOR UPDATE), which is what reserve_tickets() does instead.


-- -----------------------------------------------------------------------------
-- L9 · Not waiting forever: NOWAIT, lock_timeout, SKIP LOCKED   (concept, short)
-- -----------------------------------------------------------------------------
-- A1: BEGIN;  SELECT * FROM lab.ticket_types WHERE id = 1 FOR UPDATE;   (keep it open)
-- B1: SELECT * FROM lab.ticket_types WHERE id = 1 FOR UPDATE NOWAIT;    -> error at once
-- B2: SET lock_timeout = '2s';  the same without NOWAIT                -> error after 2 s
-- B3: SELECT * FROM lab.ticket_types FOR UPDATE SKIP LOCKED;           -> only row 2
-- A2: ROLLBACK;  B: RESET lock_timeout;
-- For the doc: SKIP LOCKED is how job queues hand each worker a different row
--           (S04 background jobs). NOWAIT/lock_timeout: fail fast instead of
--           piling up waiting requests during a ticket drop (S06).


-- -----------------------------------------------------------------------------
-- L10 · Savepoints                                        (one session is enough)
-- -----------------------------------------------------------------------------
-- A: BEGIN;  INSERT a sale ('kept');
--    SAVEPOINT before_bad;
--    INSERT a sale with ticket_type_id 99  -> ERROR (FK). The transaction is now
--    "aborted": every statement fails until you roll back.
--    ROLLBACK TO SAVEPOINT before_bad;   INSERT a sale ('also kept');   COMMIT;
-- Check:    both good sales are there, the bad one isn't.


-- -----------------------------------------------------------------------------
-- L11 · Optimistic locking: a version column              (no lock is held)
-- -----------------------------------------------------------------------------
-- Setup:    ALTER TABLE lab.ticket_types ADD COLUMN version INT NOT NULL DEFAULT 1;
-- A1: SELECT sold, version FROM lab.ticket_types WHERE id = 2;     -> remember v
-- B1: the same                                                     -> the same v
-- B2: UPDATE lab.ticket_types SET sold = sold + 1, version = version + 1
--      WHERE id = 2 AND version = <v>;                             -> UPDATE 1
-- A2: the same UPDATE with the same <v>                            -> UPDATE 0
--     0 rows = someone changed it since you read it: re-read and retry.
-- For the doc: optimistic (version, no waiting, retry on conflict) vs pessimistic
--           (FOR UPDATE, wait your turn). Which fits a ticket drop with 1,000
--           buyers on one row, and which fits an organizer editing an event form?


-- -----------------------------------------------------------------------------
-- L12 · MVCC, seen directly                                          (optional)
-- -----------------------------------------------------------------------------
-- A1: BEGIN;  UPDATE lab.ticket_types SET sold = 7 WHERE id = 2;   (don't commit)
-- B1: SELECT xmin, xmax, sold FROM lab.ticket_types WHERE id = 2;
--     B still reads the OLD version, and doesn't wait: readers don't block writers.
--     xmax is A's transaction id: "this version is being replaced by A".
-- A2: COMMIT;   B2: the same SELECT -> the new version, new xmin.


-- -----------------------------------------------------------------------------
-- Cleanup
-- -----------------------------------------------------------------------------
-- DROP SCHEMA lab CASCADE;
-- then run_all.sql again: L4 and L5 changed ticket type 241 and event 122.
