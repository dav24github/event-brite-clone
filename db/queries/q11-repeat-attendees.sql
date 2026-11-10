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

-- Query A · how many repeat attendees → 548
SELECT COUNT(*) AS repeat_attendees
FROM (SELECT r.user_id
      FROM reservations r
      JOIN tickets t ON t.reservation_id = r.reservation_id AND t.status = 'active'
      GROUP BY r.user_id
      HAVING COUNT(DISTINCT r.event_id) > 1) AS x;


-- Query B · the top 3 → user 1 (89), user 2 (48), user 3 (40)
SELECT u.user_id, u.full_name, COUNT(DISTINCT r.event_id) AS events
FROM reservations r
JOIN users u   ON u.user_id = r.user_id
JOIN tickets t ON t.reservation_id = r.reservation_id AND t.status = 'active'
GROUP BY u.user_id, u.full_name
HAVING COUNT(DISTINCT r.event_id) > 1
ORDER BY events DESC, u.user_id
LIMIT 3;


-- Verify · find the SAME set of users two different ways, then compare → expect 0 rows
--   version_a: count each user's distinct events (GROUP BY + HAVING)
--   version_b: find a pair of active tickets of one user for two different events (self-join)
-- Both sides return only user_id: EXCEPT compares whole rows, so the columns must match.
-- (This compares two METHODS, not query A with query B: those answer different questions.)
WITH version_a AS (
    SELECT r.user_id
    FROM reservations r
    JOIN tickets t ON t.reservation_id = r.reservation_id AND t.status = 'active'
    GROUP BY r.user_id
    HAVING COUNT(DISTINCT r.event_id) > 1
),
version_b AS (
    SELECT DISTINCT r1.user_id
    FROM reservations r1
    JOIN tickets t1      ON t1.reservation_id = r1.reservation_id AND t1.status = 'active'
    JOIN reservations r2 ON r2.user_id = r1.user_id                  -- same user...
    JOIN tickets t2      ON t2.reservation_id = r2.reservation_id AND t2.status = 'active'
    WHERE r1.event_id <> r2.event_id                                -- ...different event
) 
(SELECT user_id FROM version_a EXCEPT SELECT user_id FROM version_b)
UNION ALL
(SELECT user_id FROM version_b EXCEPT SELECT user_id FROM version_a);