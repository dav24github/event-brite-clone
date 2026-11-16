# 05 · Performance: indexes and `EXPLAIN ANALYZE`

<!--
How to fill this file (delete this comment when done):
- One section per pattern, the same six parts each time. Keep each section readable in about a minute.
- Paste only the plan lines that matter (scan nodes, Sort, the top node's time and Buffers), never whole plans.
- Every number comes from labs/05-performance.sql, second run (warm cache).
- Write "why" in your own words: that's the part an interviewer asks about.
-->

How the main access patterns of the Eventbrite database behave at volume, which index each one needs and why, and what the indexes cost. The numbers come from [`labs/05-performance.sql`](../labs/05-performance.sql), run on the volume seed.

## Setup

| | |
|---|---|
| Data | _users · organizers · events · ticket types · reservations · tickets (from seed_volume.sql)_ |
| Load time | _from `\timing`_ |
| PostgreSQL | 18, local, default settings |
| Measured with | `EXPLAIN (ANALYZE, BUFFERS)`, second run (warm cache) |

**How to read the numbers:** *Buffers* counts the 8 KB pages a query touched (`hit` = from memory, `read` = from disk). It's the before/after number I trust most, because time changes from run to run.

## Summary

| # | Pattern | Before | Index / change | After |
|---|---|---|---|---|
| P1 | Browse published, upcoming events | _Seq Scan · N buffers · N ms_ | | |
| P2 | An organizer's events | | | |
| P3 | My tickets | | | |
| P4 | Sales report | | | |
| P5 | Title search | | | |

## P1 · Browse published, upcoming events

**Query:** _Q01, and the page-500 query for pagination_

**Before**
```
(paste the key plan lines)
```

**Why it's slow:** _one or two sentences_

**Index:** _the CREATE INDEX, and why it's partial and in that column order_

**After**
```
```

**Pagination, OFFSET vs keyset:** _rows read for page 500 with each; why keyset stays flat_

**Lesson:** _one line_

## P2 · An organizer's events

**Query:**

**Before** (no index · with `idx_events_organizer`)
```
```

**Why it's slow:**

**Index:**

**After**
```
```

**Column order:** _what happened with (starts_at, organizer_id), and why_

**Lesson:**

## P3 · My tickets

**Query:**

**Before**
```
```

**Why it's slow:**

**Index:** _and the covering-index experiment: Index Only Scan, Heap Fetches, VACUUM_

**After**
```
```

**Lesson:**

## P4 · Sales report

**Query:**

**Before**
```
```

**Why it's slow:** _what the CTE reads before the organizer filter_

**Change:** _the two rewrites, and whether any index was still needed_

**After**
```
```

**Lesson:**

## P5 · Title search

**Query:**

**Before**
```
```

**Why a B-tree can't help:**

**Index:** _pg_trgm GIN_

**After**
```
```

**Common vs rare word:**

**Lesson:**

## Sargable predicates

_The two ways of writing "reservations created yesterday", their plans, and why the expression index on `created_at::date` fails (IMMUTABLE)._

## The write cost of indexes

| Table copy | Indexes | Insert 200,000 rows |
|---|---|---|
| `lab_tickets_bare` | 0 | _ms_ |
| `lab_tickets_idx` | _N_ | _ms_ |

_Unused indexes found with `pg_stat_user_indexes`, and what you did with them._

## Decisions

The indexes added to [`schema.sql`](../schema.sql), and the ones they replaced:

| Index | For | Replaces |
|---|---|---|
| | | |

## Takeaways

_Three to five lines. For example: when the planner is right to ignore an index; why estimated vs actual rows matters; when the fix was the query, not an index._
