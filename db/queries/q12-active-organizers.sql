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

