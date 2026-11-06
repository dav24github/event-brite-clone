-- =============================================================================
-- constraint_tests.sql · one deliberate violation per constraint
-- Every statement here must FAIL. Run WITHOUT ON_ERROR_STOP:
--   psql -U postgres -d eventbrite_lab -f db/run_all.sql                (fresh data first)
--   psql -U postgres -d eventbrite_lab -f db/tests/constraint_tests.sql
-- Format:
--   -- T1 · BR-?? · <what it violates>
--   -- expect: ERROR <constraint_name>
--   INSERT ...;
--
-- Runs against the seeded database (run_all.sql first). Rows it relies on:
--   users 1–25 are organizers · user 500 is an attendee, not an organizer
--   '[Edge] Sold Out Rooftop' (organizer 2, published) · category slug 'music'
-- Each statement breaks ONE constraint; every other value in it must be valid,
-- or Postgres may report a different error first.
-- Tag new values with the test number ('T2@test.com', name 'T2'), so a test that
-- succeeds by mistake leaves a row that's easy to find.
-- A "setup" line marks a statement that is allowed to succeed.
-- NOT NULL and VARCHAR lengths aren't tested here: Postgres enforces them itself.
-- =============================================================================

SET search_path TO eventbrite;    -- a new session doesn't keep run_all.sql's search_path
\set ECHO all
\set VERBOSITY verbose


-- =============================================================================
-- users
-- =============================================================================

-- T1 · BR-U1 · email already taken (seeded users have lowercase emails)
-- expect: ERROR users_email_key
INSERT INTO users (email, password_hash, full_name) 
    VALUES('user1@example.com', 'hash', 'T1');


-- T2 · BR-U1 · email not lowercase
-- expect: ERROR ck_users_email_lowercase
INSERT INTO users (email, password_hash, full_name)
    VALUES('T2@test.com', 'hash', 'T2');


-- T3 · BR-U1 · email without '@'
-- expect: ERROR ck_users_email_format
INSERT INTO users (email, password_hash, full_name)
    VALUES('t3-test.com', 'hash', 'T3');


-- T4 · BR-U2 · password_hash blank
-- values: email 't4@test.com', password_hash '   ', full_name 'T4'
-- expect: ERROR ck_users_password_hash_not_blank
INSERT INTO users (email, password_hash, full_name)
    VALUES('t4@test.com', '   ', 'T4');


-- T5 · BR-U3 · full_name blank
-- expect: ERROR ck_users_full_name_not_blank
INSERT INTO users (email, password_hash, full_name)
    VALUES('t5@test.com', 'hash', '    ');


-- T6 · BR-U6 · hard delete of a user with reservations
-- values: user_id 500 (2 reservations, not an organizer, so only this FK applies)
-- expect: ERROR fk_reservations_user
DELETE FROM users WHERE user_id = 500;

-- =============================================================================
-- organizers
-- =============================================================================

-- T7 · D1 · a user who is already an organizer enabled twice
-- values: user_id 1 (already 'Food Society'), organizer_name 'T7 Org'
-- expect: ERROR organizers_pkey
INSERT INTO organizers (user_id, organizer_name) VALUES (1, 'T7 Org');


-- T8 · BR-U4, D1 · organizer for a user that doesn't exist
-- values: user_id 999999, organizer_name 'T8 Org'
-- expect: ERROR fk_organizers_user
INSERT INTO organizers (user_id, organizer_name) VALUES (999999, 'T8 Org');


-- T9 · BR-U4 · organizer_name shorter than 2 characters after trimming
-- values: user_id 500, organizer_name ' A '
-- expect: ERROR ck_organizers_name_length
INSERT INTO organizers (user_id, organizer_name) VALUES (500, ' A ');


-- T10 · BR-U4 · organizer_name already used, different case
-- values: user_id 500, organizer_name 'FOOD SOCIETY' (user 1 has 'Food Society')
-- expect: ERROR uq_organizers_name_lower
INSERT INTO organizers (user_id, organizer_name) VALUES (500, 'FOOD SOCIETY');


-- T11 · BR-U6 · hard delete of an organizer who owns events
-- values: organizer user_id 2 (owns '[Edge] Sold Out Rooftop')
-- expect: ERROR fk_events_organizer
DELETE FROM organizers WHERE user_id = 2;


-- =============================================================================
-- categories
-- =============================================================================

-- T12 · BR-C1 · name already taken
-- values: name 'Music', slug 't12'
-- expect: ERROR categories_name_key
INSERT INTO categories (name, slug) VALUES ('Music', 't12');


-- T13 · BR-C1 · slug already taken
-- values: name 'T13', slug 'music'
-- expect: ERROR categories_slug_key
INSERT INTO categories (name, slug) VALUES ('T13', 'music');


-- T14 · BR-C1 · name blank
-- values: name '   ', slug 't14'
-- expect: ERROR ck_categories_name_not_blank
INSERT INTO categories (name, slug) VALUES ('   ', 't14');


-- T15 · BR-C1 · slug with uppercase or spaces
-- values: name 'T15', slug 'Live Music'
-- expect: ERROR ck_categories_slug_format
INSERT INTO categories (name, slug) VALUES ('T15', 'Live Music');


-- T16 · BR-C1 · slug with a double hyphen
-- values: name 'T16', slug 'live--music'
-- expect: ERROR ck_categories_slug_format
INSERT INTO categories (name, slug) VALUES ('T16', 'live--music');


-- T17 · BR-C3 · delete a category that events use
-- values: category slug 'music'
-- expect: ERROR fk_events_category
DELETE FROM categories WHERE slug = 'music';



-- =============================================================================
-- venues
-- Valid base row: name 'T<n> Venue', address 'Calle 1 #2-3', city 'Bogotá',
-- country 'CO', no coordinates. Change only the value the test names.
-- =============================================================================

-- T18 · BR-L2 · name blank
-- values: name '   '
-- expect: ERROR ck_venues_name_not_blank
INSERT INTO venues (name, address, city, country)
    VALUES ('   ', 'Calle 1 #2-3', 'Bogotá', 'CO');


-- T19 · BR-L2 · address blank
-- values: address '   '
-- expect: ERROR ck_venues_address_not_blank
INSERT INTO venues (name, address, city, country)
    VALUES ('T19 Venue', '   ', 'Bogotá', 'CO');


-- T20 · BR-L2 · city blank
-- values: city '   '
-- expect: ERROR ck_venues_city_not_blank
INSERT INTO venues (name, address, city, country)
    VALUES ('T20 Venue', 'Calle 1 #2-3', '   ', 'CO');


-- T21 · BR-L2 · country not two uppercase letters
-- values: country 'co'
-- expect: ERROR ck_venues_country_format
INSERT INTO venues (name, address, city, country)
    VALUES ('T21 Venue', 'Calle 1 #2-3', 'Bogotá', 'co');


-- T22 · BR-L2 · latitude out of range
-- values: latitude -91, longitude 0
-- expect: ERROR ck_venues_latitude_range
INSERT INTO venues (name, address, city, country, latitude, longitude)
    VALUES ('T22 Venue', 'Calle 1 #2-3', 'Bogotá', 'CO', -91, 0);


-- T23 · BR-L2 · longitude out of range
-- values: latitude 0, longitude 181
-- expect: ERROR ck_venues_longitude_range
INSERT INTO venues (name, address, city, country, latitude, longitude)
    VALUES ('T23 Venue', 'Calle 1 #2-3', 'Bogotá', 'CO', 0, 181);


-- T24 · BR-L2 · latitude without longitude
-- values: latitude 4.711, longitude NULL
-- expect: ERROR ck_venues_coords_both_or_neither
INSERT INTO venues (name, address, city, country, latitude)
    VALUES ('T24 Venue', 'Calle 1 #2-3', 'Bogotá', 'CO', 4.711);


-- T25 · BR-L5, BR-R7 · delete a venue that events use
-- values: venue_id 1
-- expect: ERROR fk_events_venue
DELETE FROM venues WHERE venue_id = 1;



-- =============================================================================
-- events · CHECKs and FKs
-- Valid base row (a draft): organizer_id 1, title 'T<n> Event',
-- starts_at now() + interval '30 days', ends_at now() + interval '30 days 2 hours',
-- timezone 'America/Bogota', currency 'COP'. Leave status out (defaults to draft).
-- Change or add only the value the test names.
-- Seeded rows used below: event_id 2 is a complete future draft with 3 ticket types.
-- =============================================================================

-- T26 · BR-E2 · title shorter than 3 characters after trimming
-- values: title ' AB '
-- expect: ERROR ck_events_title_length
INSERT INTO events (organizer_id, title, starts_at, ends_at, timezone, currency)
    VALUES (1, ' AB ', now() + interval '30 days', now() + interval '30 days 2 hours', 'America/Bogota', 'COP');


-- T27 · BR-E3 · ends_at before starts_at
-- values: ends_at now() + interval '29 days'
-- expect: ERROR ck_events_ends_after_start
INSERT INTO events (organizer_id, title, starts_at, ends_at, timezone, currency)
    VALUES (1, 'T27 Event', now() + interval '30 days', now() + interval '29 days', 'America/Bogota', 'COP');


-- T28 · BR-E3 · duration longer than 14 days
-- values: ends_at now() + interval '45 days'
-- expect: ERROR ck_events_ends_after_start
INSERT INTO events (organizer_id, title, starts_at, ends_at, timezone, currency)
    VALUES (1, 'T28 Event', now() + interval '30 days', now() + interval '45 days', 'America/Bogota', 'COP');


-- T29 · BR-E11 · cover_url not https
-- values: cover_url 'http://img.example.com/t29.jpg'
-- expect: ERROR ck_events_cover_url_format
INSERT INTO events (organizer_id, title, starts_at, ends_at, timezone, currency, cover_url)
    VALUES (1, 'T29 Event', now() + interval '30 days', now() + interval '30 days 2 hours', 'America/Bogota', 'COP', 'http://img.example.com/t29.jpg');


-- T30 · BR-L3 · meeting_url not https
-- values: location_type 'online', meeting_url 'http://meet.example.com/t30'
-- expect: ERROR ck_events_meeting_url_format
INSERT INTO events (organizer_id, title, starts_at, ends_at, timezone, currency, location_type, meeting_url)
    VALUES (1, 'T30 Event', now() + interval '30 days', now() + interval '30 days 2 hours', 'America/Bogota', 'COP', 'online', 'http://meet.example.com/t30');


-- T31 · BR-T5, D3 · currency not three uppercase letters
-- values: currency 'cop'
-- expect: ERROR ck_events_currency_format
INSERT INTO events (organizer_id, title, starts_at, ends_at, timezone, currency)
    VALUES (1, 'T31 Event', now() + interval '30 days', now() + interval '30 days 2 hours', 'America/Bogota', 'cop');


-- T32 · BR-L1 · online event with a venue_id
-- values: location_type 'online', venue_id 1
-- expect: ERROR ck_events_location_exclusive
INSERT INTO events (organizer_id, title, starts_at, ends_at, timezone, currency, location_type, venue_id)
    VALUES (1, 'T32 Event', now() + interval '30 days', now() + interval '30 days 2 hours', 'America/Bogota', 'COP', 'online', 1);


-- T33 · BR-L1 · in-person event with a meeting_url
-- values: location_type 'in_person', meeting_url 'https://meet.example.com/t33'
-- expect: ERROR ck_events_location_exclusive
INSERT INTO events (organizer_id, title, starts_at, ends_at, timezone, currency, location_type, meeting_url)
    VALUES (1, 'T33 Event', now() + interval '30 days', now() + interval '30 days 2 hours', 'America/Bogota', 'COP', 'in_person', 'https://meet.example.com/t33');


-- T34 · BR-E6, BR-C2 · publish a draft without a description
--       (one UPDATE: the status trigger passes, then the CHECK fails)
-- values: event_id 2, SET status = 'published', description = NULL
-- expect: ERROR ck_events_when_is_draft
UPDATE events SET status = 'published', description = NULL WHERE event_id = 2;


-- T35 · BR-E6 · set published_at on a draft without publishing it
-- values: event_id 2, SET published_at = now()
-- expect: ERROR ck_events_published_at_iff_not_draft
UPDATE events SET published_at = now() WHERE event_id = 2;


-- T36 · BR-E9 · set cancelled_at on a published event without cancelling it
-- values: title '[Edge] Sold Out Rooftop', SET cancelled_at = now()
-- expect: ERROR ck_events_when_is_cancelled
UPDATE events SET cancelled_at = now() WHERE title = '[Edge] Sold Out Rooftop';


-- T37 · BR-E1 · organizer_id of a user who isn't an organizer
-- values: base row with organizer_id 500
-- expect: ERROR fk_events_organizer
INSERT INTO events (organizer_id, title, starts_at, ends_at, timezone, currency)
    VALUES (500, 'T37 Event', now() + interval '30 days', now() + interval '30 days 2 hours', 'America/Bogota', 'COP');


-- T38 · BR-C3 · category_id that doesn't exist
-- values: base row with category_id 999999
-- expect: ERROR fk_events_category
INSERT INTO events (organizer_id, title, starts_at, ends_at, timezone, currency, category_id)
    VALUES (1, 'T38 Event', now() + interval '30 days', now() + interval '30 days 2 hours', 'America/Bogota', 'COP', 999999);


-- T39 · BR-L2 · venue_id that doesn't exist
-- values: base row with location_type 'in_person', venue_id 999999
-- expect: ERROR fk_events_venue
INSERT INTO events (organizer_id, title, starts_at, ends_at, timezone, currency, location_type, venue_id)
    VALUES (1, 'T39 Event', now() + interval '30 days', now() + interval '30 days 2 hours', 'America/Bogota', 'COP', 'in_person', 999999);



-- =============================================================================
-- events · triggers
-- =============================================================================

-- T40 · BR-E4, D7 · timezone that isn't an IANA name (INSERT path)
-- values: base row with timezone 'Mars/Olympus'
-- expect: ERROR trg_events_guard_timezone
INSERT INTO events (organizer_id, title, starts_at, ends_at, timezone, currency)
    VALUES (1, 'T40 Event', now() + interval '30 days', now() + interval '30 days 2 hours', 'Mars/Olympus', 'COP');


-- T41 · BR-E4, D7 · change a valid timezone to an invalid one (UPDATE path)
-- values: title '[Edge] No Sales Workshop', SET timezone = 'Mars/Olympus'
-- expect: ERROR trg_events_guard_timezone
UPDATE events SET timezone = 'Mars/Olympus' WHERE title = '[Edge] No Sales Workshop';


-- T42 · BR-E5, BR-E6 · INSERT straight as published
-- values: base row with status 'published'
-- expect: ERROR trg_events_guard_insert
INSERT INTO events (organizer_id, title, starts_at, ends_at, timezone, currency, status)
    VALUES (1, 'T42 Event', now() + interval '30 days', now() + interval '30 days 2 hours', 'America/Bogota', 'COP', 'published');


-- T43 · BR-E5 · draft → cancelled (not an allowed move)
-- values: event_id 2, SET status = 'cancelled'
-- expect: ERROR trg_events_status_transition
UPDATE events SET status = 'cancelled' WHERE event_id = 2;


-- T44 · BR-E5 · published → draft (no going back)
-- values: title '[Edge] Sold Out Rooftop', SET status = 'draft'
-- expect: ERROR trg_events_status_transition
UPDATE events SET status = 'draft' WHERE title = '[Edge] Sold Out Rooftop';


-- T45 · BR-E5 · cancelled → published (cancelled is final)
-- values: title '[Edge] Cancelled Concert', SET status = 'published'
-- expect: ERROR trg_events_status_transition
UPDATE events SET status = 'published' WHERE title = '[Edge] Cancelled Concert';


-- T46 · BR-E6, D5 · publish a draft whose starts_at is already in the past
-- setup 1 (succeeds): INSERT a complete draft: base row with title 'T46 Event',
--   starts_at now() - interval '1 day', ends_at now() - interval '1 day' + interval '2 hours',
--   category_id 1, description 'T46', location_type 'online', meeting_url 'https://meet.example.com/t46'
-- setup 2 (succeeds): INSERT a ticket type for it: name 'General', quantity 10, position 1
--   (find the event_id with a subquery on title = 'T46 Event')
-- test: publish it (SET status = 'published' WHERE title = 'T46 Event')
-- expect: ERROR trg_events_status_transition
INSERT INTO events (organizer_id, title, starts_at, ends_at, timezone, currency, category_id, description, location_type, meeting_url)
    VALUES (1, 'T46 Event', now() - interval '1 day', now() - interval '1 day' + interval '2 hours', 'America/Bogota', 'COP', 1, 'T46', 'online', 'https://meet.example.com/t46');
INSERT INTO ticket_types (event_id, name, quantity, position)
    VALUES ((SELECT event_id FROM events WHERE title = 'T46 Event'), 'General', 10, 1);
UPDATE events SET status = 'published' WHERE title = 'T46 Event';


-- T47 · BR-E6, D5 · publish a complete draft with no ticket types
-- setup (succeeds): INSERT a complete future draft: base row with title 'T47 Event',
--   category_id 1, description 'T47', location_type 'online', meeting_url 'https://meet.example.com/t47'
-- test: publish it (SET status = 'published' WHERE title = 'T47 Event')
-- expect: ERROR trg_events_status_transition
INSERT INTO events (organizer_id, title, starts_at, ends_at, timezone, currency, category_id, description, location_type, meeting_url)
    VALUES (1, 'T47 Event', now() + interval '30 days', now() + interval '30 days 2 hours', 'America/Bogota', 'COP', 1, 'T47', 'online', 'https://meet.example.com/t47');
UPDATE events SET status = 'published' WHERE title = 'T47 Event';


-- T48 · BR-E8, D9 · delete an event that was ever published
-- values: title '[Edge] No Sales Workshop' (published, no reservations, so only the trigger can stop it)
-- expect: ERROR trg_events_guard_delete
DELETE FROM events WHERE title = '[Edge] No Sales Workshop';


-- T49 · BR-E1 · change organizer_id (to another organizer, so the FK passes)
-- values: title '[Edge] Sold Out Rooftop' (organizer 2), SET organizer_id = 3
-- expect: ERROR trg_events_reject_change_organizer
UPDATE events SET organizer_id = 3 WHERE title = '[Edge] Sold Out Rooftop';


-- T50 · BR-E6 · change published_at once it's set
-- values: title '[Edge] Sold Out Rooftop', SET published_at = published_at - interval '1 day'
-- expect: ERROR trg_events_reject_change_timestamps
UPDATE events SET published_at = published_at - interval '1 day' WHERE title = '[Edge] Sold Out Rooftop';


-- T51 · BR-E9 · change cancelled_at once it's set
-- values: title '[Edge] Cancelled Concert', SET cancelled_at = cancelled_at - interval '1 day'
-- expect: ERROR trg_events_reject_change_timestamps
UPDATE events SET cancelled_at = cancelled_at - interval '1 day' WHERE title = '[Edge] Cancelled Concert';


-- T52 · BR-T6, D6 · move ends_at before a ticket type's sales_end
-- setup (succeeds): on '[Edge] No Sales Workshop', SET its 'General' ticket type's
--   sales_end = the event's starts_at + interval '1 hour' (the event lasts 2 hours, so it's valid)
-- test: SET the event's ends_at = starts_at + interval '30 minutes'
--   (still after starts_at, so only the trigger can stop it)
-- expect: ERROR trg_events_guard_ends_at
UPDATE ticket_types 
    SET sales_end = (SELECT starts_at + interval '1 hour' FROM events WHERE title = '[Edge] No Sales Workshop') 
WHERE event_id = (SELECT event_id FROM events WHERE title = '[Edge] No Sales Workshop') AND name = 'General';
UPDATE events
   SET ends_at = starts_at + interval '30 minutes'
 WHERE title = '[Edge] No Sales Workshop';