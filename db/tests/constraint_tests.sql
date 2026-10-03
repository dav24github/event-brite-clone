-- =============================================================================
-- constraint_tests.sql · one deliberate violation per constraint
-- Every statement here must FAIL. Run WITHOUT ON_ERROR_STOP:
--   psql -d eventbrite_lab -f db/tests/constraint_tests.sql
-- Format:
--   -- T1 · BR-?? · <what it violates>
--   -- expect: ERROR <constraint_name>
--   INSERT ...;
-- =============================================================================

