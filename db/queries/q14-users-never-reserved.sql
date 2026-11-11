-- Q14 · platform
-- Question: Which registered users have never made a reservation? (a marketing list)
-- Concept:  anti-join: NOT EXISTS vs LEFT JOIN ... WHERE right side IS NULL
-- Rules:    BR-U6, D9 (leave anonymized users out: deleted_at IS NULL), BR-M5 (the other end of repeat attendees)
-- Input:    none
-- Output:   query A: never_reserved (one number)
--           query B: user_id, full_name, created_at   (the list)
-- Filter:   users.deleted_at IS NULL AND no row in reservations for that user
-- Sort:     B: user_id
-- Expected: A: 183 · B: 183 rows, the first user_id is 154
-- Verify:   write B twice and compare; 0 rows means both agree:
--             version A: WHERE NOT EXISTS (SELECT 1 FROM reservations r WHERE r.user_id = u.user_id)
--             version B: LEFT JOIN reservations r USING (user_id) WHERE r.reservation_id IS NULL
--             (A EXCEPT B) UNION ALL (B EXCEPT A);   → expect 0 rows
-- Watch:    NOT IN (SELECT user_id FROM ...) also works here, but returns nothing at all if the
--           subquery ever yields a NULL. NOT EXISTS doesn't have that trap.
-- Run on a fresh run_all.sql.

SET search_path TO eventbrite;

-- Query A · how many users never reserved → 183
SELECT COUNT(*) AS never_reserved
FROM users u
WHERE u.deleted_at IS NULL
  AND NOT EXISTS (SELECT 1 FROM reservations r
                  WHERE r.user_id = u.user_id);


-- Query B · the list → 183 rows, first user_id 154
SELECT u.user_id, u.full_name, u.created_at
FROM users u
WHERE u.deleted_at IS NULL
  AND NOT EXISTS (SELECT 1 FROM reservations r
                  WHERE r.user_id = u.user_id)
ORDER BY u.user_id;


-- Verify 
WITH version_a AS (
    SELECT u.user_id
    FROM users u
    WHERE u.deleted_at IS NULL
      AND NOT EXISTS (SELECT 1 FROM reservations r
                      WHERE r.user_id = u.user_id)
),
version_b AS (
    SELECT u.user_id
    FROM users u
    LEFT JOIN reservations r ON r.user_id = u.user_id
    WHERE u.deleted_at IS NULL
      AND r.reservation_id IS NULL
)
(SELECT user_id FROM version_a EXCEPT SELECT user_id FROM version_b)
UNION ALL
(SELECT user_id FROM version_b EXCEPT SELECT user_id FROM version_a);