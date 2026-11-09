-- Q06 · organizer
-- Question: On my dashboard, how many tickets are reserved per ticket type, and per event?
-- Concept:  LEFT JOIN + count(...) FILTER (WHERE ...); two levels of grouping
-- Rules:    BR-M1 (tickets reserved = active tickets; cancelled ones don't count)
-- Input:    organizer_id 2
-- Output:   query A (per type):  title, ticket_type, reserved
--           query B (per event): title, reserved
-- Filter:   events.organizer_id = 2; count only tickets.status = 'active'
-- Sort:     title, then ticket type position
-- Watch:    count(t.ticket_id), not count(*): with a LEFT JOIN, a type with no tickets
--           still gives one row, and count(*) would count it as 1
-- Expected: A: 7 rows · '[Edge] Sold Out Rooftop' General 5, VIP 0
--           B: 5 rows · Design Talks 74, Street Food Fair 20, Stand-up Comedy 17,
--              Live Jazz Night 11, '[Edge] Sold Out Rooftop' 5
-- Run on a fresh run_all.sql.

SET search_path TO eventbrite;

-- Q1
SELECT e.title, tt.name, COUNT(t.ticket_id) AS reserved
FROM ticket_types tt
JOIN events e USING (event_id)
LEFT JOIN tickets t ON t.ticket_type_id = tt.ticket_type_id  AND t.status = 'active'
WHERE e.organizer_id = 2
GROUP BY e.title, tt.name, tt.position
ORDER BY e.title, tt.position;

-- Q2
SELECT e.title, COUNT(t.ticket_id) AS reserved
FROM events e
LEFT JOIN tickets t ON t.event_id = e.event_id AND t.status = 'active'
WHERE e.organizer_id = 2
GROUP BY e.title
ORDER BY e.title;