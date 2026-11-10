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

WITH a AS ( 
-- Version A: LEFT JOIN tickets + GROUP BY
        SELECT e.title,
                tt.name AS ticket_type,
                tt.quantity,
                GREATEST(tt.quantity - COUNT(at.ticket_id), 0) AS available,
                (GREATEST(tt.quantity - COUNT(at.ticket_id), 0) = 0) AS sold_out
        FROM events e
        JOIN ticket_types tt ON e.event_id = tt.event_id
        LEFT JOIN tickets at ON tt.ticket_type_id = at.ticket_type_id AND at.status = 'active'
        WHERE e.organizer_id = 2
        GROUP BY e.title, tt.name, tt.quantity, tt.position
        ORDER BY e.title, tt.position
),
b AS ( 
-- Version B: correlated subquery per ticket type
        SELECT e.title,
                tt.name AS ticket_type,
                tt.quantity,
                GREATEST(tt.quantity - (
                SELECT COUNT(*)
                FROM tickets t
                WHERE t.ticket_type_id = tt.ticket_type_id
                AND t.status = 'active'
                ), 0) AS available,
                (GREATEST(tt.quantity - (
                SELECT COUNT(*)
                FROM tickets t
                WHERE t.ticket_type_id = tt.ticket_type_id
                AND t.status = 'active'
                ), 0) = 0) AS sold_out
        FROM events e
        JOIN ticket_types tt ON e.event_id = tt.event_id
        WHERE e.organizer_id = 2
        ORDER BY e.title, tt.position 
)
(SELECT * FROM a EXCEPT SELECT * FROM b)
UNION ALL
(SELECT * FROM b EXCEPT SELECT * FROM a);      -- expect 0 rows