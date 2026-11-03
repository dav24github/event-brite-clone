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
-- reject_delete · rows that are never deleted                       BR-K4, D9
-- -----------------------------------------------------------------------------
-- Generic: attendees keep their history and organizers their reports, so
-- reservations and tickets are cancelled, never deleted. Only raises.
CREATE FUNCTION reject_delete() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    RAISE EXCEPTION '% rows are never deleted', TG_TABLE_NAME
        USING ERRCODE = 'restrict_violation', CONSTRAINT = TG_NAME;            -- same SQLSTATE as an FK RESTRICT
END;
$$;

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

-- The tickets composite FK (ticket_type_id, event_id) relies on this never changing.
CREATE TRIGGER trg_ticket_types_reject_change_event
    BEFORE UPDATE OF event_id ON ticket_types
    FOR EACH ROW
    WHEN (OLD.event_id IS DISTINCT FROM NEW.event_id)
    EXECUTE FUNCTION reject_change('event_id');                                -- BR-R1, D2

-- A reservation never moves to another event or user (no ticket transfers in v0).
-- The tickets composite FK (reservation_id, event_id) relies on event_id.
CREATE TRIGGER trg_reservations_reject_change_keys
    BEFORE UPDATE OF event_id, user_id ON reservations
    FOR EACH ROW
    WHEN (   OLD.event_id IS DISTINCT FROM NEW.event_id
          OR OLD.user_id  IS DISTINCT FROM NEW.user_id)
    EXECUTE FUNCTION reject_change('event_id/user_id');                        -- BR-R1, BR-K5, D2

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

-- -----------------------------------------------------------------------------
-- guard_ticket_types_lowering_quantity · ticket_types                BR-T4, D4
-- -----------------------------------------------------------------------------
-- Raising is always allowed; lowering can't go below the active tickets.
-- No extra lock: this UPDATE already holds the ticket type's row lock, the same
-- lock reserve_tickets() takes before counting, so the two take turns.
CREATE FUNCTION guard_ticket_types_lowering_quantity() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE v_active_tickets BIGINT;
BEGIN
    SELECT count(*) INTO v_active_tickets 
        FROM tickets
        WHERE ticket_type_id = NEW.ticket_type_id AND status = 'active';
    
    IF v_active_tickets > NEW.quantity THEN
        RAISE EXCEPTION 'ticket_types: quantity % is below the % active tickets', NEW.quantity, v_active_tickets
            USING ERRCODE = 'check_violation', CONSTRAINT = TG_NAME;
    END IF;

    RETURN NEW;    
END;
$$;

CREATE TRIGGER trg_ticket_types_guard_quantity
    BEFORE UPDATE OF quantity ON ticket_types
    FOR EACH ROW
    WHEN (NEW.quantity < OLD.quantity)                                         -- raising is always allowed
    EXECUTE FUNCTION guard_ticket_types_lowering_quantity();                   -- BR-T4, D4

-- -----------------------------------------------------------------------------
-- guard_ticket_types_sales_end · ticket_types                        BR-T6, D6
-- -----------------------------------------------------------------------------
-- A ticket type can't sell after its event ends. The other direction (the event's
-- ends_at moving earlier) is guard_events_ends_at. FOR SHARE makes the two take
-- turns on the event row, so neither checks a value the other is changing.
CREATE FUNCTION guard_ticket_types_sales_end() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
    v_ends_at TIMESTAMPTZ;
BEGIN
    SELECT ends_at INTO v_ends_at
      FROM events
     WHERE event_id = NEW.event_id
       FOR SHARE;                                                              -- waits for / blocks an ends_at change

    IF NEW.sales_end > v_ends_at THEN
        RAISE EXCEPTION 'ticket_types: sales_end % is after the event''s ends_at %', NEW.sales_end, v_ends_at
            USING ERRCODE = 'check_violation', CONSTRAINT = TG_NAME;
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_ticket_types_guard_sales_end
    BEFORE INSERT OR UPDATE OF sales_end ON ticket_types
    FOR EACH ROW
    WHEN (NEW.sales_end IS NOT NULL)                                           -- NULL = until starts_at, always valid
    EXECUTE FUNCTION guard_ticket_types_sales_end();                           -- BR-T6, D6

-- -----------------------------------------------------------------------------
-- guard_ticket_types_delete · ticket_types                                 BR-E6
-- -----------------------------------------------------------------------------
-- A published (or cancelled/completed) event keeps at least one ticket type, so
-- the publish check can't be undone afterwards. Drafts are free to delete them.
-- When a draft event is deleted, CASCADE runs this after the event row is gone:
-- no event found → allowed.
-- FOR NO KEY UPDATE on the event: two deletes on the same event take turns, so they
-- can't each see the other's ticket type and both delete. (It doesn't block inserts,
-- whose FK check only needs FOR KEY SHARE.)
CREATE FUNCTION guard_ticket_types_delete() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
    v_status event_status;
BEGIN
    SELECT status INTO v_status
      FROM events
     WHERE event_id = OLD.event_id
       FOR NO KEY UPDATE;

    IF v_status <> 'draft'                                                     -- NULL (event gone) → skipped
       AND NOT EXISTS (SELECT 1 FROM ticket_types
                        WHERE event_id = OLD.event_id
                          AND ticket_type_id <> OLD.ticket_type_id) THEN
        RAISE EXCEPTION 'ticket_types: can''t delete the last ticket type of a % event', v_status
            USING ERRCODE = 'check_violation', CONSTRAINT = TG_NAME;
    END IF;

    RETURN OLD;                -- BEFORE DELETE: OLD lets the delete through
END;
$$;

CREATE TRIGGER trg_ticket_types_guard_delete
    BEFORE DELETE ON ticket_types
    FOR EACH ROW
    EXECUTE FUNCTION guard_ticket_types_delete();                              -- BR-E6

-- -----------------------------------------------------------------------------
-- reservations · no reactivation, no delete                  BR-R5, BR-K4, D9
-- -----------------------------------------------------------------------------
-- A cancelled reservation stays cancelled; its tickets went back to availability.
CREATE TRIGGER trg_reservations_no_reactivate
    BEFORE UPDATE OF status ON reservations
    FOR EACH ROW
    WHEN (OLD.status = 'cancelled' AND NEW.status <> 'cancelled')
    EXECUTE FUNCTION reject_change('status');                                  -- BR-R5

-- RESTRICT from tickets already blocks most deletes; this also covers a reservation
-- with no tickets, and gives a clear message.
CREATE TRIGGER trg_reservations_no_delete
    BEFORE DELETE ON reservations
    FOR EACH ROW
    EXECUTE FUNCTION reject_delete();                                          -- BR-K4, D9

-- -----------------------------------------------------------------------------
-- guard_tickets_status · tickets                                           BR-K3
-- -----------------------------------------------------------------------------
-- Forbidden: cancelled → active. With check-in (used), also forbid moves out of
-- cancelled and used, or switch to listing the allowed moves like guard_events_status.
CREATE FUNCTION guard_tickets_status() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    IF (OLD.status = 'cancelled' AND NEW.status = 'active') THEN
        RAISE EXCEPTION 'tickets.status can''t go from % to %', OLD.status, NEW.status   -- BR-K3
            USING ERRCODE = 'check_violation', CONSTRAINT = TG_NAME;
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_tickets_status_transition
    BEFORE UPDATE OF status ON tickets
    FOR EACH ROW
    WHEN (OLD.status IS DISTINCT FROM NEW.status)
    EXECUTE FUNCTION guard_tickets_status();                                   -- BR-K3

-- -----------------------------------------------------------------------------
-- tickets · fixed columns, no delete                    BR-K2, BR-K4, BR-R7, D2
-- -----------------------------------------------------------------------------
-- Only status and cancelled_at ever change. code is the QR credential (BR-K2),
-- unit_price the price snapshot (BR-R7), and the ids hold the composite FKs (D2).
CREATE TRIGGER trg_tickets_reject_change_keys
    BEFORE UPDATE OF code, unit_price, reservation_id, ticket_type_id, event_id ON tickets
    FOR EACH ROW
    WHEN (   OLD.code           IS DISTINCT FROM NEW.code
          OR OLD.unit_price     IS DISTINCT FROM NEW.unit_price
          OR OLD.reservation_id IS DISTINCT FROM NEW.reservation_id
          OR OLD.ticket_type_id IS DISTINCT FROM NEW.ticket_type_id
          OR OLD.event_id       IS DISTINCT FROM NEW.event_id)
    EXECUTE FUNCTION reject_change('code/unit_price/reservation_id/ticket_type_id/event_id');  -- BR-K2, BR-R7, D2

CREATE TRIGGER trg_tickets_no_delete
    BEFORE DELETE ON tickets
    FOR EACH ROW
    EXECUTE FUNCTION reject_delete();                                          -- BR-K4, D9

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

-- -----------------------------------------------------------------------------
-- gen_reference_code · reservations                                 BR-R3, D8
-- -----------------------------------------------------------------------------
-- 'EBK-' + 6 random characters. The alphabet leaves out 0/O and 1/I/L so codes
-- can be read out to support. 31^6 ≈ 887 million codes; random, so they don't
-- reveal how many reservations exist. Not a credential (D8), so random() is enough.
-- Uniqueness isn't checked here: reserve_tickets() retries on unique_violation.
CREATE FUNCTION gen_reference_code() RETURNS TEXT
LANGUAGE plpgsql AS $$
DECLARE
    v_alphabet CONSTANT TEXT := '23456789ABCDEFGHJKMNPQRSTUVWXYZ';              -- same set as ck_reservations_reference_code_format
    v_code     TEXT := 'EBK-';
BEGIN
    FOR i IN 1..6 LOOP
        v_code := v_code || substr(v_alphabet, 1 + floor(random() * length(v_alphabet))::int, 1);
    END LOOP;
    RETURN v_code;
END;
$$;

-- -----------------------------------------------------------------------------
-- cancel_reservation · reservations, tickets                           BR-R5
-- -----------------------------------------------------------------------------
-- An attendee cancels their own reservation until the event starts; all its
-- tickets are cancelled and return to availability. Lock order: reservation,
-- then tickets (same as trg_events_cancel_cascade). Checks run after the lock.
CREATE FUNCTION cancel_reservation(p_user_id BIGINT, p_reservation_id BIGINT) RETURNS void
LANGUAGE plpgsql AS $$
DECLARE
    v_status reservation_status;
    v_starts_at TIMESTAMPTZ;
BEGIN
    -- lock the row (reservation)
    SELECT r.status, e.starts_at INTO v_status, v_starts_at
        FROM reservations r
        JOIN events e USING (event_id)
    WHERE r.reservation_id = p_reservation_id
        AND r.user_id = p_user_id
        FOR UPDATE OF r;

    -- IF NOT FOUND
    IF NOT FOUND THEN
        RAISE EXCEPTION 'reservation % not found for user %', p_reservation_id, p_user_id
            USING ERRCODE = 'no_data_found';      
    END IF;

    -- IF already cancelled
    IF (v_status <> 'confirmed') THEN
        RAISE EXCEPTION 'Reservation: % is already %.', p_reservation_id, v_status
            USING ERRCODE = 'check_violation';
    END IF;

    -- IF event has started
    IF v_starts_at <= now() THEN
        RAISE EXCEPTION 'Reservation: % can''t be cancelled, the event has started.', p_reservation_id
            USING ERRCODE = 'check_violation';
    END IF;
    
    -- cancel reservation
    UPDATE reservations
        SET status = 'cancelled', cancelled_at = now()
    WHERE reservation_id = p_reservation_id;

    -- cancell all its ticket
    UPDATE tickets
        SET status = 'cancelled', cancelled_at = now()
    WHERE reservation_id = p_reservation_id
        AND status = 'active';
END;
$$;

-- -----------------------------------------------------------------------------
-- reserve_tickets · reservations, tickets
--     BR-R1, BR-R2, BR-R3, BR-R6, BR-R7, BR-T3, BR-T6, BR-T7, BR-E9, D4, D8
-- -----------------------------------------------------------------------------
-- One checkout: p_items maps ticket_type_id → quantity, e.g. '{"12": 2, "13": 1}'.
-- Creates one reservation and its tickets, or nothing (any RAISE rolls back the
-- whole call, BR-R6). Returns the reference code.
-- Locks, in order: event FOR SHARE (a concurrent cancel waits for this checkout,
-- or this checkout sees 'cancelled') → each ticket type FOR UPDATE in id order
-- (one checkout counts at a time, no deadlocks) → inserts.
CREATE FUNCTION reserve_tickets(p_user_id BIGINT, p_event_id BIGINT, p_items JSONB) RETURNS TEXT
LANGUAGE plpgsql AS $$
DECLARE
    v_item RECORD;
    v_tt RECORD;
    v_reservation_id BIGINT;
    v_reference_code TEXT;
    v_status event_status;
    v_starts_at TIMESTAMPTZ;
    v_published_at TIMESTAMPTZ;
    v_active INT;
BEGIN
    -- 1. Checks that don't need a lock
    IF p_items IS NULL OR p_items = '{}'::jsonb THEN
        RAISE EXCEPTION 'No tickets specified for reservation'
            USING ERRCODE = 'check_violation';
    END IF; -- LOOP will not run if no items, so the reservation would be empty      -- BR-T7

    -- Anonymize user check: deleted users can't make reservations
    IF EXISTS (SELECT 1 FROM users WHERE user_id = p_user_id AND deleted_at IS NOT NULL) THEN
        RAISE EXCEPTION 'User % is deleted and cannot make reservations', p_user_id
            USING ERRCODE = 'check_violation';
    END IF;

    -- 2. Lock the event, then check it
    SELECT status, starts_at, published_at INTO v_status, v_starts_at, v_published_at
        FROM events
        WHERE event_id = p_event_id
        FOR SHARE; -- lock the event row to prevent changes while reserving (e.g. cancellation)

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Event % not found', p_event_id
            USING ERRCODE = 'no_data_found';
    END IF;

    -- Verify is event is published & not started
    IF v_status <> 'published' OR v_starts_at <= now() THEN                       -- BR-R2
        RAISE EXCEPTION 'Event % is not available for reservation', p_event_id
            USING ERRCODE = 'check_violation';
    END IF;

    -- 3. Insert the reservation; retry if the random code is already taken     -- BR-R3, D8
    LOOP
        BEGIN
            INSERT INTO reservations (user_id, event_id, reference_code)
                VALUES (p_user_id, p_event_id, gen_reference_code())
            RETURNING reservation_id, reference_code INTO v_reservation_id, v_reference_code;
            EXIT;                                                              -- inserted, leave the loop
        EXCEPTION WHEN unique_violation THEN
            -- code collision (very rare): loop and try a new one
        END;
    END LOOP;

    -- 4. Each ticket type: lock, check, count, insert
    FOR v_item IN
        SELECT key::BIGINT AS ticket_type_id, value::INT AS quantity
        FROM jsonb_each(p_items)
        ORDER BY 1 -- Refers to the 1st column: ticket_type_id
    LOOP
        -- Data: v_item.ticket_type_id, v_item.quantity
        SELECT price, quantity, off_sale_at, max_per_checkout, sales_start, sales_end 
            INTO v_tt
            FROM ticket_types
            WHERE ticket_type_id = v_item.ticket_type_id AND event_id = p_event_id
            FOR UPDATE; --  lock the ticket type row to prevent overselling while reserving

        IF NOT FOUND THEN                                                      -- BR-R1: never another event's type
            RAISE EXCEPTION 'Ticket type % does not exist for event %', v_item.ticket_type_id, p_event_id
                USING ERRCODE = 'no_data_found';
        END IF;

        -- Verify if reservation is within the sales period: open from start (inclusive)  -- BR-R2, BR-T6
        -- to end (exclusive); NULL start/end = published_at/starts_at; NULL off_sale_at = on sale
        IF COALESCE(v_tt.sales_start, v_published_at) > now() OR COALESCE(v_tt.sales_end, v_starts_at) <= now() OR v_tt.off_sale_at <= now() THEN
            RAISE EXCEPTION 'Ticket type % is not available for reservation', v_item.ticket_type_id
                USING ERRCODE = 'check_violation';
        END IF;

        -- Verify if quantity is within the allowed range
        IF v_item.quantity < 1 OR v_item.quantity > v_tt.max_per_checkout THEN       -- BR-T7
            RAISE EXCEPTION 'Quantity for ticket type % must be at least 1 and at most %', v_item.ticket_type_id, v_tt.max_per_checkout
                USING ERRCODE = 'check_violation';
        END IF;


        SELECT count(*) INTO v_active
            FROM tickets
            WHERE ticket_type_id = v_item.ticket_type_id AND status = 'active';

        -- Check the available tickets for this ticket type
        IF v_active + v_item.quantity > v_tt.quantity THEN                     -- BR-T3, D4: counted under the lock
            RAISE EXCEPTION 'Not enough tickets available for ticket type %', v_item.ticket_type_id
                USING ERRCODE = 'check_violation';
        END IF;
        
        -- create all tickets for this ticket type
        INSERT INTO tickets (reservation_id, event_id, ticket_type_id, unit_price)
            SELECT v_reservation_id, p_event_id, v_item.ticket_type_id, v_tt.price  -- price snapshot (BR-R7)
            FROM generate_series(1, v_item.quantity);
    END LOOP;

    RETURN v_reference_code;
END;
$$;