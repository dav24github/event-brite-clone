-- Q13 · platform
-- Question: How many events are in each status, counting a published event that already ended as completed?
-- Concept:  a derived column with CASE; GROUP BY that expression
-- Rules:    BR-E10 (completed = ends_at < now; in v0 no job updates the stored status yet)
-- Input:    none
-- Output:   query A: effective_status, events
--           query B: event_id, title, ends_at of the events the job would mark completed
-- effective_status = CASE WHEN status = 'published' AND ends_at < now() THEN 'completed'
--                         ELSE status::text END
--           (::text: a CASE can't mix the enum and a plain string)
-- Sort:     A: effective_status · B: ends_at
-- Expected: A: 4 rows · cancelled 1, completed 40, draft 9, published 73
--           B: 11 rows (stored 'published', ends_at in the past: 29 stored completed + 11 = 40)
-- Run on a fresh run_all.sql.

SET search_path TO eventbrite;

-- queary A
SELECT CASE
	WHEN status = 'published' AND ends_at < now()
	THEN 'completed'
	ELSE status::text  
	END AS effective_status, 
	COUNT(*) AS events
FROM events
GROUP BY effective_status
ORDER BY effective_status;

-- queary B
SELECT event_id, title, ends_at
FROM events
WHERE status = 'published'
    AND ends_at < now()
ORDER BY ends_at;
