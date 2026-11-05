-- =============================================================================
-- seed.sql · deterministic seed data (setseed + generate_series)
-- Planted edge cases:
--   [x] a sold-out ticket type
--   [x] an event with no sales
--   [x] a cancelled event
--   [x] a user who is both organizer and attendee
--
-- Sections:
--   1. setseed                          generated
--   2. categories                       (everything below picks from it)
--   3. users, organizers, venues        generated
--   4. future events                    generated, through the real path
--   5. past events                      generated, triggers off
--   6. planted edge cases               fixed rows, through the real path
--   7. ANALYZE + counts
--
-- Deterministic: same rows on every run, except values tied to the run time
-- (dates are relative to now(), and tickets.code comes from gen_random_uuid()).
-- =============================================================================

SET client_encoding = 'UTF8';

-- -----------------------------------------------------------------------------
-- 1. setseed: every random() below returns the same sequence on every run
-- -----------------------------------------------------------------------------
SELECT setseed(0.42);

-- -----------------------------------------------------------------------------
-- 2. Categories                                               BR-C1
-- -----------------------------------------------------------------------------
-- The fixed platform list. Slugs: lowercase a-z, 0-9 and single hyphens
-- (ck_categories_slug_format), so '&' and spaces become '-'.
INSERT INTO categories (name, slug) VALUES
    ('Music',              'music'),
    ('Food & Drink',       'food-drink'),
    ('Technology',         'technology'),
    ('Business',           'business'),
    ('Arts & Culture',     'arts-culture'),
    ('Comedy',             'comedy'),
    ('Health & Wellness',  'health-wellness'),
    ('Sports & Fitness',   'sports-fitness'),
    ('Education',          'education'),
    ('Community',          'community');


-- -----------------------------------------------------------------------------
-- 3. Users, organizers, venues · generated
-- -----------------------------------------------------------------------------
-- 1,000 users. The hash is a placeholder: nobody logs in with seed data.
INSERT INTO users (email, password_hash, full_name)
SELECT format('user%s@example.com', i),
       '$2b$12$seed-placeholder-hash-not-a-real-password-hash',
       (ARRAY['Ana', 'Luis', 'Sofía', 'Mateo', 'Valentina', 'Santiago', 'Camila', 'Daniel',
              'Lucía', 'Pablo', 'Martina', 'Diego'])[1 + floor(random() * 12)::int]
       || ' ' ||
       (ARRAY['García', 'Rodríguez', 'Martínez', 'López', 'Gómez', 'Pérez', 'Sánchez',
              'Ramírez', 'Torres', 'Díaz'])[1 + floor(random() * 10)::int]
  FROM generate_series(1, 1000) AS i;

-- The first 25 users are also organizers (BR-U5). Names: 25 distinct genre + kind
-- pairs out of 36, so the unique index on lower(organizer_name) always holds.
INSERT INTO organizers (user_id, organizer_name)
SELECT u.user_id, n.name
  FROM (SELECT user_id, row_number() OVER (ORDER BY user_id) AS rn
          FROM users ORDER BY user_id LIMIT 25) AS u
  JOIN (SELECT g || ' ' || k AS name, row_number() OVER (ORDER BY random()) AS rn
          FROM unnest(ARRAY['Jazz', 'Tech', 'Food', 'Art', 'Indie', 'Startup']) AS g
         CROSS JOIN unnest(ARRAY['Collective', 'Club', 'Society', 'Lab', 'House', 'Crew']) AS k) AS n
 USING (rn);

-- Cities with their time zone and currency, so an in-person event matches its venue.
CREATE TEMP TABLE seed_cities (city TEXT, country CHAR(2), timezone TEXT, currency CHAR(3), lat NUMERIC, lon NUMERIC);
INSERT INTO seed_cities VALUES
    ('Bogotá',           'CO', 'America/Bogota',                 'COP',   4.711, -74.072),
    ('Medellín',         'CO', 'America/Bogota',                 'COP',   6.244, -75.581),
    ('Madrid',           'ES', 'Europe/Madrid',                  'EUR',  40.417,  -3.704),
    ('Barcelona',        'ES', 'Europe/Madrid',                  'EUR',  41.387,   2.170),
    ('Ciudad de México', 'MX', 'America/Mexico_City',            'MXN',  19.433, -99.133),
    ('Lima',             'PE', 'America/Lima',                   'PEN', -12.046, -77.043),
    ('Buenos Aires',     'AR', 'America/Argentina/Buenos_Aires', 'ARS', -34.604, -58.382),
    ('New York',         'US', 'America/New_York',               'USD',  40.713, -74.006);

-- 30 venues; about 70% with coordinates (both or neither, BR-L2).
INSERT INTO venues (name, address, city, country, postal_code, latitude, longitude)
SELECT v.name, v.address, c.city, c.country, v.postal_code,
       CASE WHEN v.has_coords THEN round((c.lat + (random() - 0.5) * 0.1)::numeric, 6) END,   -- random() is double;
       CASE WHEN v.has_coords THEN round((c.lon + (random() - 0.5) * 0.1)::numeric, 6) END    -- round(x, 6) needs numeric
  FROM (SELECT i,
               (ARRAY['Teatro', 'Centro Cultural', 'Auditorio', 'Sala', 'Parque', 'Galería'])[1 + floor(random() * 6)::int]
               || ' ' ||
               (ARRAY['Central', 'del Sol', 'Norte', 'La Estación', 'Libertad', 'Río'])[1 + floor(random() * 6)::int] AS name,
               format('Calle %s #%s-%s', 1 + floor(random() * 150)::int,
                      1 + floor(random() * 99)::int, 1 + floor(random() * 99)::int) AS address,
               CASE WHEN random() < 0.8 THEN (10000 + floor(random() * 89999)::int)::text END AS postal_code,
               random() < 0.7 AS has_coords,
               1 + floor(random() * 8)::int AS city_rn
          FROM generate_series(1, 30) AS i) AS v
  JOIN (SELECT *, row_number() OVER (ORDER BY city) AS rn FROM seed_cities) AS c
    ON c.rn = v.city_rn
 ORDER BY v.i;

-- -----------------------------------------------------------------------------
-- 4. Future events · generated, through the real path
-- -----------------------------------------------------------------------------
-- Insert as draft → add ticket types → publish (guard_events_status runs its
-- checks and sets published_at) → reserve with reserve_tickets(). Every trigger
-- and function runs, so every invariant holds by construction.
-- 80 events, 3–120 days ahead; about 10% stay drafts.
DO $$
DECLARE
    v_organizers BIGINT[] := ARRAY(SELECT user_id FROM organizers ORDER BY user_id);
    v_categories BIGINT[] := ARRAY(SELECT category_id FROM categories ORDER BY category_id);
    v_venues     BIGINT[] := ARRAY(SELECT venue_id FROM venues ORDER BY venue_id);
    v_titles     TEXT[]   := ARRAY['Live Jazz Night', 'Tech Meetup', 'Street Food Fair', 'Indie Rock Showcase',
                                   'Startup Pitch Night', 'Yoga in the Park', 'Photography Walk', 'Wine Tasting',
                                   'Stand-up Comedy', 'Salsa Workshop', 'Design Talks', 'Book Club'];
    v_tt_names   TEXT[]   := ARRAY['General', 'VIP', 'Early Bird'];
    v_event_id   BIGINT;
    v_venue_id   BIGINT;
    v_city       TEXT;
    v_tz         TEXT;
    v_currency   CHAR(3);
    v_title      TEXT;
    v_starts     TIMESTAMPTZ;
BEGIN
    IF cardinality(v_categories) = 0 THEN
        RAISE EXCEPTION 'seed: add the categories first';
    END IF;

    FOR i IN 1..80 LOOP
        IF random() < 0.75 THEN                                                -- in person
            v_venue_id := v_venues[1 + floor(random() * cardinality(v_venues))::int];
            SELECT c.city, c.timezone, c.currency INTO v_city, v_tz, v_currency
              FROM venues v JOIN seed_cities c ON c.city = v.city AND c.country = v.country
             WHERE v.venue_id = v_venue_id;
        ELSE                                                                   -- online
            v_venue_id := NULL;
            SELECT city, timezone, currency INTO v_city, v_tz, v_currency
              FROM seed_cities ORDER BY city OFFSET floor(random() * 8) LIMIT 1;
        END IF;

        v_title  := v_titles[1 + floor(random() * cardinality(v_titles))::int];
        v_starts := date_trunc('hour', now())
                    + make_interval(days => 3 + floor(random() * 118)::int, hours => floor(random() * 12)::int);

        INSERT INTO events (organizer_id, category_id, location_type, venue_id, meeting_url,
                            title, description, starts_at, ends_at, timezone, currency, cover_url)
        VALUES (v_organizers[1 + floor(random() * cardinality(v_organizers))::int],
                v_categories[1 + floor(random() * cardinality(v_categories))::int],
                CASE WHEN v_venue_id IS NULL THEN 'online' ELSE 'in_person' END::location_type,
                v_venue_id,
                CASE WHEN v_venue_id IS NULL THEN 'https://meet.example.com/' || left(md5(random()::text), 12) END,
                v_title,
                format('%s in %s. Seed data.', v_title, v_city),
                v_starts,
                v_starts + make_interval(hours => 2 + floor(random() * 5)::int),
                v_tz,
                v_currency,
                CASE WHEN random() < 0.6 THEN 'https://img.example.com/' || left(md5(random()::text), 12) || '.jpg' END)
        RETURNING event_id INTO v_event_id;

        -- 1–3 ticket types, 20–150 tickets each, free in v0 (BR-T5)
        INSERT INTO ticket_types (event_id, name, quantity, position)
        SELECT v_event_id, v_tt_names[p], 20 + floor(random() * 131)::int, p
          FROM generate_series(1, 1 + floor(random() * 3)::int) AS p;

        IF random() < 0.9 THEN
            UPDATE events SET status = 'published' WHERE event_id = v_event_id;
        END IF;
    END LOOP;
END;
$$;

-- 1,500 checkout attempts through reserve_tickets(). power(random(), 2) favours the
-- first ticket types, so some events are popular and a few sell out on their own;
-- a sold-out attempt raises check_violation and is skipped. 20% of checkouts add a
-- second ticket type of the same event. power(random(), 3) on the user does the
-- same for attendees: a few buy often, many rarely or never (BR-M5 has contrast).
DO $$
DECLARE
    v_users     BIGINT[] := ARRAY(SELECT user_id FROM users WHERE deleted_at IS NULL ORDER BY user_id);
    v_tt_ids    BIGINT[];
    v_tt_events BIGINT[];
    v_k         INT;
    v_tt2       BIGINT;
    v_items     JSONB;
    v_skipped   INT := 0;
BEGIN
    SELECT array_agg(tt.ticket_type_id ORDER BY tt.ticket_type_id),
           array_agg(tt.event_id       ORDER BY tt.ticket_type_id)
      INTO v_tt_ids, v_tt_events
      FROM ticket_types tt JOIN events e USING (event_id)
     WHERE e.status = 'published';

    FOR i IN 1..1500 LOOP
        v_k     := 1 + floor(power(random(), 2) * cardinality(v_tt_ids))::int;
        v_items := jsonb_build_object(v_tt_ids[v_k]::text, 1 + floor(random() * 4)::int);

        IF random() < 0.2 THEN
            SELECT ticket_type_id INTO v_tt2
              FROM ticket_types
             WHERE event_id = v_tt_events[v_k] AND ticket_type_id <> v_tt_ids[v_k]
             ORDER BY ticket_type_id LIMIT 1;
            IF FOUND THEN
                v_items := v_items || jsonb_build_object(v_tt2::text, 1 + floor(random() * 2)::int);
            END IF;
        END IF;

        BEGIN
            PERFORM reserve_tickets(v_users[1 + floor(power(random(), 3) * cardinality(v_users))::int],  -- few frequent buyers, many rare ones
                                    v_tt_events[v_k], v_items);
        EXCEPTION WHEN check_violation THEN                                    -- sold out or over the limit
            v_skipped := v_skipped + 1;
        END;
    END LOOP;

    RAISE NOTICE 'seed: % of 1500 checkouts skipped (sold out / over limit)', v_skipped;
END;
$$;

-- About 5% of attendees cancel (BR-R5), through cancel_reservation().
DO $$
DECLARE
    r RECORD;
BEGIN
    FOR r IN SELECT reservation_id, user_id FROM reservations ORDER BY reservation_id LOOP
        IF random() < 0.05 THEN
            PERFORM cancel_reservation(r.user_id, r.reservation_id);
        END IF;
    END LOOP;
END;
$$;

-- -----------------------------------------------------------------------------
-- 5. Past events · generated, triggers off
-- -----------------------------------------------------------------------------
-- A past event can't be published (starts_at > now() on publish), so these rows
-- are written directly with triggers off. replica also turns off FOREIGN KEY
-- checks (they are triggers too): ids below come only from existing rows, and
-- rows are inserted in FK order. CHECKs and UNIQUE still apply. Needs a superuser.
-- The rules the triggers would enforce are kept by hand here: tickets ≤ quantity,
-- unit_price = price, reservation/ticket statuses match, reservations before start.
-- 40 events, 3–180 days ago; 70% marked completed, 30% still published (the
-- completion job lags, BR-E10). Reservations spread between publish and start,
-- which gives the daily-reservations metric (BR-M4) real history.
SET session_replication_role = replica;

DO $$
DECLARE
    v_organizers     BIGINT[] := ARRAY(SELECT user_id FROM organizers ORDER BY user_id);
    v_categories     BIGINT[] := ARRAY(SELECT category_id FROM categories ORDER BY category_id);
    v_venues         BIGINT[] := ARRAY(SELECT venue_id FROM venues ORDER BY venue_id);
    v_users          BIGINT[] := ARRAY(SELECT user_id FROM users WHERE deleted_at IS NULL ORDER BY user_id);
    v_titles         TEXT[]   := ARRAY['Live Jazz Night', 'Tech Meetup', 'Street Food Fair', 'Indie Rock Showcase',
                                       'Startup Pitch Night', 'Yoga in the Park', 'Photography Walk', 'Wine Tasting',
                                       'Stand-up Comedy', 'Salsa Workshop', 'Design Talks', 'Book Club'];
    v_tt_names       TEXT[]   := ARRAY['General', 'VIP', 'Early Bird'];
    v_event_id       BIGINT;
    v_venue_id       BIGINT;
    v_city           TEXT;
    v_tz             TEXT;
    v_currency       CHAR(3);
    v_title          TEXT;
    v_starts         TIMESTAMPTZ;
    v_published      TIMESTAMPTZ;
    tt               RECORD;
    v_target         INT;
    v_sold           INT;
    v_qty            INT;
    v_reservation_id BIGINT;
BEGIN
    FOR i IN 1..40 LOOP
        v_venue_id := v_venues[1 + floor(random() * cardinality(v_venues))::int];
        SELECT c.city, c.timezone, c.currency INTO v_city, v_tz, v_currency
          FROM venues v JOIN seed_cities c ON c.city = v.city AND c.country = v.country
         WHERE v.venue_id = v_venue_id;

        v_title     := v_titles[1 + floor(random() * cardinality(v_titles))::int];
        v_starts    := date_trunc('hour', now())
                       - make_interval(days => 3 + floor(random() * 178)::int, hours => floor(random() * 12)::int);
        v_published := v_starts - make_interval(days => 15 + floor(random() * 46)::int);

        INSERT INTO events (organizer_id, category_id, location_type, venue_id, title, description,
                            status, starts_at, ends_at, timezone, currency, published_at, created_at, updated_at)
        VALUES (v_organizers[1 + floor(random() * cardinality(v_organizers))::int],
                v_categories[1 + floor(random() * cardinality(v_categories))::int],
                'in_person', v_venue_id, v_title,
                format('%s in %s. Seed data.', v_title, v_city),
                CASE WHEN random() < 0.7 THEN 'completed' ELSE 'published' END::event_status,
                v_starts,
                v_starts + make_interval(hours => 2 + floor(random() * 5)::int),
                v_tz, v_currency,
                v_published,
                v_published - interval '2 days',
                v_published)
        RETURNING event_id INTO v_event_id;

        INSERT INTO ticket_types (event_id, name, quantity, position)
        SELECT v_event_id, v_tt_names[p], 20 + floor(random() * 131)::int, p
          FROM generate_series(1, 1 + floor(random() * 3)::int) AS p;

        -- Sell 30–100% of each ticket type, 1–4 tickets per reservation
        FOR tt IN SELECT ticket_type_id, quantity, price FROM ticket_types
                   WHERE event_id = v_event_id ORDER BY ticket_type_id LOOP
            v_target := floor(tt.quantity * (0.3 + random() * 0.7))::int;
            v_sold   := 0;

            WHILE v_sold < v_target LOOP
                v_qty := least(1 + floor(random() * 4)::int, v_target - v_sold);

                LOOP                                                           -- same retry as reserve_tickets()
                    BEGIN
                        INSERT INTO reservations (user_id, event_id, reference_code, created_at)
                        VALUES (v_users[1 + floor(power(random(), 3) * cardinality(v_users))::int],  -- same skew as section 4
                                v_event_id,
                                gen_reference_code(),
                                v_published + (v_starts - v_published) * random())
                        RETURNING reservation_id INTO v_reservation_id;
                        EXIT;
                    EXCEPTION WHEN unique_violation THEN
                    END;
                END LOOP;

                INSERT INTO tickets (reservation_id, ticket_type_id, event_id, unit_price)
                SELECT v_reservation_id, tt.ticket_type_id, v_event_id, tt.price
                  FROM generate_series(1, v_qty);

                v_sold := v_sold + v_qty;
            END LOOP;
        END LOOP;
    END LOOP;
END;
$$;

SET session_replication_role = DEFAULT;

-- -----------------------------------------------------------------------------
-- 6. Planted edge cases
-- -----------------------------------------------------------------------------
-- Known rows that tests and query labs can rely on, found by their '[Edge]' title.
-- Same real path as section 4 (triggers on): draft → ticket types → publish →
-- reserve_tickets(). Online events, so no venue lookup is needed.
--   organizer 2 · '[Edge] Sold Out Rooftop'  'General' 5/5 sold, 'VIP' 0/10 sold
--   organizer 3 · '[Edge] No Sales Workshop'  published, zero reservations
--   organizer 4 · '[Edge] Cancelled Concert'  2 reservations, then cancelled
--   user 1 (organizer) holds tickets to organizer 2's event (BR-U5)
DO $$
DECLARE
    v_music      BIGINT := (SELECT category_id FROM categories WHERE slug = 'music');
    v_education  BIGINT := (SELECT category_id FROM categories WHERE slug = 'education');
    v_starts     TIMESTAMPTZ := date_trunc('day', now()) + interval '30 days 19 hours';
    v_event_id   BIGINT;
    v_general    BIGINT;
BEGIN
    -- a sold-out ticket type, next to one with tickets left -------------------
    INSERT INTO events (organizer_id, category_id, location_type, meeting_url, title, description,
                        starts_at, ends_at, timezone, currency)
    VALUES (2, v_music, 'online', 'https://meet.example.com/edge-sold-out',
            '[Edge] Sold Out Rooftop', 'Planted edge case: General is sold out, VIP has no sales.',
            v_starts, v_starts + interval '3 hours', 'America/Bogota', 'COP')
    RETURNING event_id INTO v_event_id;

    INSERT INTO ticket_types (event_id, name, quantity, position)
    VALUES (v_event_id, 'General', 5, 1)
    RETURNING ticket_type_id INTO v_general;
    INSERT INTO ticket_types (event_id, name, quantity, position)
    VALUES (v_event_id, 'VIP', 10, 2);

    UPDATE events SET status = 'published' WHERE event_id = v_event_id;

    -- user 1 is an organizer (section 3) and here also an attendee (BR-U5)
    PERFORM reserve_tickets(1,   v_event_id, jsonb_build_object(v_general::text, 2));
    PERFORM reserve_tickets(500, v_event_id, jsonb_build_object(v_general::text, 3));   -- 5/5: sold out

    -- an event with no sales ---------------------------------------------------
    INSERT INTO events (organizer_id, category_id, location_type, meeting_url, title, description,
                        starts_at, ends_at, timezone, currency)
    VALUES (3, v_education, 'online', 'https://meet.example.com/edge-no-sales',
            '[Edge] No Sales Workshop', 'Planted edge case: published, nobody reserved.',
            v_starts + interval '7 days', v_starts + interval '7 days 2 hours', 'Europe/Madrid', 'EUR')
    RETURNING event_id INTO v_event_id;

    INSERT INTO ticket_types (event_id, name, quantity, position)
    VALUES (v_event_id, 'General', 50, 1);

    UPDATE events SET status = 'published' WHERE event_id = v_event_id;

    -- a cancelled event: publish, reserve, cancel; the cascade cancels the rest -
    INSERT INTO events (organizer_id, category_id, location_type, meeting_url, title, description,
                        starts_at, ends_at, timezone, currency)
    VALUES (4, v_music, 'online', 'https://meet.example.com/edge-cancelled',
            '[Edge] Cancelled Concert', 'Planted edge case: had reservations, then was cancelled.',
            v_starts + interval '14 days', v_starts + interval '14 days 3 hours', 'America/Mexico_City', 'MXN')
    RETURNING event_id INTO v_event_id;

    INSERT INTO ticket_types (event_id, name, quantity, position)
    VALUES (v_event_id, 'General', 100, 1)
    RETURNING ticket_type_id INTO v_general;

    UPDATE events SET status = 'published' WHERE event_id = v_event_id;

    PERFORM reserve_tickets(600, v_event_id, jsonb_build_object(v_general::text, 2));
    PERFORM reserve_tickets(700, v_event_id, jsonb_build_object(v_general::text, 1));

    UPDATE events
       SET status = 'cancelled', cancellation_reason = 'Planted edge case: artist unavailable.'
     WHERE event_id = v_event_id;                    -- cancel_event_reservations cancels both
END;
$$;


-- -----------------------------------------------------------------------------
-- 7. ANALYZE + counts
-- -----------------------------------------------------------------------------
DROP TABLE seed_cities;

ANALYZE;                       -- fresh planner statistics for the query and performance labs

SELECT (SELECT count(*) FROM users)                                  AS users,
       (SELECT count(*) FROM organizers)                             AS organizers,
       (SELECT count(*) FROM venues)                                 AS venues,
       (SELECT count(*) FROM events)                                 AS events,
       (SELECT count(*) FROM ticket_types)                           AS ticket_types,
       (SELECT count(*) FROM reservations)                           AS reservations,
       (SELECT count(*) FROM tickets)                                AS tickets,
       (SELECT count(*) FROM tickets WHERE status = 'cancelled')     AS cancelled_tickets;
