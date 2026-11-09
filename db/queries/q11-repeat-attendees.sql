-- Q11 · platform
-- Question: How many repeat attendees does the platform have, and who are the top ones?
-- Concept:  GROUP BY + HAVING; count(DISTINCT ...)
-- Rules:    BR-M5 (repeat attendee = active tickets for at least 2 DIFFERENT events)
-- Input:    none
-- Output:   query A: repeat_attendees (one number)
--           query B: user_id, full_name, events   (the top 3)
-- Filter:   tickets.status = 'active'; HAVING count(DISTINCT event_id) >= 2
-- Sort:     B: events DESC, user_id · LIMIT 3
-- Watch:    count(DISTINCT event_id), not count(*): 3 tickets to one event is 1 event
-- Expected: A: 548
--           B: user 1 (89 events), user 2 (48), user 3 (40)
-- Verify:   write A twice and compare the user lists; 0 rows means both agree:
--             version A: GROUP BY user_id HAVING count(DISTINCT event_id) >= 2
--             version B: a self-join: two active tickets of the same user with different event_id
--                        (SELECT DISTINCT r1.user_id ... WHERE t1.event_id <> t2.event_id)
--             (A EXCEPT B) UNION ALL (B EXCEPT A);   → expect 0 rows
-- Run on a fresh run_all.sql.

SET search_path TO eventbrite;

