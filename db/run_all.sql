-- Rebuilds the eventbrite schema from scratch. Re-runnable.
--   psql -v ON_ERROR_STOP=1 -d eventbrite_lab -f db/run_all.sql   (from the repo root)
\set ON_ERROR_STOP on
\echo '== reset'
DROP SCHEMA IF EXISTS eventbrite CASCADE;
CREATE SCHEMA eventbrite;
SET search_path TO eventbrite;

\echo '== schema'
\ir schema.sql
\echo '== seed'
\ir seed.sql
\echo '== done'
