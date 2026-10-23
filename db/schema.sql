-- =============================================================================
-- schema.sql · types, tables, indexes, functions and triggers
-- Every constraint is named and tagged with the rule ID it enforces, e.g.
--   CONSTRAINT ck_events_ends_after_start CHECK (ends_at > starts_at)  -- BR-E?
-- Rules: docs/01-business-rules.md · Checklist: docs/03-schema-checklist.md
-- Order: types → tables (FK order) → indexes → trigger functions + triggers → functions called by the app
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Types
-- -----------------------------------------------------------------------------

CREATE TYPE event_status  AS ENUM ('draft', 'published', 'cancelled', 'completed');  -- BR-E5
CREATE TYPE location_type AS ENUM ('in_person', 'online');                           -- BR-L1
CREATE TYPE reservation_status AS ENUM ('confirmed', 'cancelled');                 -- BR-R4 (v1 adds pending, paid, refunded, expired)
CREATE TYPE ticket_status      AS ENUM ('active', 'cancelled');                           -- BR-K3 (check-in adds used)

-- -----------------------------------------------------------------------------
-- Tables
-- -----------------------------------------------------------------------------

CREATE TABLE users (
    user_id         BIGINT          PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
    email           TEXT            NOT NULL UNIQUE,                                     -- BR-U1 (stored lowercase, so plain UNIQUE is case-insensitive)
    password_hash   TEXT            NOT NULL,                                            -- BR-U2
    full_name       VARCHAR(100)    NOT NULL,                                            -- BR-U3
    created_at      TIMESTAMPTZ     NOT NULL DEFAULT now(),                              -- BR-U7
    updated_at      TIMESTAMPTZ     NOT NULL DEFAULT now(),                              -- BR-U7 (trigger keeps it current)
    deleted_at      TIMESTAMPTZ,                                                         -- D9 (set when anonymized)

    CONSTRAINT ck_users_email_lowercase         CHECK (email = lower(email)),            -- BR-U1
    CONSTRAINT ck_users_email_format            CHECK (email ~ '^[^@\s]+@[^@\s]+$'),     -- BR-U1
    CONSTRAINT ck_users_password_hash_not_blank CHECK (btrim(password_hash) <> ''),      -- BR-U2
    CONSTRAINT ck_users_full_name_not_blank     CHECK (btrim(full_name) <> '')           -- BR-U3
);

CREATE TABLE organizers (
    user_id         BIGINT          PRIMARY KEY,                                         -- D1 (same id as users, not generated)
    organizer_name  VARCHAR(80)     NOT NULL,                                            -- BR-U4
    enabled_at      TIMESTAMPTZ     NOT NULL DEFAULT now(),                              -- D1

    CONSTRAINT ck_organizers_name_length CHECK (char_length(btrim(organizer_name)) >= 2),                       -- BR-U4

    CONSTRAINT fk_organizers_user FOREIGN KEY (user_id) REFERENCES users (user_id) ON DELETE RESTRICT          -- BR-U4, BR-U6, D1
);

CREATE UNIQUE INDEX uq_organizers_name_lower ON organizers (lower(organizer_name));     -- BR-U4

-- Lookup table, seeded by the platform (BR-C1)
CREATE TABLE categories (
    category_id     BIGINT          PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
    name            VARCHAR(50)     NOT NULL UNIQUE,                                     -- BR-C1
    slug            VARCHAR(50)     NOT NULL UNIQUE,                                     -- BR-C1

    CONSTRAINT ck_categories_name_not_blank CHECK (btrim(name) <> ''),                   -- BR-C1
    CONSTRAINT ck_categories_slug_format    CHECK (slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$')    -- BR-C1
);

CREATE TABLE venues (
    venue_id        BIGINT          PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
    name            VARCHAR(120)    NOT NULL,                                            -- BR-L2
    address         VARCHAR(200)    NOT NULL,                                            -- BR-L2
    city            VARCHAR(80)     NOT NULL,                                            -- BR-L2
    country         CHAR(2)         NOT NULL,                                            -- BR-L2 (ISO 3166-1 alpha-2)
    postal_code     VARCHAR(20),
    latitude        NUMERIC(8,6),                                                        -- ±90.000000
    longitude       NUMERIC(9,6),                                                        -- ±180.000000

    CONSTRAINT ck_venues_name_not_blank    CHECK (btrim(name) <> ''),                    -- BR-L2
    CONSTRAINT ck_venues_address_not_blank CHECK (btrim(address) <> ''),                 -- BR-L2
    CONSTRAINT ck_venues_city_not_blank    CHECK (btrim(city) <> ''),                    -- BR-L2
    CONSTRAINT ck_venues_country_format    CHECK (country ~ '^[A-Z]{2}$'),               -- BR-L2
    CONSTRAINT ck_venues_latitude_range    CHECK (latitude BETWEEN -90 AND 90),          -- BR-L2
    CONSTRAINT ck_venues_longitude_range   CHECK (longitude BETWEEN -180 AND 180),       -- BR-L2
    CONSTRAINT ck_venues_coords_both_or_neither
        CHECK ((latitude IS NULL) = (longitude IS NULL))                                 -- BR-L2
);

CREATE TABLE events (
    event_id            BIGINT         PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
    organizer_id        BIGINT         NOT NULL,                                            -- BR-E1 (immutable, trigger)
    category_id         BIGINT,                                                             -- BR-C2 (nullable in draft)
    location_type       location_type,                                                      -- BR-L1, BR-L4 (nullable in draft)
    venue_id            BIGINT,                                                             -- BR-L1, BR-L2 (in_person only)
    meeting_url         VARCHAR(200),                                                       -- BR-L1, BR-L3 (online only)
    title               VARCHAR(120)   NOT NULL,                                            -- BR-E2
    description         VARCHAR(10000),                                                     -- BR-E2 (nullable in draft)
    status              event_status   NOT NULL DEFAULT 'draft',                            -- BR-E5
    starts_at           TIMESTAMPTZ    NOT NULL,                                            -- BR-E3
    ends_at             TIMESTAMPTZ    NOT NULL,                                            -- BR-E3
    timezone            VARCHAR(50)    NOT NULL,                                            -- BR-E4, D7 (IANA tz database name)
    currency            CHAR(3)        NOT NULL,                                            -- BR-T5, D3 (ISO 4217)
    cover_url           VARCHAR(2048),                                                      -- BR-E11
    published_at        TIMESTAMPTZ,                                                        -- BR-E6 (set iff not draft)
    cancelled_at        TIMESTAMPTZ,                                                        -- BR-E9 (set iff cancelled)
    cancellation_reason VARCHAR(500),                                                       -- BR-E9
    created_at          TIMESTAMPTZ    NOT NULL DEFAULT now(),                              -- BR-E12
    updated_at          TIMESTAMPTZ    NOT NULL DEFAULT now(),                              -- BR-E12 (trigger keeps it current)

    CONSTRAINT ck_events_title_length CHECK (char_length(btrim(title)) >= 3),                        -- BR-E2
    CONSTRAINT ck_events_ends_after_start CHECK (ends_at > starts_at AND (ends_at - starts_at) <= INTERVAL '14 days' ), -- BR-E3
    CONSTRAINT ck_events_when_is_draft CHECK ( -- BR-E6, BR-C2, BR-L4
        (status = 'draft') OR (description IS NOT NULL AND
        category_id IS NOT NULL AND 
        ((location_type = 'in_person' AND venue_id IS NOT NULL) OR
         (location_type = 'online'    AND meeting_url IS NOT NULL)))
    ), -- not iff "OR"
    CONSTRAINT ck_events_when_is_cancelled CHECK ( -- BR-E9
        (status = 'cancelled') = (cancelled_at IS NOT NULL)
    ), -- iff "="
    CONSTRAINT ck_events_published_at_iff_not_draft CHECK ((status = 'draft') = (published_at IS NULL)),  -- BR-E6
    -- No now() in a CHECK: Postgres only checks it on INSERT/UPDATE, so it goes stale as time passes
    -- and a dump restore fails for past events. "starts_at > now() on publish" is in the events trigger (BR-E6, D5).
    CONSTRAINT ck_events_cover_url_format CHECK (cover_url ~ '^https://.+'),                       -- BR-E11
    CONSTRAINT ck_events_meeting_url_format CHECK (meeting_url ~ '^https://.+'),  -- BR-L3
    CONSTRAINT ck_events_currency_format CHECK (currency ~ '^[A-Z]{3}$'),    -- BR-T5, D3
    CONSTRAINT ck_events_location_exclusive CHECK ( -- BR-L1
        (venue_id    IS NULL OR location_type = 'in_person') AND
        (meeting_url IS NULL OR location_type = 'online')
    ),
    
    CONSTRAINT fk_events_organizer FOREIGN KEY (organizer_id) REFERENCES organizers (user_id) ON DELETE RESTRICT, -- BR-E1, BR-U6
    CONSTRAINT fk_events_venue FOREIGN KEY (venue_id) REFERENCES venues (venue_id) ON DELETE RESTRICT, -- BR-L2, BR-R7
    CONSTRAINT fk_events_category FOREIGN KEY (category_id) REFERENCES categories (category_id) ON DELETE RESTRICT -- BR-C3
);

CREATE TABLE ticket_types (
    ticket_type_id  BIGINT PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
    event_id        BIGINT NOT NULL,                                                        -- BR-T1 (immutable, trigger)
    name            VARCHAR(60) NOT NULL,                                                   -- BR-T1 (unique per event on lower(), index below)
    description     VARCHAR(500),                                                           -- BR-T1
    price           NUMERIC(12, 2) NOT NULL DEFAULT 0,                                      -- BR-T5, D3 (0 in v0)
    quantity        INT NOT NULL,                                                           -- BR-T2
    max_per_checkout INT NOT NULL DEFAULT 10,                                               -- BR-T7
    position        INT NOT NULL,                                                           -- BR-T8
    sales_start     TIMESTAMPTZ,                                                            -- BR-T6 (NULL = published_at)
    sales_end       TIMESTAMPTZ,                                                            -- BR-T6 (NULL = starts_at; <= events.ends_at, trigger)
    off_sale_at     TIMESTAMPTZ,                                                            -- BR-T9

    -- uq
    -- ticket_type_id is unique by itself (PK), but Postgres rejects the tickets composite FK (ticket_type_id, event_id) unless the target columns have a matching UNIQUE or PK constraint.
    CONSTRAINT uq_ticket_types_id_event          UNIQUE (ticket_type_id, event_id),   -- BR-R1, D2
    CONSTRAINT uq_ticket_types_position_per_event UNIQUE (event_id, position),  -- BR-T8

    -- ck
    CONSTRAINT ck_ticket_types_name_length CHECK (btrim(name) <> ''),  -- BR-T1
    CONSTRAINT ck_ticket_types_quantity_range CHECK (quantity >= 1 AND quantity <= 100000),  -- BR-T2
    CONSTRAINT ck_ticket_types_price_v0_only CHECK (price = 0),  -- BR-T5
    CONSTRAINT ck_ticket_types_price_non_negative CHECK (price >= 0),  -- BR-T5, D3
    CONSTRAINT ck_ticket_types_sales_start_before_end CHECK (sales_start IS NULL OR sales_end IS NULL OR sales_start < sales_end),  -- BR-T6
    CONSTRAINT ck_ticket_types_max_per_checkout_range CHECK (max_per_checkout >= 1 AND max_per_checkout <= 50),  -- BR-T7
    
    -- fk
    CONSTRAINT fk_ticket_types_event FOREIGN KEY (event_id) REFERENCES events (event_id) ON DELETE CASCADE -- BR-T1, BR-E8, D9
);

-- CREATE INDEX allows duplicate values in the indexed column
-- CREATE UNIQUE INDEX enforces uniqueness; NULLs count as distinct, so several NULL rows are allowed (PG15+: NULLS NOT DISTINCT).
--      Declaring a PRIMARY KEY or UNIQUE constraint automatically generates a UNIQUE INDEX behind the scenes.
--      Use it where needed for Functional or Filtered uniqueness.
CREATE UNIQUE INDEX uq_ticket_types_event_name_lower ON ticket_types (event_id, lower(name)); -- BR-T1

CREATE TABLE reservations (
    reservation_id   BIGINT PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
    user_id          BIGINT NOT NULL,                                                       -- BR-R1
    event_id         BIGINT NOT NULL,                                                       -- BR-R1 (immutable, trigger)
    reference_code   CHAR(10) NOT NULL UNIQUE,                                              -- BR-R3, D8 (EBK- + 6 chars, random)
    status           reservation_status NOT NULL DEFAULT 'confirmed',                       -- BR-R4
    created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),                                    -- BR-R1
    cancelled_at     TIMESTAMPTZ,                                                           -- BR-R5 (set iff cancelled)

    -- uq
    CONSTRAINT uq_reservations_id_event UNIQUE (reservation_id, event_id),  -- BR-R1, D2

    -- ck
    CONSTRAINT ck_reservations_reference_code_format CHECK (reference_code ~ '^EBK-[2-9A-HJKMNP-Z]{6}$'),   -- BR-R3, D8
    CONSTRAINT ck_reservations_cancelled_at_iff_cancelled CHECK ((status = 'cancelled') = (cancelled_at IS NOT NULL)), -- BR-R5

    -- fk
    CONSTRAINT fk_reservations_user FOREIGN KEY (user_id) REFERENCES users (user_id) ON DELETE RESTRICT, -- BR-R1, BR-U6
    CONSTRAINT fk_reservations_event FOREIGN KEY (event_id) REFERENCES events (event_id) ON DELETE RESTRICT -- BR-R1, BR-E8
);

CREATE TABLE tickets (
    ticket_id       BIGINT PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
    reservation_id  BIGINT NOT NULL,                                                        -- BR-R1 (NOT NULL, or the composite FK is skipped)
    ticket_type_id  BIGINT NOT NULL,                                                        -- BR-R1
    event_id        BIGINT NOT NULL,                                                        -- BR-R1, D2 (denormalized; both FKs force it to match)
    code            UUID UNIQUE NOT NULL DEFAULT gen_random_uuid(),                         -- BR-K2, D8 (encoded in the QR)
    unit_price      NUMERIC(12, 2) NOT NULL,                                                -- BR-R7, D3 (price snapshot at reservation time)
    status          ticket_status NOT NULL DEFAULT 'active',                                -- BR-K3
    cancelled_at    TIMESTAMPTZ,                                                            -- BR-K3 (set iff cancelled)

    -- ck
    CONSTRAINT ck_tickets_unit_price_non_negative CHECK (unit_price >= 0),  -- BR-R7, D3
    CONSTRAINT ck_tickets_cancelled_at_iff_cancelled CHECK ((status = 'cancelled') = (cancelled_at IS NOT NULL)),  -- BR-K3

    -- fk
    CONSTRAINT fk_tickets_reservation_event FOREIGN KEY (reservation_id, event_id)
        REFERENCES reservations (reservation_id, event_id) ON DELETE RESTRICT,     -- BR-R1, BR-K4, D2
    CONSTRAINT fk_tickets_ticket_type_event FOREIGN KEY (ticket_type_id, event_id)
        REFERENCES ticket_types (ticket_type_id, event_id) ON DELETE RESTRICT      -- BR-R1, BR-T9, D2
);

/* -------------------------------------------------------------------------- */
/*                                   INDEXES                                  */
/* -------------------------------------------------------------------------- */

-- Oversell check (BR-T3, D4): reserve_tickets() counts active tickets per type while holding
-- the ticket type's row lock, so the count must be fast. Partial = only active rows are indexed;
-- cancelled tickets are never deleted (D9) and would otherwise grow the index forever.
-- Also used by the BR-T4 quantity trigger and "tickets left" on the event page.
CREATE INDEX idx_tickets_active_by_type ON tickets (ticket_type_id) WHERE status = 'active';   -- BR-T3, BR-T4, D4

-- FK columns: Postgres indexes the referenced side (PK/UNIQUE) but not the referencing column.
-- These serve parent -> children lookups and the RESTRICT check when a parent row is deleted.
-- Already covered by a leading column elsewhere, so not repeated here:
--   organizers.user_id (PK) · ticket_types.event_id (uq (event_id, position))
--   tickets.ticket_type_id (partial index above; the FK check only runs on rare ticket type deletes)
--   events.venue_id is left out: no query lists events by venue and venues are rarely deleted.
CREATE INDEX idx_tickets_reservation      ON tickets (reservation_id);      -- a reservation's tickets, cancel all (BR-R5), composite FK
CREATE INDEX idx_reservations_user        ON reservations (user_id);        -- "my reservations / my tickets"
CREATE INDEX idx_reservations_event       ON reservations (event_id);       -- attendee list, event cancel (BR-E9), metrics (BR-M)
CREATE INDEX idx_events_organizer         ON events (organizer_id);         -- organizer dashboard
CREATE INDEX idx_events_category          ON events (category_id);          -- browse by category, RESTRICT on category delete (BR-C3)

/* -------------------------------------------------------------------------- */
/*                           FUNCTIONS AND TRIGGERS                           */
/* -------------------------------------------------------------------------- */

-- Naming: trigger functions are verbs (set_updated_at, reject_change, guard_<table>_<op>);
--         triggers are trg_<table>_<what>. Triggers with the same timing on one table
--         fire alphabetically by name.
-- Errors: RAISE … USING CONSTRAINT = TG_NAME, so tests can assert on the trigger name
--         the same way they assert on ck_/uq_/fk_ names.

-- -----------------------------------------------------------------------------
-- set_updated_at · users, events                                    BR-U7, BR-E12
-- -----------------------------------------------------------------------------
-- A DEFAULT only fills updated_at on INSERT; this keeps it current on every UPDATE.
-- BEFORE so it can change NEW before the row is written (an AFTER trigger can't).
CREATE FUNCTION set_updated_at() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    NEW.updated_at := now();   -- now() = transaction start, so every row in one transaction gets the same time
    RETURN NEW;                -- BEFORE ROW: the returned row is what gets written (NULL would skip it)
END;
$$;

CREATE TRIGGER trg_users_set_updated_at
    BEFORE UPDATE ON users
    FOR EACH ROW
    EXECUTE FUNCTION set_updated_at();                                         -- BR-U7

CREATE TRIGGER trg_events_set_updated_at
    BEFORE UPDATE ON events
    FOR EACH ROW
    EXECUTE FUNCTION set_updated_at();                                         -- BR-E12

-- -----------------------------------------------------------------------------
-- reject_change · columns that never change                     BR-E1, BR-R1, …
-- -----------------------------------------------------------------------------
-- Generic: the trigger passes the column name(s) as an argument, and its WHEN
-- clause decides whether the column really changed. So this function only raises.
CREATE FUNCTION reject_change() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    RAISE EXCEPTION '%.% can''t be changed', TG_TABLE_NAME, TG_ARGV[0]
        USING ERRCODE = 'check_violation', CONSTRAINT = TG_NAME;               -- tests assert on the trigger name
END;
$$;

CREATE TRIGGER trg_events_reject_change_organizer
    BEFORE UPDATE OF organizer_id ON events
    FOR EACH ROW
    WHEN (OLD.organizer_id IS DISTINCT FROM NEW.organizer_id)
    EXECUTE FUNCTION reject_change('organizer_id');                            -- BR-E1

-- Once recorded, the publish and cancel times are history. NULL → value is still
-- allowed: guard_events_status sets them on the transition.
CREATE TRIGGER trg_events_reject_change_timestamps
    BEFORE UPDATE OF published_at, cancelled_at ON events
    FOR EACH ROW
    WHEN (   (OLD.published_at IS NOT NULL AND OLD.published_at IS DISTINCT FROM NEW.published_at)
          OR (OLD.cancelled_at IS NOT NULL AND OLD.cancelled_at IS DISTINCT FROM NEW.cancelled_at))
    EXECUTE FUNCTION reject_change('published_at/cancelled_at');               -- BR-E6, BR-E9

-- -----------------------------------------------------------------------------
-- guard_events_timezone · events                                    BR-E4, D7
-- -----------------------------------------------------------------------------
-- A CHECK can't run a subquery, so the IANA name is checked against
-- pg_timezone_names here. Exact match: 'america/bogota' is rejected, so every
-- row keeps the canonical spelling.
CREATE FUNCTION guard_events_timezone() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_timezone_names WHERE name = NEW.timezone) THEN
        RAISE EXCEPTION 'events.timezone "%" is not a valid IANA time zone', NEW.timezone
            USING ERRCODE = 'check_violation', CONSTRAINT = TG_NAME;
    END IF;
    RETURN NEW;                -- BEFORE ROW: without this the row isn't written
END;
$$;

CREATE TRIGGER trg_events_guard_timezone
    BEFORE INSERT OR UPDATE OF timezone ON events
    FOR EACH ROW
    EXECUTE FUNCTION guard_events_timezone();                                  -- BR-E4, D7

-- -----------------------------------------------------------------------------
-- guard_events_insert · events                                      BR-E5, BR-E6
-- -----------------------------------------------------------------------------
-- Every event starts as a draft. Without this, an INSERT with status = 'published'
-- would skip the publish checks, which only run on UPDATE (guard_events_status).
-- Seeding past/completed events needs triggers off: SET session_replication_role = replica.
CREATE FUNCTION guard_events_insert() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    RAISE EXCEPTION 'events: a new event must be a draft, got %', NEW.status
        USING ERRCODE = 'check_violation', CONSTRAINT = TG_NAME;
END;
$$;

CREATE TRIGGER trg_events_guard_insert
    BEFORE INSERT ON events
    FOR EACH ROW
    WHEN (NEW.status <> 'draft')                                               -- drafts never reach the function
    EXECUTE FUNCTION guard_events_insert();                                    -- BR-E5, BR-E6

-- -----------------------------------------------------------------------------
-- guard_events_status · events                        BR-E5, BR-E6, BR-E9, D5
-- -----------------------------------------------------------------------------
-- Allowed: draft → published, published → cancelled, published → completed.
-- Publishing also checks what a CHECK can't (now(), other tables) and records
-- the time. BEFORE triggers run before CHECKs, so the timestamps set here are
-- what ck_events_published_at_iff_not_draft / ck_events_when_is_cancelled see.
CREATE FUNCTION guard_events_status() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    IF NOT (   (OLD.status = 'draft'     AND NEW.status = 'published')
            OR (OLD.status = 'published' AND NEW.status IN ('cancelled', 'completed'))) THEN
        RAISE EXCEPTION 'events.status can''t go from % to %', OLD.status, NEW.status  -- BR-E5
            USING ERRCODE = 'check_violation', CONSTRAINT = TG_NAME;
    END IF;

    IF NEW.status = 'published' THEN
        IF NEW.starts_at <= now() THEN                                         -- BR-E6
            RAISE EXCEPTION 'events: can''t publish an event that has already started'
                USING ERRCODE = 'check_violation', CONSTRAINT = TG_NAME;
        END IF;
        IF NOT EXISTS (SELECT 1 FROM ticket_types WHERE event_id = NEW.event_id) THEN  -- BR-E6
            RAISE EXCEPTION 'events: can''t publish without at least one ticket type'
                USING ERRCODE = 'check_violation', CONSTRAINT = TG_NAME;
        END IF;
        NEW.published_at := now();                                             -- BR-E6

    ELSIF NEW.status = 'cancelled' THEN
        NEW.cancelled_at := now();                                             -- BR-E9
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_events_status_transition
    BEFORE UPDATE OF status ON events
    FOR EACH ROW
    WHEN (OLD.status IS DISTINCT FROM NEW.status)                              -- same status = no transition
    EXECUTE FUNCTION guard_events_status();                                    -- BR-E5, BR-E6, D5

-- -----------------------------------------------------------------------------
-- guard_events_delete · events                                      BR-E8, D9
-- -----------------------------------------------------------------------------
-- Only a never-published event can be deleted; its ticket types go with it (CASCADE).
-- RESTRICT on reservations alone would still allow deleting a published event
-- that has no reservations yet.
CREATE FUNCTION guard_events_delete() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    IF OLD.published_at IS NOT NULL THEN                                       -- OLD is the row being deleted
        RAISE EXCEPTION 'events: can''t delete an event that was published'
            USING ERRCODE = 'check_violation', CONSTRAINT = TG_NAME;
    END IF;
    RETURN OLD;                -- BEFORE DELETE: OLD lets the delete through, NULL silently skips it
END;
$$;

CREATE TRIGGER trg_events_guard_delete
    BEFORE DELETE ON events
    FOR EACH ROW
    EXECUTE FUNCTION guard_events_delete();                                    -- BR-E8, D9

-- -----------------------------------------------------------------------------
-- cancel_event_reservations · events                        BR-E9, BR-K3, D5
-- -----------------------------------------------------------------------------
-- When an event is cancelled, every confirmed reservation and active ticket is
-- cancelled in the same transaction. Rows stay (BR-K4), so "my tickets" shows them.
-- AFTER: runs only once the status change has passed every BEFORE guard.
-- Lock order reservations → tickets (each UPDATE locks its rows); keep it in every function.
CREATE FUNCTION cancel_event_reservations() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    UPDATE reservations
        SET status = 'cancelled',
            cancelled_at = now()
        WHERE event_id = NEW.event_id AND status = 'confirmed';

    UPDATE tickets                                                             -- via reservations: tickets has no event_id index
        SET status = 'cancelled',
            cancelled_at = now()
        WHERE reservation_id IN (SELECT reservation_id FROM reservations WHERE event_id = NEW.event_id)
            AND status = 'active';

    RETURN NULL;               -- AFTER ROW: return value is ignored
END;
$$;

CREATE TRIGGER trg_events_cancel_cascade
    AFTER UPDATE OF status ON events
    FOR EACH ROW
    WHEN (OLD.status = 'published' AND NEW.status = 'cancelled')
    EXECUTE FUNCTION cancel_event_reservations();                              -- BR-E9, BR-K3, D5

-- -----------------------------------------------------------------------------
-- guard_events_ends_at · events                                      BR-T6, D6
-- -----------------------------------------------------------------------------
-- Moving ends_at earlier can't leave a ticket type selling after the event ends.
-- (NULL sales_end means "until starts_at", which is always before ends_at.)
-- The other side, a ticket type's sales_end vs its event, is on ticket_types.
CREATE FUNCTION guard_events_ends_at() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    IF EXISTS (SELECT 1 FROM ticket_types
                WHERE event_id = NEW.event_id AND sales_end > NEW.ends_at) THEN
        RAISE EXCEPTION 'events: ends_at % is before a ticket type''s sales_end', NEW.ends_at
            USING ERRCODE = 'check_violation', CONSTRAINT = TG_NAME;
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_events_guard_ends_at
    BEFORE UPDATE OF ends_at ON events
    FOR EACH ROW
    WHEN (OLD.ends_at IS DISTINCT FROM NEW.ends_at)
    EXECUTE FUNCTION guard_events_ends_at();                                   -- BR-T6, D6

/* -------------------------------------------------------------------------- */
/*                         FUNCTIONS CALLED BY THE APP                        */
/* -------------------------------------------------------------------------- */

-- -----------------------------------------------------------------------------
-- anonymize_user · users, organizers                                BR-U6, D9
-- -----------------------------------------------------------------------------
-- Account deletion = scrub personal data, never DELETE: the row stays so FKs to
-- reservations and events keep working. Values are chosen to pass every CHECK
-- and unique index. Returns the original email for the confirmation message.
CREATE FUNCTION anonymize_user(p_user_id BIGINT) RETURNS TEXT
LANGUAGE plpgsql AS $$
DECLARE
    v_email TEXT;
BEGIN
    -- Lock the row; a second concurrent call waits, then finds deleted_at set
    SELECT email INTO v_email
      FROM users
     WHERE user_id = p_user_id AND deleted_at IS NULL
       FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'User % not found or already deleted', p_user_id
            USING ERRCODE = 'no_data_found';                                   -- P0002 → app maps to 404
    END IF;

    UPDATE users
       SET email         = 'deleted-' || user_id || '@invalid.local',
           full_name     = 'Deleted User',
           password_hash = '!',
           deleted_at    = now()
     WHERE user_id = p_user_id;

    UPDATE organizers                                                          -- no-op if never an organizer
       SET organizer_name = 'Deleted organizer ' || user_id
     WHERE user_id = p_user_id;

    RETURN v_email;
END;
$$;
