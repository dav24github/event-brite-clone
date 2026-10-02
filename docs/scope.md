# Product scope

What the product does, by release. This was consolidated on 2026-10-01 from the earlier `requirements.md`, `requirements-v2.md` and `process.md` (archived in `_archive/2026-09-second-attempt/`). **Nothing was dropped.** Ideas that came too early were moved to later releases.

## The core loop

- **Organizer:** create an event → set ticket types (price, quantity) → publish.
- **Attendee:** browse or search → select tickets → check out → receive a digital ticket.

## MVP · v0 (M1–M3): free events

**Must have**
- Sign up and sign in with email and password. Roles: organizer and attendee. Whether one person can be both gets decided in the business rules.
- Organizers create, edit and publish events: title, description, date and time with a time zone, a physical location or an online link, a cover image URL, and a category.
- Ticket types per event (e.g. General, VIP) with quantity limits. Free tickets only in v0.
- Reservations that never oversell, even under concurrent requests.
- Attendee portal: "my tickets", each with a unique code and QR code.
- Browse, plus basic search with category filters.
- Organizer dashboard: tickets reserved per event.

**Out of scope for v0:** payments, emails, uploads, real-time updates, seat maps, promo codes, recurring events.

## v1 (M4): paid tickets

- Stripe Checkout (test mode). Order states: pending → paid → cancelled / refunded / expired.
- Payment webhooks, signature-verified and idempotent.
- Reservation holds that expire and release their tickets.
- Confirmation emails with the QR ticket, sent by a background job (BullMQ + Redis; Resend or Brevo).
- Event poster and venue image uploads to S3-compatible storage (S3, R2 or MinIO).
- Organizer revenue per event and per ticket type.
- Stretch: Mercado Pago as a second, regional gateway.
- Stretch: PDF ticket download.

## v2 (M5): AI features

- Event draft assistant: free text → a structured event draft.
- Semantic event search ("chill live jazz this weekend").
- Event Q&A for attendees, grounded in the event's own information, with citations.

## v3 (M6–M7): scale and hardening

- High-traffic ticket drops: holds or a waiting room, caching, rate limiting.
- Live ticket availability (WebSockets/SSE, with Redis pub/sub across instances).
- The original distributed-lock idea (Redis Redlock), evaluated here *against* database-level locking, with load tests.
- Google sign-in, audit logs, backups and restore drills.

## Later (M8–M12)

- Self-hosting on a VPS or cloud, with infrastructure as code.
- Organizer copilot (an agent) and an MCP server.
- Check-in scanner app with offline mode, plus real-time scan validation ("ticket already used") across devices.
- Organizations and multi-tenancy: teams with roles (super-admin, owner, staff/scanner) and strict tenant isolation (`tenant_id` + row-level security).
- A public/partner API. The original requirements considered GraphQL.
- Session and permission caching in Redis, only if measurements show it's needed.
- Organizer analytics: funnels and cohorts.

## Could have (unscheduled)

- Discount codes · waitlists for sold-out events · recurring events · refund automation.

## Won't have (for now)

- Interactive seat maps · multi-day agenda builders · in-app messaging between attendees and organizers · custom email campaigns.
