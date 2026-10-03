# Guide: understanding the business from the rules doc alone

How to go from [db/docs/01-business-rules.md](db/docs/01-business-rules.md) to design decisions, with no prior knowledge of how ticketing platforms work.

---

## 1. The rules doc is all the business knowledge you need

Sections 1–3 are the spec. They're written so you don't need to have worked at Eventbrite.

| Section                     | What it gives you                                                     |
| --------------------------- | --------------------------------------------------------------------- |
| 1. Overview + glossary      | The things that exist: users, events, ticket types, reservations, tickets |
| 2. Actors                   | Who does what                                                         |
| 3. Rules                    | What must always be true                                              |
| 4. Decisions                | How the database will model and enforce the rules (your design)       |
| 5. Open questions           | Gaps you found and haven't resolved                                   |

If something isn't in the doc, it's either out of scope for v0 or a gap. **A gap goes in section 5 (Open questions).** You don't invent it, and you don't have to know it already.

Rules (section 3) say **what** must happen. They're fixed. Decisions (section 4) say **how** the database does it. They're yours.

---

## 2. Walk through a story

The fastest way to understand a domain: follow one realistic story from start to finish and **write down the rows that appear or change at each step.**

| Step | What happens                                   | Rows that exist / change                                  | Rules hit        |
| ---- | ---------------------------------------------- | --------------------------------------------------------- | ---------------- |
| 1    | Ana signs up                                   | 1 user                                                    | BR-U1–U3         |
| 2    | Ana becomes organizer "Bogotá Jazz"            | organizer data for Ana                                    | BR-U4            |
| 3    | Ana creates a draft concert                    | 1 event, status `draft`, no category yet                  | BR-E2, E5, C2    |
| 4    | Ana adds General (100) and VIP (20)            | 2 ticket types                                            | BR-T1, T2, T7    |
| 5    | Ana publishes                                  | event → `published`, `published_at` is set               | BR-E6            |
| 6    | Luis reserves 2 General + 1 VIP                | 1 reservation, 3 tickets with codes                       | BR-R1, R6, K1–K2 |
| 7    | Luis cancels                                   | reservation and its 3 tickets → `cancelled`               | BR-R5, K3        |
| 8    | Ana cancels the event                          | event → `cancelled`, every remaining ticket → `cancelled` | BR-E9            |

At each step, ask **"where does this data live?"** The answers are your decisions:

- Step 2: where does "organizer" live? → **D1**
- Step 6: is it one row or three? What does the QR show? → **D2**
- Step 6 again: how do we know VIP has 19 left? → **D4**
- Step 8: what happens to Luis's tickets? → **D5**

### Then try the edge cases

Each edge case points to another decision:

| Edge case                                                  | Decision |
| ---------------------------------------------------------- | -------- |
| Two people buy the last VIP ticket at the same instant     | D4       |
| A Madrid event viewed from Bogotá; a DST change mid-event  | D7       |
| Someone tries ticket code `…0042` after seeing `…0041`     | D8       |
| Ana deletes her account after selling tickets              | D9       |
| Luis tries to reserve after the sales window closed        | D6       |
| In v1, the price changes after Luis reserved               | D3       |

---

## 3. Sketching tables is part of answering

You don't need a finished schema to answer a decision. You're allowed to sketch tables while deciding. The order **rules → decisions → ERD → `schema.sql`** is about what you **finalize** first, not what you're allowed to think about.

```
read a rule → sketch 2 options as tables → check them against the rules → pick → write the decision
```

The sketches are rough drafts of the ERD. Keep them on paper or in a scratch file, and keep them messy. [db/docs/02-design.md](db/docs/02-design.md) gets the clean version.

### Worked example: D1 (organizer: a role or an entity?)

1. **Write each option as a tiny table sketch.**

   ```
   Option A                          Option B
   users(id, email, is_organizer,    users(id, email, ...)
         organizer_name NULL)        organizers(user_id PK→users, organizer_name)
   events(id, organizer_id → users)  events(id, organizer_id → organizers)
   ```

2. **Check each sketch against the rules listed under the question.**

   - **BR-U4: only enabled organizers create events.**
     - Option A: `organizer_id → users` accepts any user, so the rule needs a trigger.
     - Option B: the foreign key guarantees it on its own.
   - **BR-U4: an organizer must have a public name.**
     - Option A: `organizer_name` must be nullable, plus a `CHECK` tying it to the flag.
     - Option B: the column is just `NOT NULL`.
   - **BR-U5: one person can be both.** Both options handle this.

3. **Pick the option that guarantees the most with the fewest moving parts.** Option B wins, and that comparison is the "Why".

---

## 4. How decision questions are made (so you can write your own)

**A decision question appears wherever a rule says *what* must happen but there's more than one reasonable way to build it, each with a cost.**

For any rule, ask:

1. **Can this be a column, a separate table, or calculated when needed?** (D1, D2, D4)
2. **Can a `CHECK` enforce it, or does it involve other rows, other tables, or the current time?** (D5, D6)
3. **What happens if two users do this at the same instant?** (D4)
4. **What happens to it when something it depends on is edited, cancelled or deleted?** (D5, D9)
5. **Will someone see it in a URL or QR code?** (D8)
6. **Is it a known trap?** Money in `float` (D3), times without a time zone (D7), sequential public ids (D8), deleting history (D9).

If a question has only one sensible answer, it's not a decision. Just write the rule.

---

## 5. If a question feels impossible

You're probably missing a **concept**, not business knowledge. To list the options, you need to know the tools:

| Decision | Concept to know                                                          |
| -------- | ------------------------------------------------------------------------ |
| D1, D9   | Foreign keys, 1:1 tables, `ON DELETE` options                            |
| D2       | Header/detail tables (order → items), what a row represents              |
| D3       | `NUMERIC` vs `float` precision                                           |
| D4       | Derived vs stored data, race conditions, `SELECT … FOR UPDATE`           |
| D5, D6   | What `CHECK` can't do (other rows, `now()`), triggers                    |
| D7       | `TIMESTAMP` vs `TIMESTAMPTZ`, IANA time zones                            |
| D8       | Identity keys vs UUIDs, why sequential ids leak information              |

Study the concept, then come back to the question.

---

## 6. It's iterative

You won't get every decision right before writing SQL. Writing the ERD or schema often shows a decision was wrong. When that happens, go back, change the decision and its "Why", and continue. That's expected, and it's the same rule as in [ADR-0001](docs/adr/0001-restart-database-first.md): fix the design, don't restart.

For intuition, browsing eventbrite.com helps. Where it differs from the rules doc, the doc wins, because this project's scope is smaller.
