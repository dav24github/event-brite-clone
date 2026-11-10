-- Q12 · platform
-- Question: How many organizers are active right now, and which ones aren't?
-- Concept:  EXISTS / NOT EXISTS (semi-join and anti-join)
-- Rules:    BR-M6 (active organizer = at least one published, upcoming event)
-- Input:    none
-- Output:   query A: active_organizers (one number)
--           query B: user_id, organizer_name of the organizers who are NOT active
-- Filter:   EXISTS (an event of that organizer with status = 'published' AND starts_at > now())
-- Sort:     B: user_id
-- Expected: A: 23 (of 25 organizers)
--           B: 2 rows (A + B must add up to 25)
--             4  'Food Collective'  (owns '[Edge] Cancelled Concert': cancelled doesn't count)
--             19 'Startup Lab'
-- Run on a fresh run_all.sql.

SET search_path TO eventbrite;

-- query A
SELECT COUNT(DISTINCT o.user_id) AS active_organizers
FROM organizers o
JOIN events e ON e.organizer_id = o.user_id
WHERE e.status = 'published' AND e.starts_at > now();

-- SELECT COUNT(*) AS active_organizers
-- FROM organizers o
-- WHERE EXISTS (SELECT 1 FROM events e
--               WHERE e.organizer_id = o.user_id
--                 AND e.status = 'published' AND e.starts_at > now());

-- query B
SELECT o.user_id, o.organizer_name
FROM organizers o
WHERE NOT EXISTS (SELECT 1 FROM events e
                  WHERE e.organizer_id = o.user_id
                    AND e.status = 'published'
                    AND e.starts_at > now())
ORDER BY o.user_id;

-- SELECT o.user_id, o.organizer_name
-- FROM organizers o
-- LEFT JOIN events e ON e.organizer_id = o.user_id
--                   AND e.status = 'published' AND e.starts_at > now()
-- WHERE e.event_id IS NULL
-- ORDER BY o.user_id;