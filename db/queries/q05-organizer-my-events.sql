-- Q05 · organizer
-- Question: Which events do I organize, drafts included, and how many of each status?
-- Concept:  filter by owner; GROUP BY status (second query)
-- Rules:    BR-E7 (drafts are visible only to their organizer: this is the one place they appear),
--           BR-E1 (organizer_id is the owner)
-- Input:    organizer_id 2
-- Output:   query A (list):    event_id, title, status, starts_at, published_at
--           query B (summary): status, events
-- Filter:   events.organizer_id = 2
-- Sort:     A: starts_at · B: status
-- Expected: A: 5 rows, '[Edge] Sold Out Rooftop' among them
--           B: 1 row · published 5 (organizer 2 has no drafts in the seed)
-- Try:      organizer_id 7, who has 3 drafts: they must show up in A and as 'draft' in B
-- Run on a fresh run_all.sql.

SET search_path TO eventbrite;

-- Q A
SELECT event_id, title, status, starts_at, published_at
FROM events
WHERE organizer_id = 2
ORDER BY starts_at;

-- Q B
SELECT status, COUNT(*) as events
FROM events
WHERE organizer_id = 2
GROUP BY status; 
ORDER BY status