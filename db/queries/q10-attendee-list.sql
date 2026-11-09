-- Q10 · organizer
-- Question: Who's coming to my event, and how many tickets does each person hold?
-- Concept:  3-table join + GROUP BY a person
-- Rules:    BR-K5 (owner = the reservation's user), BR-K3 (only active tickets admit someone)
-- Input:    event_id 121 ('[Edge] Sold Out Rooftop')
-- Output:   full_name, email, tickets
-- Filter:   tickets.event_id = 121 AND tickets.status = 'active'
-- Sort:     tickets DESC, full_name
-- Steps:    tickets → reservations → users; GROUP BY users.user_id
-- Expected: 2 rows
--             Ana Díaz     user500@example.com  3
--             Lucía López  user1@example.com    2   (user 1 is also an organizer: BR-U5)
-- Run on a fresh run_all.sql.

SET search_path TO eventbrite;

