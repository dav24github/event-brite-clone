-- Q07 · organizer
-- Question: How many tickets are still available per ticket type, and which ones are sold out?
-- Concept:  arithmetic on aggregates; GREATEST(..., 0); a boolean column
-- Rules:    BR-M2 (available = quantity − active tickets, never below 0; sold out = available is 0)
-- Input:    organizer_id 2
-- Output:   title, ticket_type, quantity, available, sold_out
-- Filter:   events.organizer_id = 2
-- Sort:     title, position
-- Expected: 7 rows · exactly one sold out: '[Edge] Sold Out Rooftop' General (5, 0, true)
--           '[Edge] Sold Out Rooftop' VIP (10, 10, false) · Design Talks General (143, 69, false)
-- Verify:   write it twice and compare; 0 rows means both agree:
--             version A: LEFT JOIN tickets + GROUP BY
--             version B: a correlated subquery per ticket type
--                        (SELECT count(*) FROM tickets WHERE ticket_type_id = tt.ticket_type_id AND status = 'active')
--             (A EXCEPT B) UNION ALL (B EXCEPT A);   → expect 0 rows
-- Run on a fresh run_all.sql.

SET search_path TO eventbrite;