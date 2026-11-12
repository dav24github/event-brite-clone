-- =============================================================================
-- w01 · window functions (S01 step 4.1)
-- A window function computes across a set of rows ("the window") but, unlike
-- GROUP BY, keeps every row:  f(...) OVER (PARTITION BY ... ORDER BY ...)
--   PARTITION BY = restart the calculation per group (like GROUP BY, without collapsing)
--   ORDER BY     = the order the window walks in (needed for running totals, ranks, LAG)
-- Window functions run AFTER GROUP BY, so they can use aggregates: SUM(COUNT(*)) OVER (...)
-- Run on a fresh run_all.sql. Exact dates move with the seed run; totals don't.
-- =============================================================================

SET search_path TO eventbrite;


-- -----------------------------------------------------------------------------
-- W1 · running total of reservations for one event                 builds on Q09
-- -----------------------------------------------------------------------------
-- Question: Day by day, how many reservations has event 81 collected so far?
-- Concept:  SUM(...) OVER (ORDER BY ...) = a running total
-- Rules:    BR-M4 (days in the event's time zone)
-- Input:    event_id 81
-- Output:   local_day, reservations, running_total
-- Sort:     local_day
-- Steps:    1. start from your Q09 (reservations per local_day)
--           2. add SUM(COUNT(*)) OVER (ORDER BY <the local_day expression>) AS running_total
--              (an alias can't be used inside OVER: repeat the expression, or put Q09 in a CTE
--               and write SUM(reservations) OVER (ORDER BY local_day) on top — cleaner)
-- Expected: about 10 rows · running_total goes up every row · the LAST row is 18
--           (18 = Q09's total: a running total always ends at the grand total)
WITH per_day AS (
    SELECT (r.created_at AT TIME ZONE e.timezone)::date AS local_day,
           COUNT(*) AS reservations
    FROM reservations r
    JOIN events e USING (event_id)
    WHERE r.event_id = 81
    GROUP BY local_day
)
SELECT local_day, reservations,
        SUM(reservations) OVER (ORDER BY local_day) AS running_total
FROM per_day
ORDER BY local_day;

-- -----------------------------------------------------------------------------
-- W2 · running total per event, all of an organizer's events
-- -----------------------------------------------------------------------------
-- Question: For each of organizer 2's events, how many reservations so far, day by day?
-- Concept:  PARTITION BY = restart the running total for every event
-- Rules:    BR-M4
-- Input:    organizer_id 2
-- Output:   title, local_day, reservations, running_total
-- Sort:     title, local_day
-- Steps:    same as W1, but filter by organizer, GROUP BY event_id, title, local_day,
--           and use OVER (PARTITION BY event_id ORDER BY local_day)
-- Expected: about 26 rows · running_total restarts at each new event
--           the last row of each event equals its total reservations:
--             Design Talks 31 · Stand-up Comedy 10 · Street Food Fair 7
--             Live Jazz Night 4 · '[Edge] Sold Out Rooftop' 2
-- Try:      remove PARTITION BY: the total no longer restarts, it runs across all events
WITH per_day AS (
    SELECT e.event_id,  e.title, 
            (r.created_at AT TIME ZONE e.timezone)::date AS local_day,
            COUNT(*) AS reservations
    FROM reservations r
    JOIN events e USING (event_id)
    WHERE e.organizer_id = 2
    GROUP BY e.event_id, e.title, local_day
)
SELECT title, local_day, reservations, 
        SUM(reservations) OVER (PARTITION BY event_id ORDER BY local_day) as running_total
FROM per_day
ORDER BY title, local_day;

-- -----------------------------------------------------------------------------
-- W3 · top 2 events by sell-through within each category           builds on Q08
-- -----------------------------------------------------------------------------
-- Question: In each category, which 2 upcoming events sell best?
-- Concept:  RANK() OVER (PARTITION BY ... ORDER BY ...) = top-N per group
-- Rules:    BR-M3 (sell-through), BR-E7 (published + upcoming)
-- Input:    all published, upcoming events
-- Output:   category, rnk, event_id, title, sell_through_pct
-- Sort:     category, rnk
-- Steps:    1. CTE per_type: active tickets and quantity per ticket type (your Q08 CTE)
--           2. CTE per_event: sell_through_pct per event + its category name
--              (filter status = 'published' AND starts_at > now())
--           3. CTE ranked: per_event + RANK() OVER (PARTITION BY category ORDER BY sell_through_pct DESC)
--           4. SELECT ... FROM ranked WHERE rnk <= 2
-- Watch:    you can't write WHERE rnk <= 2 in the same SELECT that computes rnk:
--           WHERE runs before window functions. That's why step 3 is its own CTE.
-- Expected: 20 rows (10 categories × 2) · for example:
--             Education         1  Street Food Fair (event 3)  93.0
--             Health & Wellness 1  Wine Tasting (event 1)      93.1
--             Food & Drink      2  Street Food Fair (event 80) 22.2
-- Try:      replace RANK() with ROW_NUMBER() and DENSE_RANK(). They only differ on ties:
--             values 90, 90, 80 -> RANK 1,1,3 · DENSE_RANK 1,1,2 · ROW_NUMBER 1,2,3
--           (no ties in the top 2 here, so all three give the same 20 rows)
WITH per_type AS (    
    SELECT 
        tt.event_id,
        tt.ticket_type_id, 
        tt.quantity,
        GREATEST(COUNT(*) FILTER (WHERE t.status = 'active'), 0) as active_tickets
    FROM ticket_types tt
    LEFT JOIN tickets t USING (ticket_type_id)
    GROUP BY tt.event_id, tt.ticket_type_id, tt.quantity
),
per_event AS (    
    SELECT e.event_id, e.title, c.name as category,
        SUM(per_type.active_tickets) as active_tickets, 
        SUM(per_type.quantity) as quantity, 
        ROUND(100.0 * SUM(per_type.active_tickets) / SUM(per_type.quantity), 1) as sell_through_pct
    FROM per_type
    JOIN events e ON e.event_id = per_type.event_id
    JOIN categories c ON c.category_id = e.category_id
    WHERE e.status = 'published' AND e.starts_at > now() 
    GROUP BY e.title, e.event_id, e.title, c.name
    ORDER BY sell_through_pct DESC, e.title
),
ranked AS (
SELECT category, 
		RANK() OVER (PARTITION BY category ORDER BY sell_through_pct DESC) AS rnk,
		event_id,
		title,
		sell_through_pct
FROM per_event
)
SELECT * FROM ranked WHERE rnk <= 2
ORDER BY category, rnk;;

-- -----------------------------------------------------------------------------
-- W4 · day-over-day change                                           builds on W1
-- -----------------------------------------------------------------------------
-- Question: Did event 81 get more or fewer reservations than the day before?
-- Concept:  LAG(x) OVER (ORDER BY ...) = the value from the previous row
-- Input:    event_id 81
-- Output:   local_day, reservations, previous_day, change
--           previous_day = LAG(reservations) OVER (ORDER BY local_day)
--           change       = reservations - previous_day
-- Sort:     local_day
-- Steps:    put W1's per-day counts in a CTE, then apply LAG on top
-- Expected: same rows as W1 · the FIRST row has previous_day and change NULL (no day before it)
--           e.g. a day with 5 after a day with 1 -> change 4
-- Watch:    "previous row" is not "yesterday": days with no reservations have no row,
--           so LAG compares with the last day that HAD sales.
-- Try:      LEAD(reservations) OVER (ORDER BY local_day) = the NEXT row's value
WITH per_day AS (
    SELECT (r.created_at AT TIME ZONE e.timezone)::date AS local_day,
	COUNT(*) AS reservations
FROM reservations r
JOIN events e USING (event_id)
WHERE r.event_id = 81
GROUP BY local_day
)
SELECT local_day, reservations, 
	LAG(reservations) OVER (ORDER BY local_day) AS previous_day,
	CASE
        WHEN LAG(reservations) OVER (ORDER BY local_day) IS NULL THEN NULL
        WHEN  reservations > LAG(reservations) OVER (ORDER BY local_day) THEN 'more'
        WHEN  reservations < LAG(reservations) OVER (ORDER BY local_day) THEN 'fewer'
        ELSE 'same'
	END AS change
FROM per_day
ORDER BY local_day;
