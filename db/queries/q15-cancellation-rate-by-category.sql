-- Q15 · platform
-- Question: What share of tickets ends up cancelled, per category?
-- Concept:  count(...) FILTER (WHERE ...) for conditional counts; NULLIF to avoid dividing by 0
-- Rules:    BR-K3 (cancelled tickets), BR-R5 (attendee cancels), BR-E9 (event cancels), BR-C1
-- Input:    none
-- Output:   category, tickets, cancelled, cancel_pct
--           cancel_pct = round(100.0 * cancelled / NULLIF(tickets, 0), 1)
-- Filter:   none: every category appears (LEFT JOIN, so a category with no tickets still shows)
-- Sort:     cancel_pct DESC NULLS LAST, category
-- Expected: 10 rows
--             first: Business 819 tickets, 34 cancelled, 4.2
--             last:  Food & Drink 459, 0, 0.0
--             Music 918, 20, 2.2 (includes the 3 tickets of '[Edge] Cancelled Concert')
-- Run on a fresh run_all.sql.

SET search_path TO eventbrite;

SELECT c.category_id,
		c.name AS category, 
		SUM(cte.tickets) AS tickets, 
		SUM(cte.cancelled_tickets) AS cancelled, 
		round(100.0 * SUM(cte.cancelled_tickets) / NULLIF(SUM(cte.tickets), 0), 1) AS cancel_pct
FROM categories c
LEFT JOIN (
    SELECT e.event_id, 
			e.category_id, 
			COUNT(t.ticket_id) FILTER (WHERE t.status = 'cancelled') AS cancelled_tickets,
			COUNT(t.ticket_id) AS tickets
	FROM events e
	JOIN tickets t USING (event_id)
	GROUP BY e.event_id, e.category_id 
) AS cte
ON cte.category_id = c.category_id
GROUP BY c.category_id, c.name 
ORDER BY cancel_pct DESC NULLS LAST, category

-- SELECT c.category_id, c.name AS category,
--        COUNT(t.ticket_id) AS tickets,
--        COUNT(t.ticket_id) FILTER (WHERE t.status = 'cancelled') AS cancelled,
--        round(100.0 * COUNT(t.ticket_id) FILTER (WHERE t.status = 'cancelled')
--              / NULLIF(COUNT(t.ticket_id), 0), 1) AS cancel_pct
-- FROM categories c
-- LEFT JOIN events e  ON e.category_id = c.category_id
-- LEFT JOIN tickets t ON t.event_id = e.event_id
-- GROUP BY c.category_id, c.name
-- ORDER BY cancel_pct DESC NULLS LAST, category;