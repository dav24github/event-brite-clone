-- Q09 · organizer
-- Question: How many reservations did my event get each day, by the event's local date?
-- Concept:  GROUP BY an expression; AT TIME ZONE + ::date
-- Rules:    BR-M4 (grouped by the date in the EVENT's time zone, not UTC), D7
-- Input:    event_id 81 ('Indie Rock Showcase', Europe/Madrid, a past event with sales spread over days)
-- Output:   local_day, reservations
--           local_day = (reservations.created_at AT TIME ZONE events.timezone)::date
-- Filter:   reservations.event_id = 81 (count every reservation, cancelled ones too: they were made that day)
-- Sort:     local_day
-- Expected: 9 rows, 18 reservations in total · busiest day has 4
--           (the dates move with the day you run run_all.sql: the seed dates are relative to now())
-- Try:      group by created_at::date instead (the server's zone): a reservation made late
--           at night can land on a different day. That's the bug BR-M4 prevents.
-- Next:     4.1 adds a running total to this query with SUM(...) OVER (ORDER BY local_day).
-- Run on a fresh run_all.sql.

SET search_path TO eventbrite;

