# Business Rules

How the Eventbrite clone's database is supposed to behave. The schema, seed data, tests and queries all follow from this document.

Every rule has an ID (`BR-<area><n>`, e.g. `BR-E1`, `BR-T1`). The ID is cited in `db/schema.sql` next to the constraint that enforces it, in `db/tests/constraint_tests.sql`, and in the query headers.

- **DBMS:** PostgreSQL 16+
- **Schema:** `eventbrite`
- **Reference date for analytics:** `2026-11-01 00:00 UTC`. The seed data is static, so "now" is fixed at this instant and query results can be reproduced.
- **Scope:** MVP v0, free events. See [../../docs/scope.md](../../docs/scope.md). Rules marked **(v1-ready)** describe things v0 doesn't use yet but the design must not block.

> **Who wrote what:** the rules (sections 1–3) are the product spec, given. The decisions in section 4 are design, written by me.

---

## 1. Domain overview

A marketplace for events. **Organizers** create **events**, each with one or more **ticket types** (General, VIP…) that have a limited quantity. They publish the event once it's ready. **Attendees** browse published events by **category** or search, and **reserve** tickets in a single checkout. Each reserved **ticket** admits one person and carries a unique code shown as a QR code. Organizers see how many tickets each event has reserved. In v0 every ticket is free.

| Area         | Business concepts                                                   |
| ------------ | ------------------------------------------------------------------- |
| People       | user account, attendee, organizer (and the organizer's public name) |
| Catalog      | event, category, location (in-person venue or online link)          |
| Inventory    | ticket type (quantity, price, sales window, per-checkout limit)     |
| Reservations | reservation (one checkout), ticket (one admission)                  |

### Glossary

| Term              | Meaning                                                                                                                                                  |
| ----------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Reservation**   | One checkout by one attendee for one event. It can include several ticket types and several tickets.                                                     |
| **Ticket**        | One admission for one person, of one ticket type. It's what the QR code represents.                                                                      |
| **Active ticket** | A ticket that hasn't been cancelled. Only active tickets count against a ticket type's quantity.                                                         |
| **On sale**       | A ticket type is on sale when its event is published, the current time is inside its sales window, it hasn't been taken off sale, and it isn't sold out. |
| **Sold out**      | A ticket type's active tickets equal its quantity.                                                                                                       |
| **Sell-through**  | Active tickets ÷ total quantity, for a ticket type or summed for an event.                                                                               |
| **Upcoming**      | An event whose start time is after "now" (the reference date in analytics).                                                                              |

---

## 2. Actors

| Actor                                       | Can do                                                                                                                                                 |
| ------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------ |
| **Visitor** (not signed in)                 | Browse and search **published** events. See ticket types, prices and availability.                                                                     |
| **Attendee** (any signed-in user)           | Everything a visitor can, plus reserve tickets, see "my tickets", and cancel their own reservation.                                                    |
| **Organizer** (a user enabled as organizer) | Create, edit, publish and cancel **their own** events and ticket types. See reservation counts for their own events. They can also act as an attendee. |
| **Platform admin**                          | Manages the category list. There's no UI in v0; categories come from seed data.                                                                        |

---

## 3. Rules

### 3.1 Users & organizers · `BR-U`

| ID        | Rule                                                                                                                                                                                                                                                                                                                                      |
| --------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **BR-U1** | Every user has an email that is required and unique, compared case-insensitively (`Ana@x.com` and `ana@x.com` are the same account). It is stored in lowercase and must contain `@`.                                                                                                                                                      |
| **BR-U2** | The database stores only a password **hash**, never the password. The hash is required.                                                                                                                                                                                                                                                   |
| **BR-U3** | Every user has a required full name, 1–100 characters, not blank.                                                                                                                                                                                                                                                                         |
| **BR-U4** | Any user can be an attendee. To create events, a user must first be **enabled as an organizer**, which requires a **public organizer name** (2–80 characters, e.g. "Bogotá Jazz Collective"). That name is shown on their events instead of their personal name. Organizer names are unique on the platform, compared case-insensitively. |
| **BR-U5** | **One person can be both organizer and attendee**, with one account and one email. An organizer may reserve tickets to other organizers' events and to their own (e.g. complimentary tickets).                                                                                                                                            |
| **BR-U6** | Deleting an account must never make an issued ticket, a reservation, or a published, cancelled or completed event disappear, because attendees and organizers rely on that history.                                                                                                                                                       |
| **BR-U7** | The system records when each account was created and when it was last updated.                                                                                                                                                                                                                                                            |

### 3.2 Events · `BR-E`

| ID         | Rule                                                                                                                                                                                                                                                                                                                                                   |
| ---------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| **BR-E1**  | Every event belongs to exactly one organizer, and the organizer can't be changed.                                                                                                                                                                                                                                                                      |
| **BR-E2**  | Every event has a title of 3–120 characters. The description is optional in a draft and required to publish (up to 10 000 characters).                                                                                                                                                                                                                 |
| **BR-E3**  | Every event has a start and an end. The end is strictly after the start, and an event lasts at most **14 days**.                                                                                                                                                                                                                                       |
| **BR-E4**  | Every event happens in a **time zone**, a valid IANA name such as `America/Bogota` or `Europe/Madrid`. Attendees always see the event's times in the event's local time, wherever they are. Start and end must each identify one unambiguous instant.                                                                                                  |
| **BR-E5**  | An event's status is one of `draft`, `published`, `cancelled` or `completed`. The only allowed transitions are `draft → published`, `published → cancelled` and `published → completed`. `cancelled` and `completed` are final. An event can't go back to draft.                                                                                       |
| **BR-E6**  | **To publish**, an event needs a description, a category, a location (BR-L), a start time in the future, and at least one ticket type. The publish time is recorded. A published event always has a publish time, and a draft never does.                                                                                                              |
| **BR-E7**  | Only `published`, `cancelled` and `completed` events are visible to the public. Drafts are visible only to their organizer. Browse and search show only **published, upcoming** events.                                                                                                                                                                |
| **BR-E8**  | A **draft** can be deleted outright. An event that was ever published can't be deleted. It can only be cancelled.                                                                                                                                                                                                                                      |
| **BR-E9**  | **Cancelling** an event records when it happened and an optional reason (up to 500 characters). After that, no new reservations are allowed, and every ticket for the event is cancelled (BR-K3). Attendees still see those tickets in "my tickets", marked as cancelled. A cancelled event always has a cancellation time, and other events never do. |
| **BR-E10** | An event becomes `completed` after its end time passes. (In v0 a job or query marks it. For analytics, "completed" means `end < now`.)                                                                                                                                                                                                                 |
| **BR-E11** | The cover image is an optional `https://` URL, up to 2 048 characters. Uploads are out of scope in v0.                                                                                                                                                                                                                                                 |
| **BR-E12** | The system records when each event was created and last updated.                                                                                                                                                                                                                                                                                       |

### 3.3 Location · `BR-L`

| ID        | Rule                                                                                                                                                                                                                                                                                                                     |
| --------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| **BR-L1** | Every event is either **in person** or **online**, never both. Hybrid events are out of scope.                                                                                                                                                                                                                           |
| **BR-L2** | An in-person event has a venue name (up to 120 characters), an address line, a city, and a country (an uppercase ISO 3166-1 alpha-2 code such as `CO` or `ES`). Postal code, latitude and longitude are optional. If one coordinate is given, both must be: latitude between −90 and 90, longitude between −180 and 180. |
| **BR-L3** | An online event has an `https://` meeting URL. The app shows it only to holders of active tickets.                                                                                                                                                                                                                       |
| **BR-L4** | A draft may have no location yet. A published event must satisfy BR-L1 to BR-L3.                                                                                                                                                                                                                                         |
| **BR-L5** | Several events may take place at the same venue. Whether a venue is stored once and reused, or copied onto each event, is a design choice. Reusing venues isn't a v0 feature.                                                                                                                                            |

### 3.4 Categories · `BR-C`

| ID        | Rule                                                                                                                                                   |
| --------- | ------------------------------------------------------------------------------------------------------------------------------------------------------ |
| **BR-C1** | Categories are a fixed list managed by the platform. Each has a unique name and a unique URL slug (lowercase `a-z`, `0-9` and `-`, e.g. `food-drink`). |
| **BR-C2** | A published event has exactly one category. A draft may have none yet.                                                                                 |
| **BR-C3** | A category that any event uses can't be deleted.                                                                                                       |

**Categories (reference data)**

| slug         | name              |
| ------------ | ----------------- |
| `music`      | Music             |
| `tech`       | Technology        |
| `business`   | Business          |
| `food-drink` | Food & Drink      |
| `arts`       | Arts & Culture    |
| `sports`     | Sports & Fitness  |
| `health`     | Health & Wellness |
| `education`  | Education         |
| `community`  | Community         |
| `other`      | Other             |

### 3.5 Ticket types · `BR-T`

| ID        | Rule                                                                                                                                                                                                                                                        |
| --------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **BR-T1** | A ticket type belongs to exactly one event. Its name is 1–60 characters, and names are unique within an event, compared case-insensitively. An optional description can be up to 500 characters.                                                            |
| **BR-T2** | **Quantity:** each ticket type has a total quantity between 1 and 100 000.                                                                                                                                                                                  |
| **BR-T3** | **Never oversell.** At no moment can a ticket type have more active tickets than its quantity, even when two attendees check out the last ticket at the same instant.                                                                                       |
| **BR-T4** | The quantity can be raised at any time. It can be lowered, but never below the number of active tickets.                                                                                                                                                    |
| **BR-T5** | **Price:** in v0 every ticket type is free (price 0). **(v1-ready)** The price can't be negative, it's exact (no rounding errors), and it comes with an ISO 4217 currency code (`USD`, `EUR`, `COP`…). All ticket types of one event use the same currency. |
| **BR-T6** | **Sales window:** each ticket type has an optional sales start and sales end. If both are set, the end is after the start, and sales can't end after the event ends. By default, sales start when the event is published and end when the event starts.     |
| **BR-T7** | **Per-checkout limit:** each ticket type has a maximum number of tickets per reservation, between 1 and 50, default 10. Every reservation must include at least 1 ticket of a type it lists.                                                                |
| **BR-T8** | Each ticket type has a display order on the event page, and no two ticket types of an event share a position.                                                                                                                                               |
| **BR-T9** | A ticket type with **no** tickets ever issued can be deleted. Once tickets are issued, it can only be **taken off sale**. Its existing tickets stay valid.                                                                                                  |

### 3.6 Reservations · `BR-R`

| ID        | Rule                                                                                                                                                                                                                                     |
| --------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **BR-R1** | A reservation is made by exactly one user, for exactly one event, at a recorded time. It includes one or more ticket types **of that event** (never another event's), each with a quantity that respects BR-T7.                          |
| **BR-R2** | A reservation can only be made when the event is `published`, the event hasn't started, and every ticket type involved is on sale (inside its sales window and not taken off sale).                                                      |
| **BR-R3** | Each reservation has a **reference code**, short and human-readable, that the attendee can read out to support (e.g. `EBK-7Q2X9M`). It's unique on the platform and must not reveal how many reservations exist (no sequential numbers). |
| **BR-R4** | In v0 a reservation is **confirmed immediately**, since tickets are free. **(v1-ready)** In v1 a reservation goes through `pending → paid → cancelled / refunded / expired`, and pending reservations hold tickets until they expire.    |
| **BR-R5** | An attendee can **cancel their own reservation** until the event starts. All its tickets are cancelled and return to availability. The cancellation time is recorded.                                                                    |
| **BR-R6** | Making a reservation is **all or nothing**. If any ticket type can't supply the requested quantity, nothing is reserved.                                                                                                                 |
| **BR-R7** | A reservation's record must still show what was reserved, even after the event or its ticket types are edited later. Deleting a ticket type after tickets exist isn't allowed (BR-T9).                                                   |

### 3.7 Tickets · `BR-K`

| ID        | Rule                                                                                                                                                                                                                            |
| --------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **BR-K1** | A ticket admits **one person** to one event, for one ticket type, and comes from exactly one reservation. A reservation for 3 General tickets produces 3 tickets.                                                               |
| **BR-K2** | Every ticket has a **unique code**, encoded in its QR. The code must be **unguessable**: someone holding one ticket can't work out another ticket's code. Codes are never reused, even after cancellation.                      |
| **BR-K3** | A ticket's status is `active` or `cancelled`. It becomes cancelled when its reservation is cancelled (BR-R5) or its event is cancelled (BR-E9). The cancellation time is recorded. Cancelled tickets never become active again. |
| **BR-K4** | Tickets are never deleted. Attendees keep their history, and organizers keep their reports.                                                                                                                                     |
| **BR-K5** | A ticket belongs to the user who made its reservation. Transferring tickets and attendee names per ticket are out of scope in v0. Check-in (`used`) comes in a later milestone.                                                 |

### 3.8 Metrics & reporting · `BR-M`

These definitions are the "expected" basis for the queries in `db/queries/`.

| ID        | Rule                                                                                                                                     |
| --------- | ---------------------------------------------------------------------------------------------------------------------------------------- |
| **BR-M1** | **Tickets reserved** (on the organizer dashboard) = active tickets, per ticket type and per event. Cancelled tickets don't count.        |
| **BR-M2** | **Available** = quantity − active tickets, never below 0. **Sold out** = available is 0.                                                 |
| **BR-M3** | **Sell-through** = active tickets ÷ quantity, as a percentage with 1 decimal. For an event, both sides are summed over its ticket types. |
| **BR-M4** | **Daily reservations** are grouped by the date of the reservation in the **event's** time zone, not UTC.                                 |
| **BR-M5** | A **repeat attendee** has active tickets for at least 2 different events.                                                                |
| **BR-M6** | An **active organizer** has at least one published, upcoming event.                                                                      |

---

## 4. Decisions

Write the answer **and** the reason, and cite the rules each one produces or depends on.

The rules in section 3 say **what** must hold. These decisions say **how** the schema holds it. Where a rule can't be a `CHECK` (it spans rows or tables, or depends on "now"), the decision says which trigger or function enforces it instead.

### D1 · Organizer: a role or a separate entity? Can one person be both organizer and attendee?

_Rules involved: BR-U4, BR-U5, BR-E1._ (Being both is already decided as yes. The modeling question is yours.)

**Answer:** A separate 1:1 table, `organizers`, whose primary key is also a foreign key to `users` (`organizers.user_id → users.id`). It holds the organizer-only data: `organizer_name` (2–80 characters, unique on `lower(organizer_name)`) and when the user was enabled. `events.organizer_id` references `organizers(user_id)`. Reservations reference `users`. A person who is both has one `users` row and one `organizers` row with the same id. A `BEFORE UPDATE` trigger on `events` rejects any change to `organizer_id` (BR-E1).

**Why:** With a flag on `users` (`is_organizer` plus a nullable `organizer_name`), a foreign key can't ensure that an event's owner is actually an organizer, because an FK can point at a row but can't check a column on it. With a separate table, "only enabled organizers own events" (BR-U4) becomes a plain FK, and `organizer_name` can be `NOT NULL` instead of "required only when the flag is true". Being both (BR-U5) needs nothing special: the same `user_id` shows up on both sides.

### D2 · One order holding several tickets, or one row per ticket? What does a QR code point to?

_Rules involved: BR-R1, BR-R3, BR-R6, BR-K1, BR-K2._

**Answer:** Both levels exist. `reservations` holds one row per checkout: user, event, `reference_code`, status, `created_at` and `cancelled_at`. `tickets` holds one row per admission: reservation, ticket type, `code`, status, `unit_price` at the time of reservation, and `cancelled_at`. A checkout for 3 General + 1 VIP is 1 reservation and 4 tickets. The per-type quantity in BR-R1 is `COUNT(*)` of tickets grouped by type, so it isn't stored separately. **The QR encodes `tickets.code`**, never the reservation, so each person is admitted on their own ticket. `reservations.reference_code` is for support only.

To guarantee that a ticket's type belongs to the reservation's event (BR-R1), `tickets` also carries `event_id` with two composite FKs: `(reservation_id, event_id) → reservations(id, event_id)` and `(ticket_type_id, event_id) → ticket_types(id, event_id)`. This works declaratively, with no trigger.

**Why:** BR-K1 makes a ticket the unit of admission, and BR-K3 lets tickets be cancelled one at a time, so a ticket needs its own row, status and code. The reservation is still needed: it's what the attendee cancels (BR-R5), what support looks up (BR-R3), and the unit of "all or nothing" (BR-R6). All inserts for one reservation happen in a single transaction, so a failure rolls back the whole checkout. I don't add a `reservation_items` table because its quantity would duplicate the ticket count and could disagree with it.

### D3 · Money: integer cents + currency, or `NUMERIC`? Why never `float`?

_Rules involved: BR-T5._

**Answer:** `ticket_types.price NUMERIC(12,2) NOT NULL DEFAULT 0` with `CHECK (price >= 0)`, plus a v0 check `CHECK (price = 0)` that M-v1 drops. The currency is `events.currency CHAR(3) NOT NULL` with `CHECK (currency ~ '^[A-Z]{3}$')`. It's stored once per event, not per ticket type. `tickets.unit_price` copies the price at reservation time.

**Why:** `float`/`double` are binary fractions. They can't represent `0.10` exactly, so sums drift (`0.1 + 0.2 ≠ 0.3`), which is unacceptable for money. Both `NUMERIC` and integer cents are exact. I chose `NUMERIC` because it reads naturally in SQL and in the query labs (`25.00`, not `2500`). Payment gateways that want minor units get a conversion at the API boundary in v1. Putting the currency on `events` makes "all ticket types of one event use the same currency" true by construction, with no check needed. Copying `unit_price` onto the ticket keeps the record correct if the price changes later (BR-R7).

### D4 · A stored `remaining_quantity`, or computed from sold tickets? Risks of each?

_Rules involved: BR-T3, BR-T4, BR-M2._

**Answer:** Computed. Available = `quantity − COUNT(active tickets)`, with a partial index `ON tickets (ticket_type_id) WHERE status = 'active'` to keep it cheap. The reservation function locks each ticket type row involved (`SELECT … FOR UPDATE`, in id order to avoid deadlocks), counts the active tickets, and inserts only if the count stays within the quantity. Lowering `quantity` (BR-T4) goes through a trigger that does the same check under the same lock.

**Why:**

- **Stored counter.** Reads are fast, and `CHECK (reserved <= quantity)` plus an atomic `UPDATE … SET reserved = reserved + n` is a strong guard against overselling. The risk is drift: every path that creates or cancels tickets (reservation, attendee cancel, event cancel, manual fixes) must update it, and one missed path makes it wrong for good. It's also a second source of truth for the same fact, which breaks 3NF.
- **Computed.** Always correct by definition. The risks are the cost of counting (handled by the index) and the race where two checkouts both see "1 left" (handled by the row lock).

At v0 volumes, being correct by construction matters more than saving a count. `docs/04-concurrency.md` benchmarks both approaches. If the counter wins, it comes back as a documented denormalization in `02-design.md`, maintained by a trigger.

### D5 · Event states (draft → published → cancelled/completed). What happens to orders when an event is cancelled?

_Rules involved: BR-E5, BR-E6, BR-E9, BR-E10, BR-K3._ (The business behavior is set. How the schema represents and guards it is yours.)

**Answer:**

- **Representation:** `CREATE TYPE event_status AS ENUM ('draft','published','cancelled','completed')`.
- **Row checks:** `CHECK ((status = 'draft') = (published_at IS NULL))` and `CHECK ((status = 'cancelled') = (cancelled_at IS NOT NULL))`. A check for `status <> 'draft'` requires `description`, `category_id` and a complete location (BR-E6, BR-L4).
- **Transitions:** a `BEFORE UPDATE` trigger allows only `draft→published`, `published→cancelled` and `published→completed` (BR-E5). On `draft→published` it also checks the parts a `CHECK` can't: `starts_at > now()` and at least one ticket type.
- **Cancellation:** an `AFTER UPDATE` trigger on `published→cancelled` sets every active ticket of the event to `cancelled` with `cancelled_at = now()` and marks its reservations cancelled, all in the same transaction (BR-E9, BR-K3). The rows stay, so "my tickets" still shows them.
- **Completion:** v0 has no job. Queries treat `ends_at < now` as completed (BR-E10). A later job only sets the stored status.

**Why:** The status and its timestamps describe the same fact, so the `CHECK`s keep them from contradicting each other. Transition rules compare the old and new row, which only a trigger can see. Cascading the cancellation inside the database means no code path can cancel an event and forget its tickets.

### D6 · Sales windows (`sales_start`, `sales_end`) and per-order limits: database constraint or app logic?

_Rules involved: BR-T6, BR-T7, BR-R2._

**Answer:** It depends on the kind of rule:

| Rule                                                                                 | Where                                                                                                |
| ------------------------------------------------------------------------------------ | ---------------------------------------------------------------------------------------------------- |
| `sales_end > sales_start` when both are set                                          | `CHECK` on `ticket_types`                                                                            |
| `max_per_checkout BETWEEN 1 AND 50`, default 10                                      | `CHECK` + `DEFAULT`                                                                                  |
| `sales_end <= events.ends_at`                                                        | Trigger on `ticket_types` (and on `events` when `ends_at` changes), because it compares two tables  |
| Event published and not started, now inside the window, not off sale (BR-R2)         | The `reserve_tickets()` function, checked in the same transaction as the insert                     |
| Tickets of one type per reservation ≤ `max_per_checkout`, ≥ 1 per listed type (BR-T7) | `reserve_tickets()`                                                                                  |

Unset `sales_start`/`sales_end` stay `NULL` and are resolved at read time: `COALESCE(sales_start, published_at)` and `COALESCE(sales_end, starts_at)`.

**Why:** Anything that is always true of a row is a `CHECK`, so no client can bypass it. Rules that depend on "now" can't be `CHECK`s. A `CHECK` runs only when that row is written, so it would pass today and silently be wrong tomorrow. Rules that count across rows can't be `CHECK`s either. Those belong to the one function that creates reservations, still inside the database and in the same transaction as the insert. Storing `NULL` for the defaults, instead of copying the dates in, means they follow the event automatically if it's rescheduled.

### D7 · Time zones: `TIMESTAMPTZ` plus the event's IANA time zone?

_Rules involved: BR-E3, BR-E4, BR-M4._

**Answer:** Yes. `starts_at` and `ends_at` are `TIMESTAMPTZ` (absolute instants), and `events.timezone TEXT NOT NULL` holds the IANA name. A trigger validates it against `pg_timezone_names`, because a `CHECK` can't query a view. BR-E3 is `CHECK (ends_at > starts_at AND ends_at - starts_at <= INTERVAL '14 days')`. Local display is `starts_at AT TIME ZONE timezone`. Daily reservations (BR-M4) group by `(r.created_at AT TIME ZONE e.timezone)::date`.

**Why:** `TIMESTAMPTZ` stores a single UTC instant, so durations, ordering and "has it started?" are correct no matter where the server or the user is. `TIMESTAMP` without a time zone is a wall-clock reading with no zone, so the same value means different instants in Bogotá and Madrid. The IANA name, rather than a fixed offset like `-05:00`, is needed because offsets change with daylight saving time. The name lets Postgres pick the right offset for each date. Because the column holds an instant, "start and end each identify one unambiguous instant" (BR-E4) holds by construction. Rejecting a wall-clock time that falls in a DST gap or overlap happens when the organizer's input is converted, in the API (M2).

### D8 · Keys: identity integers, or UUIDs/random codes for anything in URLs or QR codes?

_Rules involved: BR-R3, BR-K2._

**Answer:** Primary keys are `BIGINT GENERATED ALWAYS AS IDENTITY` everywhere, used for joins and FKs. Anything a person sees or could guess gets its own `UNIQUE` column:

- `reservations.reference_code`: `EBK-` plus 6 random characters from an alphabet without look-alike characters (`23456789ABCDEFGHJKMNPQRSTUVWXYZ`, 31⁶ ≈ 887 million). It's generated in a function, and a collision is retried.
- `tickets.code`: `UUID DEFAULT gen_random_uuid()` (122 random bits).

**Why:** Integer keys are small, fast to index and easy to read in labs, but they're sequential. Showing them would reveal how many reservations exist and let someone guess the next one (BR-R3, BR-K2). Random public codes avoid both, and the internal key stays cheap. The ticket code is a credential (it gets you in), so it needs real unguessability, which a v4 UUID provides. The reference code isn't a credential (support also checks the account email), so being short and readable matters more there. Codes are never reused because rows are never deleted (D9) and the unique constraint covers cancelled rows too.

### D9 · Delete or soft-delete? Which `ON DELETE` rule fits each relationship?

_Rules involved: BR-U6, BR-E8, BR-C3, BR-T9, BR-R7, BR-K4._

**Answer:** No general soft-delete column. History is protected with `RESTRICT` and status changes:

| Relationship (child → parent)  | `ON DELETE`  | Rule        | Reason                                                                                  |
| ------------------------------ | ------------ | ----------- | --------------------------------------------------------------------------------------- |
| `organizers → users`           | `RESTRICT`   | BR-U6       | An account with history isn't deleted (see below)                                      |
| `events → organizers`          | `RESTRICT`   | BR-U6, E1   | Events outlive any change to the account                                                |
| `events → categories`          | `RESTRICT`   | BR-C3       | A category in use can't be deleted                                                      |
| `ticket_types → events`        | `CASCADE`    | BR-E8       | Deleting a draft takes its ticket types with it                                        |
| `reservations → users`         | `RESTRICT`   | BR-U6       | History must survive                                                                    |
| `reservations → events`        | `RESTRICT`   | BR-E8       | An event with reservations can't vanish                                                |
| `tickets → reservations`       | `RESTRICT`   | BR-K4       | Tickets are never deleted                                                               |
| `tickets → ticket_types`       | `RESTRICT`   | BR-T9, R7   | A ticket type with tickets can only go off sale (`off_sale_at`)                         |

In addition:

- A `BEFORE DELETE` trigger on `events` rejects any event whose `published_at IS NOT NULL` (BR-E8). That covers a published event with no reservations yet, which `RESTRICT` alone would allow.
- A `BEFORE DELETE` trigger on `tickets` and `reservations` always raises (BR-K4).
- **Deleting an account** means anonymizing it: set `users.deleted_at` and scrub the email, name and password hash. The row stays so FKs keep working (BR-U6). This is the only soft delete, and it exists for privacy, not to hide rows.

**Why:** A soft-delete flag on every table means every query has to remember `WHERE deleted_at IS NULL`, and FKs can still point at "deleted" rows. Here the rules already say what may disappear: drafts, unused ticket types, unused categories. Everything else changes status instead. `RESTRICT` makes the database refuse a delete that would lose history, so a bug can't silently cascade-delete tickets. `CASCADE` is used in exactly one place, where everything below the deleted row is disposable (a draft's ticket types, which can't have tickets because drafts can't be reserved).

---

## 5. Open questions

- **Ticket type renames (BR-R7):** tickets keep the price but not the type's name. If an organizer renames "General" to "VIP" after tickets exist, old tickets show the new name. Should the name be copied onto the ticket too, or renames blocked once tickets exist?
- **Who cancelled:** when an event is cancelled, its reservations are marked cancelled too (D5). Should the reservation record whether the attendee or the organizer cancelled it?
- **Completed status (BR-E10):** v0 derives "completed" from `ends_at < now`, so the stored status can lag. Is that acceptable until a job exists?
- **Event URLs:** events are public, so I expose their integer id in URLs. Use a slug instead, for nicer links and to hide the number of events?
