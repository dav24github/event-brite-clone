# Schema checklist

Every rule from [01-business-rules.md](01-business-rules.md), sorted by the table that enforces it and by mechanism. Write `schema.sql` from this list, top to bottom, without going back to the rules. Tick an item when it's in `schema.sql`. Every ticked `ck`, `uq`, `fk` and `trg` item then needs a failing case in `tests/constraint_tests.sql`.

A rule that spans tables is listed under each table it touches.

**Mechanisms:** `type` column type · `nn` NOT NULL · `def` DEFAULT · `ck` CHECK · `uq` UNIQUE / unique index · `fk` foreign key · `idx` plain index · `trg` trigger · `fn` function · `app` application only

## File order

```text
1. Types        CREATE TYPE … AS ENUM
2. Tables       users → organizers → categories → venues → events → ticket_types → reservations → tickets
                (inside each: columns → PK → UNIQUE → CHECK → FK; expression unique indexes right after the table)
3. Indexes      partial and FK indexes
4. Functions    set_updated_at(), timezone check, reference-code generator
5. Triggers     one section per table
6. reserve_tickets()
```

`run_all.sql` already drops and creates the `eventbrite` schema and sets `search_path`, so `schema.sql` doesn't.

## 1. Types

- [x] `event_status` ENUM `draft, published, cancelled, completed` · BR-E5
- [x] `location_type` ENUM `in_person, online` · BR-L1
- [x] `reservation_status` ENUM `confirmed, cancelled` (v1 adds `pending, paid, refunded, expired` with `ALTER TYPE … ADD VALUE`) · BR-R4
- [x] `ticket_status` ENUM `active, cancelled` (`used` comes with check-in) · BR-K3, BR-K5

## 2. Tables

### users

- [x] `email` nn + uq · BR-U1
- [x] `email = lower(email)` ck · BR-U1
- [x] `email` contains `@` ck · BR-U1
- [x] `password_hash` nn, not blank ck · BR-U2
- [x] `full_name` varchar(100) nn, not blank ck · BR-U3
- [x] `created_at`, `updated_at` nn def `now()` · BR-U7
- [x] `updated_at` refreshed on update · trg `set_updated_at()` · BR-U7
- [x] `deleted_at` nullable · D9
- [x] anonymizing keeps every CHECK valid (e.g. email `deleted-<id>@invalid.local`) · app/fn · BR-U6, D9
- [x] no hard delete of a user with history · covered by `RESTRICT` FKs below · BR-U6

### organizers

- [x] `user_id` PK, not generated · D1
- [x] `user_id` fk → `users` RESTRICT · BR-U4, BR-U6, D1
- [x] `organizer_name` varchar(80) nn, ≥ 2 chars ck · BR-U4
- [x] `lower(organizer_name)` uq index · BR-U4
- [x] `enabled_at` nn def `now()` · D1

### categories

- [x] `name` nn uq, not blank ck · BR-C1
- [x] `slug` nn uq, `^[a-z0-9]+(-[a-z0-9]+)*$` ck · BR-C1
- [x] can't delete if used · fk RESTRICT on `events.category_id` · BR-C3
- [ ] reference rows (10 categories) · `seed.sql` · BR-C1

### venues

- [x] `name` varchar(120), `address`, `city` nn, not blank ck · BR-L2
- [x] `country` char(2), `^[A-Z]{2}$` ck · BR-L2
- [x] `postal_code` nullable · BR-L2
- [x] `latitude` −90…90, `longitude` −180…180 ck · BR-L2
- [x] both coordinates or neither ck · BR-L2
- [x] several events per venue · `events.venue_id` fk, no uq · BR-L5

### events

- [x] `organizer_id` nn fk → `organizers` RESTRICT · BR-E1, BR-U6
- [x] `organizer_id` immutable · trg BEFORE UPDATE · BR-E1
- [x] `title` varchar(120), ≥ 3 chars ck · BR-E2
- [x] `description` ≤ 10 000 ck · BR-E2
- [x] `ends_at > starts_at` ck · BR-E3
- [x] duration ≤ 14 days ck · BR-E3
- [x] `timezone` text nn · BR-E4
- [x] `timezone` exists in `pg_timezone_names` · trg (a CHECK can't query a view) · BR-E4, D7
- [ ] DST-ambiguous wall-clock input rejected · app · BR-E4, D7
- [x] `status` event_status nn def `draft` · BR-E5
- [x] only `draft→published`, `published→cancelled`, `published→completed` · trg BEFORE UPDATE · BR-E5, D5
- [x] description, category and complete location required unless draft ck · BR-E6, BR-C2, BR-L4
- [x] on publish: `starts_at > now()` and ≥ 1 ticket type · trg BEFORE UPDATE · BR-E6, D5
- [x] `published_at` set iff not draft ck · BR-E6
- [ ] draft only visible to its organizer; browse = published + upcoming · app / queries · BR-E7
- [x] delete only while `published_at IS NULL` · trg BEFORE DELETE · BR-E8, D9
- [x] `cancelled_at` set iff cancelled ck · BR-E9
- [x] `cancellation_reason` varchar(500) · BR-E9
- [x] on `published→cancelled`: cancel all active tickets and their reservations · trg AFTER UPDATE · BR-E9, BR-K3, D5
- [ ] `completed` = `ends_at < now` in queries; job sets status later · queries · BR-E10
- [x] `cover_url` https, ≤ 2048 ck · BR-E11
- [x] `created_at`, `updated_at` nn def `now()` · BR-E12
- [x] `updated_at` refreshed on update · trg `set_updated_at()` · BR-E12
- [x] `location_type` enum, nullable in draft · BR-L1, BR-L4
- [x] `venue_id` only when in person; `meeting_url` only when online ck · BR-L1
- [x] `venue_id` fk → `venues` RESTRICT · BR-L2, BR-R7
- [x] `meeting_url` https ck · BR-L3
- [ ] `meeting_url` shown only to active ticket holders · app · BR-L3
- [x] `category_id` fk → `categories` RESTRICT · BR-C3
- [x] `currency` char(3) nn, `^[A-Z]{3}$` ck · BR-T5, D3
- [x] `sales_end <= ends_at` still holds when `ends_at` changes · trg · BR-T6, D6

### ticket_types

- [x] `event_id` nn fk → `events` CASCADE · BR-T1, BR-E8, D9
- [x] uq `(ticket_type_id, event_id)` (target of the tickets composite FK) · BR-R1, D2
- [ ] `event_id` immutable · trg · BR-R1 (composite FK relies on it)
- [x] `name` varchar(60), not blank ck · BR-T1
- [x] uq index `(event_id, lower(name))` · BR-T1
- [x] `description` varchar(500) nullable · BR-T1
- [x] `quantity` int nn, 1–100 000 ck · BR-T2
- [ ] lowering `quantity` below active tickets rejected · trg BEFORE UPDATE (row lock + count) · BR-T4, D4
- [x] `price` numeric(12,2) nn def 0, `>= 0` ck · BR-T5, D3
- [x] `price = 0` ck (v0 only, dropped in v1) · BR-T5
- [x] `sales_start`, `sales_end` nullable; `sales_end > sales_start` ck · BR-T6
- [ ] `sales_end <= events.ends_at` · trg · BR-T6, D6
- [ ] defaults resolved at read time: `COALESCE(sales_start, published_at)`, `COALESCE(sales_end, starts_at)` · queries/fn · BR-T6, D6
- [x] `max_per_checkout` int nn def 10, 1–50 ck · BR-T7
- [x] `position` int nn, uq `(event_id, position)` · BR-T8
- [x] `off_sale_at` nullable · BR-T9
- [ ] delete only with no tickets · fk RESTRICT on `tickets.ticket_type_id` · BR-T9

### reservations

- [x] `user_id` nn fk → `users` RESTRICT · BR-R1, BR-U6
- [x] `event_id` nn fk → `events` RESTRICT · BR-R1, BR-E8
- [x] uq `(reservation_id, event_id)` (target of the tickets composite FK) · BR-R1, D2
- [ ] `event_id` immutable · trg · BR-R1
- [x] `created_at` nn def `now()` · BR-R1
- [x] `reference_code` nn uq, `^EBK-[2-9A-HJKMNP-Z]{6}$` ck · BR-R3, D8
- [ ] `reference_code` generated randomly, retried on collision · fn · BR-R3, D8
- [x] `status` reservation_status nn def `confirmed` · BR-R4
- [x] `cancelled_at` set iff cancelled ck · BR-R5
- [ ] cancel own reservation only before event start; cancels all its tickets · fn · BR-R5
- [ ] never deleted · trg BEFORE DELETE raises · BR-K4, D9

### tickets

- [x] `reservation_id`, `ticket_type_id`, `event_id` all nn (a NULL would skip the composite FK) · BR-R1
- [x] fk `(reservation_id, event_id)` → `reservations` RESTRICT · BR-R1, BR-K4, D2
- [x] fk `(ticket_type_id, event_id)` → `ticket_types` RESTRICT · BR-R1, BR-T9, D2
- [x] `code` uuid nn uq def `gen_random_uuid()` · BR-K2, D8
- [x] `unit_price` numeric(12,2) nn, `>= 0` ck · BR-R7, D3
- [x] `status` ticket_status nn def `active` · BR-K3
- [x] `cancelled_at` set iff cancelled ck · BR-K3
- [ ] cancelled never becomes active again · trg BEFORE UPDATE · BR-K3
- [ ] ticket status matches reservation status (v0) · test · 02-design denormalizations
- [ ] never deleted · trg BEFORE DELETE raises · BR-K4, D9
- [x] owner = reservation's user (no own user column) · design · BR-K5

## 3. Indexes

- [x] partial `tickets (ticket_type_id) WHERE status = 'active'` · BR-T3, D4
- [x] `tickets (reservation_id)`, `reservations (user_id)`, `reservations (event_id)`, `events (organizer_id)`, `events (category_id)` (FK columns aren't indexed automatically) · performance

## 4–6. Functions and triggers

- [ ] `set_updated_at()` on `users`, `events` · BR-U7, BR-E12
- [ ] `reserve_tickets(user_id, event_id, {ticket_type_id: qty})` in one transaction · BR-R6
  - [ ] event `published` and `starts_at > now()` · BR-R2
  - [ ] each type: inside sales window, `off_sale_at` null or in the future · BR-R2, BR-T6
  - [ ] each type belongs to the event · BR-R1
  - [ ] 1 ≤ qty ≤ `max_per_checkout` · BR-T7
  - [ ] lock ticket types `FOR UPDATE` in id order, count active, reject if over quantity · BR-T3, D4
  - [ ] copy `price` to `unit_price` · BR-R7
  - [ ] any failure rolls back everything · BR-R6

## 7. Coverage check

- [ ] every BR-ID in `01-business-rules.md` appears in `schema.sql`, `tests/constraint_tests.sql`, or as `app` above
- [ ] BR-M1–M6 are query definitions only; they belong in `queries/`
