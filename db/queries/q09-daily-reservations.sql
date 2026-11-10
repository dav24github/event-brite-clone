-- Q09 · organizer
-- Question: How many reservations did my event get each day, by the event's local date?
-- Concept:  GROUP BY an expression; AT TIME ZONE + ::date
-- Rules:    BR-M4 (grouped by the date in the EVENT's time zone, not UTC), D7
-- Input:    event_id 81 ('Indie Rock Showcase', Europe/Madrid, a past event with sales spread over days)
-- Output:   local_day, reservations
--           local_day = (reservations.created_at AT TIME ZONE events.timezone)::date
-- Filter:   reservations.event_id = 81 (count every reservation, cancelled ones too: they were made that day)
-- Sort:     local_day
-- Expected: 18 reservations in total (the sum of the column), over about 9–10 days
--           Only the total is fixed: the seed times are relative to now(), so each run_all.sql
--           shifts them by hours, and a reservation near Madrid's midnight can move to the next day.
-- Try:      group by created_at::date instead. That takes the date on the SERVER's clock (UTC-4),
--           not Madrid's. A reservation made at 01:33 on May 27 in Madrid is 19:33 on May 26
--           on the server, so it's counted on the 26th: the organizer's chart is a day off.
--           BR-M4 requires the event's time zone exactly so this doesn't happen.
-- Next:     4.1 adds a running total to this query with SUM(...) OVER (ORDER BY local_day).
-- Run on a fresh run_all.sql.

SET search_path TO eventbrite;

SELECT 
    (r.created_at AT TIME ZONE e.timezone)::date AS local_day, 
    COUNT(*) AS reservations,
    SUM(COUNT(*)) OVER (ORDER BY (r.created_at AT TIME ZONE e.timezone)::date) AS running_total
FROM reservations r
JOIN events e USING (event_id)
WHERE r.event_id = 81
GROUP BY local_day
ORDER BY  local_day;