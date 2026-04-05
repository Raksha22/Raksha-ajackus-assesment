# Code review — top 7 issues (by business impact)

Review scope: API controllers, authentication, and related models. Proofs below use the **development** Rails server (e.g. `docker-compose up web`) with **`rails db:seed`** so seeded users exist. Host: `http://127.0.0.1:3000`.

---

## 1. Orders API lists and returns every order (critical IDOR)

| Field | Value |
|--------|--------|
| **Location** | `app/controllers/api/v1/orders_controller.rb` — `index` ~L5–18, `show` ~L21–47, `cancel` ~L80–88 |
| **Category** | Security |
| **Severity** | Critical |

**Description:** `Order.all` in `index` returns the entire order table to any authenticated user. `show` and `cancel` use `Order.find(params[:id])` with no `user_id` check, so one attendee can read another’s confirmation numbers, totals, line items, and **payment provider references**. This is a direct breach of confidentiality and a compliance risk (PCI-adjacent data exposure, depending on what `provider_reference` holds).

**Recommended fix:** Scope all queries to the current user, e.g. `current_user.orders.order(created_at: :desc)` for `index`, and `current_user.orders.find(params[:id])` for `show`/`cancel`. Return `404` (or `403`) when the order is not found for that user. Add request specs that prove user A cannot access user B’s orders.

### Proof (running app)

Log in as **Vikram** (`vikram@example.com` / `password123`) — seeds attach him only to order **EVN-E5F6G7H8**. The API still returns **all four** orders, including **Ananya’s** **EVN-A1B2C3D4**.

```bash
TOKEN=$(curl -s -X POST http://127.0.0.1:3000/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"vikram@example.com","password":"password123"}' \
  | ruby -rjson -e 'puts JSON.parse(STDIN.read)["token"]')

curl -s "http://127.0.0.1:3000/api/v1/orders" \
  -H "Authorization: Bearer $TOKEN"
```

**Observed response (abbreviated):** JSON array containing orders with `confirmation_number` values **`EVN-A1B2C3D4`**, **`EVN-E5F6G7H8`**, **`EVN-I9J0K1L2`**, **`EVN-M3N4O5P6`** — i.e. other users’ orders, not only Vikram’s.

**Show endpoint:** After `db:seed`, order **id `16`** is Ananya’s **EVN-A1B2C3D4** (ids may differ if you re-seed; adjust id from `GET /api/v1/orders` or match `confirmation_number`).

```bash
curl -s "http://127.0.0.1:3000/api/v1/orders/16" \
  -H "Authorization: Bearer $TOKEN"
```

**Observed response (abbreviated):** `{"id":16,"confirmation_number":"EVN-A1B2C3D4",...,"payment":{"status":"completed","provider_reference":"ch_abc123def456"}}` — Vikram can read **Ananya’s** payment reference.

---

## 2. SQL injection in event search (`params[:search]` interpolated into SQL)

| Field | Value |
|--------|--------|
| **Location** | `app/controllers/api/v1/events_controller.rb` ~L9–10 |
| **Category** | Security |
| **Severity** | Critical |

**Description:** The search clause builds a string with `'%#{params[:search]}%'`, so attacker-controlled SQL can break out of the `LIKE` literal and append boolean conditions. Even if exploitation is limited by surrounding scopes, this is a classic injection surface and may enable data exfiltration or denial-of-service depending on the database and query planner.

**Recommended fix:** Use bound parameters, e.g. `events.where("title ILIKE :q OR description ILIKE :q", q: "%#{ActiveRecord::Base.sanitize_sql_like(params[:search])}%")`, or use `ransack`/pg_search with safe APIs. Never interpolate raw user input into SQL fragments.

### Proof (running app)

With seeded data, a **non-matching** search returns **no** upcoming published events; a crafted `search` uses `--` to comment out the rest of the predicate so **`OR 1=1`** matches every row still allowed by `published` + `upcoming`.

```bash
# Benign: no rows (or fewer rows) for a nonsense substring
curl -s -g "http://127.0.0.1:3000/api/v1/events?search=ZZZNO_MATCH_999"
# Observed: []  (empty JSON array)

# Malicious: widens predicate to match all scoped events
curl -s -g "http://127.0.0.1:3000/api/v1/events?search=x%27%20OR%201=1--"
# Observed: JSON array of length 4 (all published, upcoming events in seed)
```

The **change in row count** (e.g. **0 → 4**) demonstrates that user input is altering SQL structure, not merely acting as a literal search string.

---

## 3. Unsafe `ORDER BY` from user input (`params[:sort_by]`)

| Field | Value |
|--------|--------|
| **Location** | `app/controllers/api/v1/events_controller.rb` ~L21 |
| **Category** | Security |
| **Severity** | High |

**Description:** `events.order(params[:sort_by] || "starts_at ASC")` passes client-controlled strings into `ORDER BY`. Depending on the ActiveRecord/database version, this can enable SQL injection or at least unstable, user-controlled query plans. Public `index` does not require auth, so the attack surface is unauthenticated.

**Recommended fix:** Whitelist allowed columns and directions, e.g. `ALLOWED = { "date" => "starts_at ASC", "date_desc" => "starts_at DESC" }; events.order(ALLOWED.fetch(params[:sort_by], "starts_at ASC"))`, or use `reorder` with Arel-only expressions.

---

## 4. Clients can inflate “sold” counts via permitted `sold_count`

| Field | Value |
|--------|--------|
| **Location** | `app/controllers/api/v1/ticket_tiers_controller.rb` ~L52–53 (`tier_params`) |
| **Category** | Data integrity |
| **Severity** | High |

**Description:** `sold_count` is permitted in strong parameters. Any authenticated user who can hit tier `create`/`update` (see issue 5) can set `sold_count` arbitrarily, corrupting availability math (`available_quantity` typically depends on `quantity` and `sold_count`) and enabling overselling or fake sellouts.

**Recommended fix:** Remove `:sold_count` from `permit`. Only allow internal code paths (checkout, admin jobs) to change sold counts, ideally via atomic DB updates or a dedicated service.

---

## 5. No check that the current user owns the event for tiers / events mutations

| Field | Value |
|--------|--------|
| **Location** | `app/controllers/api/v1/ticket_tiers_controller.rb` ~L23–47; `app/controllers/api/v1/events_controller.rb` ~L89–103 |
| **Category** | Security / Architecture |
| **Severity** | High |

**Description:** `TicketTier` `create`/`update`/`destroy` load tiers or events by id without verifying `event.user_id == current_user.id` (or admin). Similarly, `EventsController#update` and `#destroy` do not ensure the event belongs to the organizer. A logged-in attendee can destroy or rewrite another organizer’s inventory or events if they guess or enumerate ids.

**Recommended fix:** Authorize with Pundit/Action Policy or manual guards: `authorize event, :manage?` where `event` is loaded and ownership checked. For nested tiers, `event = current_user.events.find(params[:event_id])`.

---

## 6. Registration allows clients to set `role` (privilege escalation)

| Field | Value |
|--------|--------|
| **Location** | `app/controllers/api/v1/auth_controller.rb` ~L34–35 |
| **Category** | Security |
| **Severity** | High |

**Description:** `register_params` permits `:role`. A new signup can pass `"role":"admin"` (or `"organizer"`) in the JSON body and elevate privileges without an admin workflow.

**Recommended fix:** Do not permit `role` on public registration; default to `"attendee"` in the model or controller. Only staff-facing endpoints may change roles.

---

## 7. N+1 queries on public events index (and order item counts)

| Field | Value |
|--------|--------|
| **Location** | `app/controllers/api/v1/events_controller.rb` ~L23–44; `app/controllers/api/v1/orders_controller.rb` ~L15 (`order_items.count`) |
| **Category** | Performance |
| **Severity** | Medium |

**Description:** `events.map` touches `event.user`, `total_tickets` / `total_sold` (aggregate queries per event), and `ticket_tiers` per row, producing many repeated SQL statements under load. `orders#index` calls `order_items.count` per order, another classic N+1. Under traffic this increases latency and database cost on hot endpoints.

**Recommended fix:** Use `Event.published.upcoming.includes(:user, :ticket_tiers)` and precompute or select aggregates in a single query where possible. For orders, use `includes(:order_items)` and `size` on loaded associations or a counter cache / subselect.

### Proof (server logs)

One unauthenticated `GET /api/v1/events` triggers **multiple** `User Load` and `TicketTier` queries (pattern repeats per event):

```bash
# Truncate log, issue one request, inspect SQL (development log)
truncate -s 0 log/development.log
curl -s "http://127.0.0.1:3000/api/v1/events" > /dev/null
grep -E "User Load|TicketTier" log/development.log | head -15
```

**Observed pattern (excerpt):** repeated lines such as `User Load ... WHERE "users"."id" = $1`, `TicketTier Sum ... WHERE "ticket_tiers"."event_id" = $1`, `TicketTier Load ... WHERE "ticket_tiers"."event_id" = $1` for **different** `event_id` values — one cluster per event instead of a constant small number of queries with eager loading.

---

## Summary

| Priority | Issue | Severity |
|----------|--------|----------|
| 1 | Orders: global scope / IDOR on index, show, cancel | Critical |
| 2 | Events search SQL string interpolation | Critical |
| 3 | Events `sort_by` passed to `order()` | High |
| 4 | `sold_count` in tier strong params | High |
| 5 | Missing ownership checks (events / ticket tiers) | High |
| 6 | `role` permitted on registration | High |
| 7 | N+1 on events index and order item counts | Medium |

---

*This document is an assessment artifact; apply fixes in code and add regression tests before production use.*
