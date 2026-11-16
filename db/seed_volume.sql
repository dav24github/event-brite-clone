-- =============================================================================
-- seed_volume.sql · volume seed for the EXPLAIN ANALYZE lab (S01 step 4.2)
-- Adds ~50k events and 500k+ tickets on top of seed.sql, so indexes matter.
--
-- Run it in its OWN database, so eventbrite_lab keeps the small seed and the
-- 105 constraint tests still pass there:
--   createdb -U postgres eventbrite_perf
--   psql -U postgres -v ON_ERROR_STOP=1 -d eventbrite_perf -f db/run_all.sql
--   psql -U postgres -v ON_ERROR_STOP=1 -d eventbrite_perf -f db/seed_volume.sql
--
-- Sections:
--   1. setup                            (given)
--   2. users + organizers               +50,000 users, +1,000 organizers
--   3. events                           +50,000, skewed: most in the past
--   4. ticket types                     1-3 per event
--   5. reservations + tickets           one statement: plan -> insert -> tickets
--   6. ANALYZE + counts
--   7. integrity checks                 every query must return 0
--
-- Rules for the whole file:
--   * SET-BASED only: INSERT ... SELECT ... FROM generate_series(...).
--     No DO loops, no reserve_tickets(): 500k calls would take far too long.
--   * Triggers are OFF (session_replication_role = replica, as in seed.sql
--     section 5). That also turns off FOREIGN KEY checks, so every id you
--     insert must come from a row that exists. CHECKs and UNIQUE still apply.
--   * The rules the triggers would enforce are kept BY HAND:
--       - sold tickets per ticket type <= quantity          (BR-T3)
--       - unit_price = ticket_types.price                   (BR-R7)
--       - ticket.event_id = its reservation's = its type's  (D2)
--       - reservation and ticket statuses match             (BR-K3)
--       - reservations only on published/completed/cancelled events,
--         created between published_at and min(starts_at, now())
--   * Keep comments ASCII: a non-ASCII character inside a statement fails on a
--     WIN1252 database.
--
-- Watch (the two traps of set-based seeding):
--   * An uncorrelated subquery such as
--         (SELECT user_id FROM organizers ORDER BY random() LIMIT 1)
--     runs ONCE for the whole INSERT: every row gets the same organizer.
--     Put the ids in an array in a CTE and index it per row:
--         ids[1 + floor(random() * cardinality(ids))::int]
--   * random() must be called per row. If you compute a value in a CTE and
--     join it back, check you didn't give every row the same number.
--
-- Expected (section 6):
--   users 51,000 · organizers 1,025 · events 50,123 · ticket_types 100,406
--   reservations 304,075 · tickets 759,426 · whole file 89,130.712 ms (approximately 1 minute and 29.13 seconds)
-- =============================================================================


-- -----------------------------------------------------------------------------
-- 1. Setup                                                              (given)
-- -----------------------------------------------------------------------------
SET client_encoding = 'UTF8';
SET search_path TO eventbrite;
SELECT setseed(0.42);                          -- same data on every run
-- show how long each statement takes (for tuning). A psql \command reads the
-- rest of its line as arguments, so its comment can't share the line.
\timing on

-- Remember the highest ids before inserting. \gset stores each column of the
-- result in a psql variable with the same name: use it later as :max_user_before
SELECT (SELECT max(user_id)  FROM users)  AS max_user_before,
       (SELECT max(event_id) FROM events) AS max_event_before \gset

SET session_replication_role = replica;        -- triggers and FK checks off


-- -----------------------------------------------------------------------------
-- 2. Users + organizers
-- -----------------------------------------------------------------------------
-- Why:      1,000 users for ~250k reservations = ~250 reservations each. Then
--           "my tickets" reads a big slice of the table and an index barely
--           helps. With ~51k users it's ~5 each: a realistic, selective lookup.
--           Same for organizers: 25 organizers x 50k events = 2,000 each.
--
-- Steps:    1. INSERT INTO users (email, password_hash, full_name)
--              FROM generate_series(1, 50000) AS i
--              email: format('vol%s@example.com', i)  (lowercase, unique,
--              and different from seed.sql's user%s@example.com)
--              password_hash: the same placeholder seed.sql uses
--              full_name: anything non-blank, e.g. 'Volume User ' || i
--           2. INSERT INTO organizers (user_id, organizer_name)
--              the first 1,000 NEW users: WHERE user_id > :max_user_before
--              ORDER BY user_id LIMIT 1000
--              organizer_name: format('Volume Organizer %s', user_id)
--              (unique index on lower(organizer_name): names must differ)
-- Check:    SELECT count(*) FROM users;       -> 51,000
--           SELECT count(*) FROM organizers;  -> 1,025
INSERT INTO users (email, password_hash, full_name, created_at)
SELECT format('vol%s@example.com', i), --email
        '$2b$12$seed-placeholder-hash-not-a-real-password-hash',
        format('Volume User %s', i), -- full_name
        now() - interval '3 years' * random() -- created_at (updated_at keeps its default now())
FROM generate_series(1, 50000) AS i;

INSERT INTO organizers (user_id, organizer_name)   -- organizers has enabled_at (default now()), no created_at
SELECT u.user_id, format('Volume Organizer %s', u.user_id)
FROM users u
WHERE u.user_id > :max_user_before
ORDER BY u.user_id
LIMIT 1000;


-- -----------------------------------------------------------------------------
-- 3. Events
-- -----------------------------------------------------------------------------
-- Why skewed: an index only pays off when the filter is SELECTIVE. If half the
--           events were "published + upcoming", browse would read half the
--           table and Postgres would rightly choose a Seq Scan. Real platforms
--           are mostly history.
--
-- Target mix (from one random() per row):
--             ~85% past     -> mostly 'completed', ~10% of them still 'published'
--                              (the completion job lags, BR-E10)
--             ~15% upcoming -> mostly 'published', ~15% of them 'draft'
--             ~3% of all    -> 'cancelled' (any date)
--
-- Steps:    1. CTE ids: the arrays of organizer ids, category ids and venue ids
--              (ARRAY(SELECT ... ORDER BY ...), as in seed.sql section 5)
--           2. CTE g: generate_series(1, 50000) AS i, plus per row:
--                starts_at = now() - interval '730 days'
--                            + random() * interval '910 days'
--                            (2 years back to 6 months ahead; ~80% in the past.
--                             Tune the numbers until the mix is close)
--                and one r = random() to pick the status
--           3. INSERT INTO events (...) SELECT ... FROM g, ids
--              Columns and the CHECK each one must pass:
--                organizer_id, category_id, venue_id  from the arrays
--                location_type 'in_person'            (ck_events_location_exclusive:
--                                                      venue set, meeting_url NULL)
--                title         any 3+ chars; reuse seed.sql's v_titles list
--                              (title search, pattern 5, needs real words)
--                description   NOT NULL unless draft   (ck_events_when_is_draft)
--                status        from starts_at and r (mix above)
--                ends_at       starts_at + 2-6 hours   (ck_events_ends_after_start)
--                timezone, currency  copy them from the venue's city:
--                              seed_cities is dropped at the end of seed.sql, so
--                              take them from an existing event at that venue,
--                              or rebuild the small city list from seed.sql line 74
--                published_at  NULL iff draft          (ck_events_published_at_iff_not_draft)
--                              e.g. starts_at - 15..60 days
--                cancelled_at  set iff cancelled       (ck_events_when_is_cancelled)
--                              + cancellation_reason
--                created_at    a bit before published_at (or before starts_at for drafts)
-- Check:    SELECT status, starts_at > now() AS upcoming, count(*)
--             FROM events GROUP BY 1, 2 ORDER BY 1, 2;
--           published + upcoming should be roughly 10% of all events
WITH ids AS (                                    -- one row holding the arrays to pick from
    SELECT ARRAY(SELECT user_id     FROM organizers ORDER BY user_id)     AS orgs,
           ARRAY(SELECT category_id FROM categories ORDER BY category_id) AS cats,
           ARRAY(SELECT venue_id    FROM venues     ORDER BY venue_id)    AS venues,
           ARRAY['Live Jazz Night', 'Tech Meetup', 'Street Food Fair', 'Indie Rock Showcase',
                 'Startup Pitch Night', 'Yoga in the Park', 'Photography Walk', 'Wine Tasting',
                 'Stand-up Comedy', 'Salsa Workshop', 'Design Talks', 'Book Club'] AS titles
),
venue_info AS (                                  -- seed_cities is dropped by seed.sql: rebuild it
    SELECT v.venue_id, v.city, c.timezone, c.currency
      FROM venues v
      JOIN (VALUES ('Bogotá',           'CO', 'America/Bogota',                 'COP'),
                   ('Medellín',         'CO', 'America/Bogota',                 'COP'),
                   ('Madrid',           'ES', 'Europe/Madrid',                  'EUR'),
                   ('Barcelona',        'ES', 'Europe/Madrid',                  'EUR'),
                   ('Ciudad de México', 'MX', 'America/Mexico_City',            'MXN'),
                   ('Lima',             'PE', 'America/Lima',                   'PEN'),
                   ('Buenos Aires',     'AR', 'America/Argentina/Buenos_Aires', 'ARS'),
                   ('New York',         'US', 'America/New_York',               'USD')
           ) AS c (city, country, timezone, currency)
        ON c.city = v.city AND c.country = v.country
),
g AS (                                           -- one row per event; random() runs per row
    SELECT i,
           ids.orgs  [1 + floor(random() * cardinality(ids.orgs))::int]   AS organizer_id,
           ids.cats  [1 + floor(random() * cardinality(ids.cats))::int]   AS category_id,
           ids.venues[1 + floor(random() * cardinality(ids.venues))::int] AS venue_id,
           ids.titles[1 + floor(random() * cardinality(ids.titles))::int] AS title,
           date_trunc('hour', now() - interval '730 days'
                              + random() * interval '850 days')           AS starts_at,  -- 2 years back, 120 days ahead
           random()                                                       AS r           -- one draw decides the status
      FROM generate_series(1, 50000) AS i
     CROSS JOIN ids
),
s AS (                                           -- status, and a publish date that's never in the future
    SELECT g.*,
           CASE
               WHEN r < 0.03           THEN 'cancelled'
               WHEN starts_at <= now() THEN CASE WHEN r < 0.13 THEN 'published' ELSE 'completed' END  -- BR-E10 lag
               ELSE                         CASE WHEN r < 0.18 THEN 'draft'     ELSE 'published' END
           END::event_status AS status,
           least(starts_at - (15 + floor(random() * 46)::int) * interval '1 day',
                 now() - interval '1 hour') AS publish_candidate
      FROM g
),
d AS (                                           -- drafts have no published_at
    SELECT s.*,
           CASE WHEN status = 'draft' THEN NULL ELSE publish_candidate END AS published_at
      FROM s
),
c AS (                                           -- cancelled_at and created_at, from published_at
    SELECT d.*,
           CASE WHEN status = 'cancelled'
                THEN published_at + (least(starts_at, now()) - published_at) * random()
           END AS cancelled_at,
           least(coalesce(published_at, starts_at - interval '30 days'), now())
               - interval '2 days' AS created_at
      FROM d
)
INSERT INTO events (organizer_id, category_id, location_type, venue_id, title, description,
                    status, starts_at, ends_at, timezone, currency,
                    published_at, cancelled_at, cancellation_reason, created_at, updated_at)
SELECT c.organizer_id, c.category_id, 'in_person', c.venue_id, c.title,
       format('%s in %s. Volume seed.', c.title, vi.city),
       c.status, c.starts_at,
       c.starts_at + (2 + floor(random() * 5)::int) * interval '1 hour',      -- 2-6 hours
       vi.timezone, vi.currency,
       c.published_at,
       c.cancelled_at,
       CASE WHEN c.status = 'cancelled' THEN 'Volume seed' END,
       c.created_at,
       coalesce(c.cancelled_at, c.published_at, c.created_at)                 -- the last thing that happened
  FROM c
  JOIN venue_info vi USING (venue_id)
 ORDER BY c.i;                                   -- event_ids follow i: same ids on every run
 
-- -----------------------------------------------------------------------------
-- 4. Ticket types
-- -----------------------------------------------------------------------------
-- Steps:    INSERT INTO ticket_types (event_id, name, quantity, position)
--           SELECT e.event_id, names[p], <quantity>, p
--             FROM events e
--            CROSS JOIN LATERAL generate_series(1, 1 + floor(random() * 3)::int) AS p
--            WHERE e.event_id > :max_event_before
--           names: ARRAY['General', 'VIP', 'Early Bird'] (unique per event:
--                  uq_ticket_types_event_name_lower, and position is unique too)
--           quantity: 10-100 is a good start (ck allows 1-100,000)
-- Watch:    LATERAL is what lets generate_series see e: 1-3 rows PER event.
--           Without it, random() would be evaluated once.
-- Check:    ~100,000 new ticket types (50k events x 2 on average)
-- Written by AI, reviewed by me.
WITH e AS (                                      -- how many types each event gets: random() per event row
    SELECT event_id, 1 + floor(random() * 3)::int AS n_types
      FROM events
     WHERE event_id > :max_event_before
)
INSERT INTO ticket_types (event_id, name, quantity, position)
SELECT e.event_id,
       (ARRAY['General', 'VIP', 'Early Bird'])[p],
       10 + floor(random() * 91)::int,           -- 10-100 tickets
       p
  FROM e
-- LATERAL allows generate_series to see e.n_types: 1-3 rows per event, each with a different p
 CROSS JOIN LATERAL generate_series(1, e.n_types) AS p   -- uses e's column: 1-3 rows per event
 ORDER BY e.event_id, p;


-- -----------------------------------------------------------------------------
-- 5. Reservations + tickets                    one statement, three CTEs
-- -----------------------------------------------------------------------------
-- Shape:    WITH plan AS (...),
--                ins  AS (INSERT INTO reservations ... RETURNING ...)
--           INSERT INTO tickets (...) SELECT ... FROM ins JOIN plan ...;
--
-- Step 1 · CTE plan: one row per future reservation
--           FROM ticket_types tt JOIN events e (new events only, no drafts)
--           per ticket type:
--             fill    = power(random(), 3)   -> most sell little, a few sell out
--                       (power(random(), n) has mean 1/(n+1): n = 3 -> 25%)
--             n_res   = floor(tt.quantity * fill / 4)
--             CROSS JOIN LATERAL generate_series(1, n_res)   -> one row each
--           per plan row:
--             qty     = 1 + floor(random() * 4)   (1-4 tickets)
--                       Dividing by 4 above (the max qty) guarantees
--                       n_res x qty <= quantity: no oversell, no trigger needed.
--             user_id = a random user (array trick from the header). Skew it with
--                       power(random(), 2) so some users reserve a lot.
--             created_at between e.published_at and least(e.starts_at, now())
--             status  = 'cancelled' if the event is cancelled, else 'confirmed'
--                       (cancelled_at set iff cancelled: two CHECKs need it)
--             n       = row_number() OVER ()      -> used for the code below
--             code    = the reference code made from n (next block)
--
-- Step 2 · reference_code, the trap
--           Format: 'EBK-' + 6 chars from '23456789ABCDEFGHJKMNPQRSTUVWXYZ'
--           (31 chars, so 31^6 = 887,503,681 codes). With ~250k RANDOM codes
--           you'd get ~35 duplicates, and in a set-based INSERT one duplicate
--           fails the whole statement.
--           Instead, make the code FROM n, so it's unique by construction:
--             x    = (n * 104729) % 887503681     (104729 is prime and not 31:
--                                                  every n gets a different x)
--             code = 'EBK-' || the 6 base-31 digits of x, each one
--                    substr(alphabet, (x / 31^k) % 31 + 1, 1) for k = 5..0
--                    (string_agg over generate_series(0, 5), or 6 substr calls)
--           seed.sql already has ~3,240 random codes, so one new code may still
--           clash with an old one: add ON CONFLICT (reference_code) DO NOTHING.
--           Losing one reservation is fine.
--
-- Step 3 · CTE ins: INSERT INTO reservations
--             (user_id, event_id, reference_code, status, created_at, cancelled_at)
--           SELECT ... FROM plan ON CONFLICT ... DO NOTHING
--           RETURNING reservation_id, event_id, reference_code
--
-- Step 4 · the final INSERT INTO tickets
--             (reservation_id, ticket_type_id, event_id, unit_price, status, cancelled_at)
--           FROM ins JOIN plan ON plan.code = ins.reference_code
--                JOIN ticket_types tt ON tt.ticket_type_id = plan.ticket_type_id
--           CROSS JOIN LATERAL generate_series(1, plan.qty)    -> qty tickets each
--           unit_price = tt.price · status/cancelled_at copied from the reservation
-- Watch:    RETURNING only returns columns of the inserted table, so plan's
--           ticket_type_id and qty come back by joining on the unique code.
--           A reservation skipped by ON CONFLICT is not in ins, so it gets no tickets.
-- Tune:     expected tickets ~ ticket_types x avg quantity x avg fill
--           x (2.5 / 4)  (avg qty / max qty). If you land outside 500k-1M,
--           change quantity or the power in fill, not the structure.
-- Written by AI, reviewed by me.
WITH uids AS (                                   -- the users who can reserve
    SELECT ARRAY(SELECT user_id FROM users WHERE deleted_at IS NULL ORDER BY user_id) AS ids
),
tt_fill AS (                                     -- per ticket type: how full it gets
    SELECT tt.ticket_type_id, tt.event_id, tt.quantity, tt.price,
           e.status AS event_status, e.published_at, e.starts_at,
           e.cancelled_at AS event_cancelled_at,
           power(random(), 3) AS fill            -- mean 25%: most sell little, a few sell out
      FROM ticket_types tt
      JOIN events e USING (event_id)
     WHERE e.event_id > :max_event_before
       AND e.status <> 'draft'                   -- nobody can reserve a draft
),
slots AS (                                       -- one row per reservation to create
    SELECT f.*,
           1 + floor(random() * 4)::int AS qty,  -- 1-4 tickets
           uids.ids[1 + floor(power(random(), 2) * cardinality(uids.ids))::int] AS user_id,  -- skewed: some users reserve a lot
           -- reserved between publishing and the first of: start, event cancel, now
           f.published_at + (least(f.starts_at, coalesce(f.event_cancelled_at, now()), now())
                             - f.published_at) * random() AS created_at,
           random() AS r                         -- decides a user's own cancellation
      FROM tt_fill f
     CROSS JOIN LATERAL generate_series(1, floor(f.quantity * f.fill / 4)::int) AS k
          -- / 4 = / max qty: n_res x qty <= quantity, so no type is oversold (BR-T3)
     CROSS JOIN uids
),
plan AS (                                        -- status + a unique reference code
    SELECT s.*,
           CASE
               WHEN s.event_status = 'cancelled' THEN 'cancelled'   -- the event cancel cascaded (BR-E9)
               WHEN s.r < 0.05                   THEN 'cancelled'   -- ~5% cancelled by the user (BR-R5)
               ELSE 'confirmed'
           END::reservation_status AS status,
           CASE
               WHEN s.event_status = 'cancelled' THEN s.event_cancelled_at
               WHEN s.r < 0.05 THEN s.created_at + (least(s.starts_at, now()) - s.created_at) * random()
           END AS cancelled_at,
           -- n -> x is one-to-one (104729 is prime, 887503681 = 31^6), then x in base 31
           'EBK-' || (SELECT string_agg(substr('23456789ABCDEFGHJKMNPQRSTUVWXYZ',
                                               ((x.v / power(31, d)::bigint) % 31)::int + 1, 1),
                                        '' ORDER BY d DESC)
                        FROM (SELECT (s.n * 104729) % 887503681 AS v) AS x,
                             generate_series(0, 5) AS d) AS code
      FROM (SELECT slots.*, row_number() OVER (ORDER BY ticket_type_id, created_at)::bigint AS n
              FROM slots) AS s
),
ins AS (
    INSERT INTO reservations (user_id, event_id, reference_code, status, created_at, cancelled_at)
    SELECT user_id, event_id, code, status, created_at, cancelled_at
      FROM plan
     ORDER BY n
        ON CONFLICT (reference_code) DO NOTHING  -- a clash with one of seed.sql's random codes
    RETURNING reservation_id, reference_code
)
INSERT INTO tickets (reservation_id, ticket_type_id, event_id, unit_price, status, cancelled_at)
SELECT ins.reservation_id, p.ticket_type_id, p.event_id,
       p.price,                                   -- price snapshot (BR-R7)
       CASE p.status WHEN 'cancelled' THEN 'cancelled' ELSE 'active' END::ticket_status,
       p.cancelled_at                             -- same moment as its reservation (BR-K3)
  FROM ins
  JOIN plan p ON p.code = ins.reference_code     -- RETURNING can't return plan's columns: join back
 CROSS JOIN LATERAL generate_series(1, p.qty)    -- qty tickets per reservation
 ORDER BY ins.reservation_id;

SET session_replication_role = DEFAULT;       -- triggers and FK checks back on


-- -----------------------------------------------------------------------------
-- 6. ANALYZE + counts
-- -----------------------------------------------------------------------------
-- Steps:    ANALYZE;   (fresh planner statistics: without it, EXPLAIN on Monday
--                       would plan with the row counts of the small seed)
--           then the same counts query as seed.sql section 7
-- Expected: see the header. Note the total time from \timing.
ANALYZE;

SELECT (SELECT count(*) FROM users)                                  AS users,
        (SELECT count(*) FROM organizers)                             AS organizers,
        (SELECT count(*) FROM venues)                                 AS venues,
        (SELECT count(*) FROM events)                                 AS events,
        (SELECT count(*) FROM ticket_types)                           AS ticket_types,
        (SELECT count(*) FROM reservations)                           AS reservations,
        (SELECT count(*) FROM tickets)                                AS tickets,
        (SELECT count(*) FROM tickets WHERE status = 'cancelled')     AS cancelled_tickets;

-- -----------------------------------------------------------------------------
-- 7. Integrity checks                               every query must return 0
-- -----------------------------------------------------------------------------
-- FKs and triggers were off, so prove by hand that the data is still valid.
--   a. orphans: reservations whose user_id or event_id has no row
--      (one anti-join each: LEFT JOIN ... WHERE parent IS NULL, or NOT EXISTS)
--   b. tickets whose event_id differs from their reservation's or their
--      ticket type's event_id
--   c. ticket types with more active tickets than quantity (oversell)
--   d. tickets whose status doesn't match their reservation's
--      (the same idea as T105 in tests/constraint_tests.sql)
--   e. reservations on draft events
-- If one returns rows: fix the section that produced them and rerun the whole
-- file from run_all.sql (no partial reruns: ids and random() would shift).

-- a
SELECT 'a. orphan reservations' AS check, count(*) AS bad
    FROM reservations r
    WHERE NOT EXISTS (SELECT 1 FROM users  u WHERE u.user_id  = r.user_id)
        OR NOT EXISTS (SELECT 1 FROM events e WHERE e.event_id = r.event_id);

SELECT 'a. orphan tickets' AS check, count(*) AS bad
    FROM tickets t
    WHERE NOT EXISTS (SELECT 1 FROM reservations r WHERE r.reservation_id = t.reservation_id)
        OR NOT EXISTS (SELECT 1 FROM ticket_types tt WHERE tt.ticket_type_id = t.ticket_type_id);

-- with LEFT JOIN ... IS NULL
-- SELECT count(*) FROM reservations r
--     LEFT JOIN users u ON u.user_id = r.user_id
--     WHERE u.user_id IS NULL;

-- b
SELECT 'b. ticket event mismatch' AS check, count(*) AS bad
    FROM tickets t
    JOIN reservations r  ON r.reservation_id  = t.reservation_id
    JOIN ticket_types tt ON tt.ticket_type_id = t.ticket_type_id
    WHERE t.event_id <> r.event_id
        OR t.event_id <> tt.event_id;

-- c
SELECT 'c. ticket types with more active tickets than quantity' AS check, count(*) as bad
    FROM (
        SELECT tt.ticket_type_id
        FROM ticket_types tt
        JOIN tickets t USING (ticket_type_id)
        WHERE t.status = 'active'
        GROUP BY tt.ticket_type_id, tt.quantity
        HAVING count(*) > tt.quantity
    );

-- d
SELECT 'd. status mismatch' AS check, count(*) AS bad
    FROM tickets t
    JOIN reservations r ON r.reservation_id = t.reservation_id
    WHERE (t.status = 'active') <> (r.status = 'confirmed');

-- e. nobody can reserve a draft (BR-E6)
SELECT 'e. reservations on drafts' AS check, count(*) AS bad
    FROM reservations r
    JOIN events e ON e.event_id = r.event_id
    WHERE e.status = 'draft';