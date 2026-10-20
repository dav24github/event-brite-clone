-- =============================================================================
-- schema.sql · types and tables
-- Every constraint is named and tagged with the rule ID it enforces, e.g.
--   CONSTRAINT ck_events_ends_after_start CHECK (ends_at > starts_at)  -- BR-E?
-- Rules: docs/01-business-rules.md · Checklist: docs/03-schema-checklist.md
-- Order: types → tables (FK order) → functions → triggers
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Types
-- -----------------------------------------------------------------------------

CREATE TYPE event_status  AS ENUM ('draft', 'published', 'cancelled', 'completed');  -- BR-E5
CREATE TYPE location_type AS ENUM ('in_person', 'online');                           -- BR-L1
CREATE TYPE reservation_status AS ENUM ('confirmed', 'cancelled');                 -- BR-R4 (v1 adds pending, paid, refunded, expired)
CREATE TYPE ticket_status      AS ENUM ('active', 'cancelled');                    -- BR-K3 (check-in adds used)

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