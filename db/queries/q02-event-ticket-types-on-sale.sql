-- Q02 · attendee
-- Question: On an event's page, which ticket types does it have, when is each one on sale, and can I buy it right now?
-- Concept:  COALESCE for defaults resolved at read time; a boolean expression as a column
-- Rules:    BR-T6, D6 (NULL sales_start = published_at, NULL sales_end = starts_at),
--           BR-T9 (off_sale_at), BR-T8 (shown in position order)
-- Input:    event_id 121 ('[Edge] Sold Out Rooftop')
-- Output:   position, name, sales_open, sales_close, on_sale_now
--           sales_open  = COALESCE(sales_start, events.published_at)
--           sales_close = COALESCE(sales_end, events.starts_at)
--           on_sale_now = sales_open <= now() AND sales_close > now()
--                         AND (off_sale_at IS NULL OR off_sale_at > now())
--           (same window as reserve_tickets(): start inclusive, end exclusive)
-- Sort:     position
-- Expected: 2 rows · 1 'General', 2 'VIP' · both on_sale_now = true
--           sales_open = the event's published_at (seed time), sales_close = its starts_at
--           (on_sale_now says the window is open, not that tickets are left: General is sold out, see Q07)
-- Run on a fresh run_all.sql.

SET search_path TO eventbrite;

SELECT tt.position,
        tt.name,
        COALESCE(tt.sales_start, e.published_at) AS sales_open,
        COALESCE(tt.sales_end, e.starts_at) AS sales_close,
        (COALESCE(tt.sales_start, e.published_at) <= now()
         AND COALESCE(tt.sales_end, e.starts_at) > now()
         AND (tt.off_sale_at IS NULL OR tt.off_sale_at > now())) AS on_sale_now
FROM ticket_types tt
JOIN events e USING (event_id)
WHERE e.event_id = 121
ORDER BY tt.position; 