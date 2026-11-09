-- Q04 · attendee
-- Question: Can I see this online event's meeting link? Only if I hold an active ticket for it.
-- Concept:  EXISTS (a yes/no subquery; it stops at the first match and never duplicates rows)
-- Rules:    BR-L3 (meeting_url shown only to active ticket holders)
-- Input:    user_id, event_id. Run it three times:
--             a) user 500, event 121  → has active tickets
--             b) user 501, event 121  → no reservation
--             c) user 600, event 123  → had tickets, but the event was cancelled
-- Output:   meeting_url (one row, or no rows)
-- Filter:   events.event_id = <event> AND EXISTS (an active ticket of <user> for that event)
-- Steps:    the subquery joins tickets → reservations and checks user_id and tickets.status = 'active'
-- Expected: a) 1 row 'https://meet.example.com/edge-sold-out'
--           b) 0 rows
--           c) 0 rows (cancelled tickets don't count)
-- Run on a fresh run_all.sql.

SET search_path TO eventbrite;

SELECT e.meeting_url
FROM events e
JOIN  reservations r USING (event_id)
WHERE (
    EXISTS (SELECT 1 FROM tickets t 
                WHERE t.reservation_id = r.reservation_id AND
                t.status = 'active') AND
    r.user_id = 500 AND
    e.event_id = 121
);

-- -----------------------------------------------------------------------------
-- Reference version (follows the header)
-- -----------------------------------------------------------------------------
-- The version above joins reservations in the outer query, so it returns one row
-- PER RESERVATION. A user can reserve the same event several times (user 1 has 10
-- reservations for event 5): the same meeting_url then comes back 10 times.
-- Here the outer query only reads events, and EXISTS only answers yes/no, so the
-- result is always one row or none, however many reservations or tickets there are.

-- user 500, event 121 → 1 row 'https://meet.example.com/edge-sold-out'
SELECT e.meeting_url
  FROM events e
 WHERE e.event_id = 121
   AND EXISTS (SELECT 1
                 FROM tickets t
                 JOIN reservations r USING (reservation_id)
                WHERE t.event_id = e.event_id
                  AND r.user_id  = 500
                  AND t.status   = 'active');