-- Q08 · organizer
-- Question: What's the sell-through of each of my events?
-- Concept:  CTE (WITH) to count per ticket type first, then sum per event; round(numeric, 1)
-- Rules:    BR-M3 (sell-through = active tickets ÷ quantity, as a % with 1 decimal;
--           for an event, both sides are summed over its ticket types)
-- Input:    organizer_id 2
-- Output:   title, active, quantity, sell_through_pct
-- Filter:   events.organizer_id = 2
-- Sort:     sell_through_pct DESC, title
-- Steps:    1. CTE per_type: one row per ticket type with quantity and its active-ticket count
--           2. join to events, GROUP BY event, sum both, then divide
-- Watch:    don't sum quantity after joining tickets: each ticket row repeats its type's quantity.
--           That's why the CTE counts per type first.
--           100.0 * ..., not 100 * ...: integer ÷ integer truncates
-- Expected: 5 rows
--             Design Talks              74 / 143  51.7
--             [Edge] Sold Out Rooftop    5 /  15  33.3
--             Street Food Fair          20 /  90  22.2
--             Live Jazz Night           11 /  63  17.5
--             Stand-up Comedy           17 / 275   6.2
-- Run on a fresh run_all.sql.

SET search_path TO eventbrite;

