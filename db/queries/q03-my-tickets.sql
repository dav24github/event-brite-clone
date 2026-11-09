-- Q03 · attendee
-- Question: What are my tickets, upcoming and past, with the start time in the event's own time zone?
-- Concept:  4-table join; AT TIME ZONE to turn a TIMESTAMPTZ into local wall-clock time
-- Rules:    BR-K5 (a ticket's owner is its reservation's user), BR-E4, D7 (shown in the event's time zone),
--           BR-E9 (cancelled tickets still show, marked cancelled)
-- Input:    user_id 500
-- Output:   title, local_start, timezone, ticket_type, ticket_status, upcoming
--           local_start = starts_at AT TIME ZONE events.timezone
--           upcoming    = starts_at > now()
-- Filter:   reservations.user_id = 500 (tickets have no user column: go through reservations)
-- Sort:     starts_at, then ticket_type
-- Steps:    tickets → reservations (for user_id) → events → ticket_types
-- Expected: 4 rows, all 'active', all upcoming, all 'America/Bogota'
--           1 'Photography Walk' · General
--           3 '[Edge] Sold Out Rooftop' · General, local_start 18:00 (19:00 in UTC-4 = 18:00 in Bogotá, UTC-5)
-- Run on a fresh run_all.sql.

SET search_path TO eventbrite;

SELECT e.title,
       e.starts_at AT TIME ZONE e.timezone AS local_start,   -- instant UTC -> Bogotá wall clock
       e.timezone,                                          -- says which zone local_start is in
       tt.name                             AS ticket_type,
       t.status                            AS ticket_status,
       e.starts_at > now()                 AS upcoming      -- true / false
FROM tickets t
JOIN reservations r  USING (reservation_id)
JOIN events e        ON e.event_id = t.event_id
JOIN ticket_types tt ON tt.ticket_type_id = t.ticket_type_id
WHERE r.user_id = 500
ORDER BY e.starts_at, tt.name