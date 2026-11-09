-- Q01 · attendee
-- Question: Which events can I browse right now, grouped by category, and how many tickets are left in each?
-- Concept:  JOIN + LEFT JOIN + GROUP BY; active tickets counted per ticket type, then summed per event
-- Rules:    BR-E7 (browse = published + upcoming), BR-M2 (available = quantity − active tickets)
-- Input:    none (every visitor sees the same list)
-- Output:   category, event_id, title, starts_at, tickets_available
-- Filter:   events.status = 'published' AND starts_at > now()
-- Sort:     category, starts_at
-- Steps:    1. join events → categories → ticket_types
--           2. LEFT JOIN the active tickets per ticket type (a type with no sales must still count)
--           3. GROUP BY the event; tickets_available = sum(quantity) − active tickets
-- Expected: 73 rows · first row 'Arts & Culture' · 'Book Club'
--           '[Edge] Sold Out Rooftop' shows 10 available (General is sold out, VIP has 10)
--           '[Edge] No Sales Workshop' shows 50 · drafts, '[Edge] Cancelled Concert' and past events don't appear
-- Run on a fresh run_all.sql (the constraint tests change some rows).

SET search_path TO eventbrite;

SELECT c.name AS category,
        e.event_id AS event_id,
        e.title,
        e.starts_at,
        SUM(tt.quantity - COALESCE(at.active_tickets, 0)) AS tickets_available
FROM events e
JOIN categories c USING (category_id)
JOIN ticket_types tt USING (event_id)
LEFT JOIN (
    SELECT ticket_type_id, COUNT(*) AS active_tickets
    FROM tickets
    WHERE status = 'active'
    GROUP BY ticket_type_id
) as at USING (ticket_type_id)
WHERE e.status = 'published'
  AND e.starts_at > now()
GROUP BY c.name, e.event_id, e.title, e.starts_at
ORDER BY c.name, e.starts_at;