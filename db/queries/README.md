# Queries

15 business questions: organizers, attendees and the platform. One file per question, e.g. `q01-browse-upcoming-events.sql`.

Run each one on a fresh `run_all.sql`, not after `tests/constraint_tests.sql` (the tests change some rows). Every file's `Expected:` line was checked against that seed.

Header for each file:

```sql
-- Q01 · <audience: organizer | attendee | platform>
-- Question: 
-- Concept:  
-- Rules:    BR-..
-- Input:    the fixed ids or values to use
-- Output:   the columns, in order
-- Filter / Sort
-- Expected: <row count / key values on the seed data>
-- Verify:   (Q07, Q11, Q14) two versions compared with (A EXCEPT B) UNION ALL (B EXCEPT A)
```

| # | Audience | Question | Concept | Rules | File |
|---|---|---|---|---|---|
| Q01 | attendee | Browse upcoming events by category, with tickets left | JOIN, LEFT JOIN, GROUP BY | BR-E7, BR-M2 | [q01](q01-browse-upcoming-events.sql) |
| Q02 | attendee | An event's ticket types and whether each is on sale now | COALESCE defaults | BR-T6, BR-T9, D6 | [q02](q02-event-ticket-types-on-sale.sql) |
| Q03 | attendee | My tickets, in the event's local time | AT TIME ZONE | BR-K5, BR-E4 | [q03](q03-my-tickets.sql) |
| Q04 | attendee | Meeting link only for active ticket holders | EXISTS | BR-L3 | [q04](q04-meeting-url-for-ticket-holders.sql) |
| Q05 | organizer | My events, drafts included | filter by owner | BR-E7, BR-E1 | [q05](q05-organizer-my-events.sql) |
| Q06 | organizer | Tickets reserved per type and per event | count FILTER | BR-M1 | [q06](q06-tickets-reserved.sql) |
| Q07 | organizer | Available and sold out | GREATEST, verify ×2 | BR-M2 | [q07](q07-available-and-sold-out.sql) |
| Q08 | organizer | Sell-through per event | CTE, round | BR-M3 | [q08](q08-sell-through.sql) |
| Q09 | organizer | Daily reservations in the event's time zone | GROUP BY expression | BR-M4, D7 | [q09](q09-daily-reservations.sql) |
| Q10 | organizer | Attendee list with ticket counts | 3-table join | BR-K5, BR-K3 | [q10](q10-attendee-list.sql) |
| Q11 | platform | Repeat attendees | HAVING, count DISTINCT, verify ×2 | BR-M5 | [q11](q11-repeat-attendees.sql) |
| Q12 | platform | Active organizers | EXISTS / NOT EXISTS | BR-M6 | [q12](q12-active-organizers.sql) |
| Q13 | platform | Events per effective status | CASE derived column | BR-E10 | [q13](q13-effective-status.sql) |
| Q14 | platform | Users who never reserved | anti-join, verify ×2 | BR-U6, BR-M5 | [q14](q14-users-never-reserved.sql) |
| Q15 | platform | Cancellation rate per category | FILTER, NULLIF | BR-K3, BR-R5, BR-E9 | [q15](q15-cancellation-rate-by-category.sql) |
