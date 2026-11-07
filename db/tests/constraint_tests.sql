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


-- #############################################################################
-- ticket_types, reservations, tickets, app functions
-- Seed ids used below (deterministic: same on every run_all.sql):
--   event 121 '[Edge] Sold Out Rooftop'   ticket types 239 'General' (5/5 sold), 240 'VIP' (0/10)
--   event 122 '[Edge] No Sales Workshop'  ticket type  241 'General' (position 1, 0/50)
--   event 123 '[Edge] Cancelled Concert'  ticket type  242 'General'
--   reservation 3238 = user 1 on event 121 (confirmed)
--   reservation 3239 = user 500 on event 121 (confirmed, code 'EBK-ME2USS', 3 tickets)
--   reservation 3240 = user 600 on event 123 (cancelled by the event cancel)
--   reservation 1501 = user 542 on past event 81 (confirmed, event already started)
-- Run order matters: T98–T100 change ticket types 240 and 241, so they come last.
-- #############################################################################


-- =============================================================================
-- ticket_types · CHECKs, UNIQUEs, FK
-- Valid base row: event_id 122, name 'T<n>', quantity 10, position <n>.
-- Leave price, max_per_checkout and the sales columns out unless the test names them.
-- =============================================================================

-- T53 · BR-T1 · name blank
-- values: name '   '
-- expect: ERROR ck_ticket_types_name_length
INSERT INTO ticket_types (event_id, name, quantity, position)
    VALUES (122, '   ', 10, 53);


-- T54 · BR-T2 · quantity below 1
-- values: quantity 0
-- expect: ERROR ck_ticket_types_quantity_range
INSERT INTO ticket_types (event_id, name, quantity, position)
    VALUES (122, 'T54', 0, 54);


-- T55 · BR-T2 · quantity above 100 000
-- values: quantity 100001
-- expect: ERROR ck_ticket_types_quantity_range
INSERT INTO ticket_types (event_id, name, quantity, position)
    VALUES (122, 'T55', 100001, 55);


-- T56 · BR-T5 · paid ticket in v0
-- values: price 5
-- expect: ERROR ck_ticket_types_price_v0_only
INSERT INTO ticket_types (event_id, name, quantity, position, price)
    VALUES (122, 'T56', 10, 56, 5);


-- T57 · BR-T5, D3 · negative price
--       (-1 also breaks v0_only, but CHECKs run in name order: non_negative < v0_only)
-- values: price -1
-- expect: ERROR ck_ticket_types_price_non_negative
INSERT INTO ticket_types (event_id, name, quantity, position, price)
    VALUES (122, 'T57', 10, 57, -1);


-- T58 · BR-T6 · sales_start after sales_end
-- values: sales_start now() + interval '2 days', sales_end now() + interval '1 day'
-- expect: ERROR ck_ticket_types_sales_start_before_end
INSERT INTO ticket_types (event_id, name, quantity, position, sales_start, sales_end)
    VALUES (122, 'T58', 10, 58, now() + interval '2 days', now() + interval '1 day');


-- T59 · BR-T7 · max_per_checkout below 1
-- values: max_per_checkout 0
-- expect: ERROR ck_ticket_types_max_per_checkout_range
INSERT INTO ticket_types (event_id, name, quantity, position, max_per_checkout)
    VALUES (122, 'T59', 10, 59, 0);


-- T60 · BR-T7 · max_per_checkout above 50
-- values: max_per_checkout 51
-- expect: ERROR ck_ticket_types_max_per_checkout_range
INSERT INTO ticket_types (event_id, name, quantity, position, max_per_checkout)
    VALUES (122, 'T60', 10, 60, 51);


-- T61 · BR-T8 · position already used in the same event
-- values: position 1 (241 'General' has it)
-- expect: ERROR uq_ticket_types_position_per_event
INSERT INTO ticket_types (event_id, name, quantity, position)
    VALUES (122, 'T61', 10, 1);


-- T62 · BR-T1 · name already used in the same event, different case
-- values: name 'GENERAL', position 62
-- expect: ERROR uq_ticket_types_event_name_lower
INSERT INTO ticket_types (event_id, name, quantity, position)
    VALUES (122, 'GENERAL', 10, 62);


-- T63 · BR-T1 · event that doesn't exist
-- values: event_id 999999
-- expect: ERROR fk_ticket_types_event
INSERT INTO ticket_types (event_id, name, quantity, position)
    VALUES (999999, 'T63', 10, 63);



-- =============================================================================
-- ticket_types · triggers and delete
-- =============================================================================

-- T64 · BR-R1, D2 · move a ticket type to another event
-- values: ticket_type_id 241, SET event_id = 121
-- expect: ERROR trg_ticket_types_reject_change_event
UPDATE ticket_types SET event_id = 121 WHERE ticket_type_id = 241;

-- T65 · BR-T4, D4 · lower quantity below the active tickets
-- values: ticket_type_id 239 (5 active), SET quantity = 4
-- expect: ERROR trg_ticket_types_guard_quantity


-- T66 · BR-T6, D6 · sales_end after the event ends (INSERT path)
-- values: base row with sales_end now() + interval '60 days' (event 122 ends in ~37 days)
-- expect: ERROR trg_ticket_types_guard_sales_end


-- T67 · BR-T6, D6 · sales_end after the event ends (UPDATE path)
-- values: ticket_type_id 241, SET sales_end = now() + interval '60 days'
-- expect: ERROR trg_ticket_types_guard_sales_end


-- T68 · BR-E6 · delete the last ticket type of a published event
-- values: ticket_type_id 241 (event 122's only type)
-- expect: ERROR trg_ticket_types_guard_delete


-- T69 · BR-T9 · delete a ticket type that has tickets
--       (event 121 has two types, so the last-type guard passes and the FK stops it)
-- values: ticket_type_id 239
-- expect: ERROR fk_tickets_ticket_type_event



-- =============================================================================
-- reservations
-- Valid base row: user_id 500, event_id 122, reference_code <the test's code>.
-- Direct INSERTs skip reserve_tickets(); that's fine, only the constraints are tested.
-- =============================================================================

-- T70 · BR-R3, D8 · reference_code already taken
-- values: reference_code 'EBK-ME2USS' (reservation 3239)
-- expect: ERROR reservations_reference_code_key
INSERT INTO reservations (user_id, event_id, reference_code)
    VALUES (500, 122, 'EBK-ME2USS');


-- T71 · BR-R3, D8 · reference_code with characters outside the alphabet (0, O, I, L, 1)
-- values: reference_code 'EBK-0OIL1A'
-- expect: ERROR ck_reservations_reference_code_format
INSERT INTO reservations (user_id, event_id, reference_code)
    VALUES (500, 122, 'EBK-0OIL1A');


-- T72 · BR-R5 · cancelled without cancelled_at
-- values: reference_code 'EBK-TSTAAA', status 'cancelled'
-- expect: ERROR ck_reservations_cancelled_at_iff_cancelled
INSERT INTO reservations (user_id, event_id, reference_code, status)
    VALUES (500, 122, 'EBK-TSTAAA', 'cancelled');


-- T73 · BR-R1 · user that doesn't exist
-- values: user_id 999999, reference_code 'EBK-TSTAAB'
-- expect: ERROR fk_reservations_user
INSERT INTO reservations (user_id, event_id, reference_code)
    VALUES (999999, 122, 'EBK-TSTAAB');


-- T74 · BR-R1 · event that doesn't exist
-- values: event_id 999999, reference_code 'EBK-TSTAAC'
-- expect: ERROR fk_reservations_event
INSERT INTO reservations (user_id, event_id, reference_code)
    VALUES (500, 999999, 'EBK-TSTAAC');


-- T75 · BR-K5 · transfer a reservation to another user
-- values: reservation_id 3239, SET user_id = 501
-- expect: ERROR trg_reservations_reject_change_keys


-- T76 · BR-R1, D2 · move a reservation to another event
-- values: reservation_id 3239, SET event_id = 122
-- expect: ERROR trg_reservations_reject_change_keys


-- T77 · BR-R5 · reactivate a cancelled reservation
-- values: reservation_id 3240, SET status = 'confirmed', cancelled_at = NULL
-- expect: ERROR trg_reservations_no_reactivate


-- T78 · BR-K4, D9 · delete a reservation
-- values: reservation_id 3239
-- expect: ERROR trg_reservations_no_delete



-- =============================================================================
-- tickets
-- Valid base row: reservation_id 3239, ticket_type_id 240, event_id 121, unit_price 0.
-- =============================================================================

-- T79 · BR-R7, D3 · negative unit_price
-- values: unit_price -1
-- expect: ERROR ck_tickets_unit_price_non_negative
INSERT INTO tickets (reservation_id, ticket_type_id, event_id, unit_price)
    VALUES (3239, 240, 121, -1);


-- T80 · BR-K3 · cancelled without cancelled_at
-- values: status 'cancelled'
-- expect: ERROR ck_tickets_cancelled_at_iff_cancelled
INSERT INTO tickets (reservation_id, ticket_type_id, event_id, unit_price, status)
    VALUES (3239, 240, 121, 0, 'cancelled');


-- T81 · BR-K2, D8 · code already taken
-- values: code = (SELECT code FROM tickets WHERE reservation_id = 3238 LIMIT 1)
-- expect: ERROR tickets_code_key
INSERT INTO tickets (reservation_id, ticket_type_id, event_id, unit_price, code)
    VALUES (3239, 240, 121, 0, (SELECT code FROM tickets WHERE reservation_id = 3238 LIMIT 1));


-- T82 · BR-R1, D2 · reservation from another event
-- values: reservation_id 3240 (event 123), event_id 121
-- expect: ERROR fk_tickets_reservation_event
INSERT INTO tickets (reservation_id, ticket_type_id, event_id, unit_price)
    VALUES (3240, 240, 121, 0);


-- T83 · BR-R1, D2 · ticket type from another event
-- values: ticket_type_id 241 (event 122), event_id 121
-- expect: ERROR fk_tickets_ticket_type_event
INSERT INTO tickets (reservation_id, ticket_type_id, event_id, unit_price)
    VALUES (3239, 241, 121, 0);


-- T84 · BR-K3 · reactivate a cancelled ticket
-- values: tickets of reservation 3240, SET status = 'active', cancelled_at = NULL
-- expect: ERROR trg_tickets_status_transition


-- T85 · BR-R7 · change the price snapshot
-- values: tickets of reservation 3239, SET unit_price = 1
-- expect: ERROR trg_tickets_reject_change_keys


-- T86 · BR-K2 · change the QR code
-- values: tickets of reservation 3239, SET code = gen_random_uuid()
-- expect: ERROR trg_tickets_reject_change_keys


-- T87 · BR-K4, D9 · delete a ticket
-- values: tickets of reservation 3239
-- expect: ERROR trg_tickets_no_delete



-- =============================================================================
-- reserve_tickets(user_id, event_id, items)
-- These RAISEs have no constraint name: expect is the SQLSTATE + message.
-- Call it with SELECT reserve_tickets(...). items is JSON text, e.g. '{"241": 1}'.
-- =============================================================================

-- T88 · BR-T7 · no ticket types requested
-- values: user 500, event 122, items '{}'
-- expect: ERROR 23514 No tickets specified for reservation


-- T89 · BR-U6 · anonymized user
-- setup (succeeds): SELECT anonymize_user(900);
-- values: user 900, event 122, items '{"241": 1}'
-- expect: ERROR 23514 User 900 is deleted and cannot make reservations


-- T90 · BR-R1 · event that doesn't exist
-- values: user 500, event 999999, items '{"241": 1}'
-- expect: ERROR P0002 Event 999999 not found


-- T91 · BR-R2 · draft event
-- values: user 500, event 2, items '{"241": 1}'
-- expect: ERROR 23514 Event 2 is not available for reservation


-- T92 · BR-R2, BR-E9 · cancelled event
-- values: user 500, event 123, items '{"242": 1}'
-- expect: ERROR 23514 Event 123 is not available for reservation


-- T93 · BR-R2 · event already started
-- values: user 500, event 81, items '{"241": 1}'
-- expect: ERROR 23514 Event 81 is not available for reservation


-- T94 · BR-R1 · ticket type of another event
-- values: user 500, event 122, items '{"240": 1}' (240 belongs to event 121)
-- expect: ERROR P0002 Ticket type 240 does not exist for event 122


-- T95 · BR-T7 · quantity 0
-- values: user 500, event 122, items '{"241": 0}'
-- expect: ERROR 23514 Quantity for ticket type 241 must be at least 1 and at most 10


-- T96 · BR-T7 · quantity above max_per_checkout (10)
-- values: user 500, event 122, items '{"241": 11}'
-- expect: ERROR 23514 Quantity for ticket type 241 must be at least 1 and at most 10


-- T97 · BR-T3, D4 · sold out
-- values: user 500, event 121, items '{"239": 1}'
-- expect: ERROR 23514 Not enough tickets available for ticket type 239


-- T98 · BR-R2, BR-T6 · sales haven't started
-- setup (succeeds): ticket_type_id 240, SET sales_start = now() + interval '1 day'
-- values: user 500, event 121, items '{"240": 1}'
-- expect: ERROR 23514 Ticket type 240 is not available for reservation


-- T99 · BR-R2, BR-T6 · sales already ended
-- setup (succeeds): ticket_type_id 241, SET sales_end = now() - interval '1 hour'
-- values: user 500, event 122, items '{"241": 1}'
-- expect: ERROR 23514 Ticket type 241 is not available for reservation


-- T100 · BR-T9 · ticket type taken off sale
-- setup (succeeds): ticket_type_id 240, SET sales_start = NULL, off_sale_at = now()
--   (clear sales_start so only off_sale_at can stop it)
-- values: user 500, event 121, items '{"240": 1}'
-- expect: ERROR 23514 Ticket type 240 is not available for reservation


-- T101 · BR-R6 · every failed checkout above rolled back completely
--       (a query, not a failing statement: count the reservations on event 122)
-- expect: 0



-- =============================================================================
-- cancel_reservation(user_id, reservation_id)
-- Call it with SELECT cancel_reservation(...).
-- =============================================================================

-- T102 · BR-R5 · cancel someone else's reservation
-- values: user 501, reservation 3239 (belongs to user 500)
-- expect: ERROR P0002 reservation 3239 not found for user 501


-- T103 · BR-R5 · cancel a reservation that's already cancelled
-- values: user 600, reservation 3240
-- expect: ERROR 23514 Reservation: 3240 is already cancelled.


-- T104 · BR-R5 · cancel after the event started
-- values: user 542, reservation 1501 (event 81, in the past)
-- expect: ERROR 23514 Reservation: 1501 can't be cancelled, the event has started.



-- =============================================================================
-- invariants (queries that must return 0 rows)
-- =============================================================================

-- T105 · 02-design denormalizations · ticket status matches its reservation's status (v0)
--       (a ticket is cancelled exactly when its reservation is)
-- expect: 0 rows

