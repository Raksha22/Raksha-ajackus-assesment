# Task 2 — Before / after proof (orders IDOR, REVIEW.md issue #1)

**Fix:** `Api::V1::OrdersController` now uses `current_user.orders` for `index`, `show`, and `cancel`. Another user’s id returns **404** with `{"error":"Not found"}`.

**Prerequisites:** API on `http://127.0.0.1:3000`, `rails db:seed` loaded (users `vikram@example.com` and `ananya@example.com`). Order ids differ per seed run; use the steps below.

---

## Same commands

```bash
TOKEN=$(curl -s -X POST http://127.0.0.1:3000/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"vikram@example.com","password":"password123"}' \
  | ruby -rjson -e 'puts JSON.parse(STDIN.read)["token"]')

# 1) List orders (should only ever be Vikram’s after the fix)
curl -s "http://127.0.0.1:3000/api/v1/orders" \
  -H "Authorization: Bearer $TOKEN"

# 2) Resolve Ananya’s order id, then fetch it as Vikram (should 404 after the fix)
ANANYA_ORDER_ID=$(bundle exec rails runner \
  "puts Order.joins(:user).where(users: { email: 'ananya@example.com' }).pick(:id)")

curl -s "http://127.0.0.1:3000/api/v1/orders/${ANANYA_ORDER_ID}" \
  -H "Authorization: Bearer $TOKEN"
```

---

## Before the fix (vulnerable)

Vikram (`attendee2` in seeds) only **owns** order **EVN-E5F6G7H8**, but **`GET /api/v1/orders`** returned **every** order, including Ananya’s **EVN-A1B2C3D4** and others:

```json
[
  {"id":19,"confirmation_number":"EVN-M3N4O5P6","event":"RailsConf India 2025", ...},
  {"id":18,"confirmation_number":"EVN-I9J0K1L2","event":"Advanced PostgreSQL Workshop", ...},
  {"id":17,"confirmation_number":"EVN-E5F6G7H8","event":"RailsConf India 2025", ...},
  {"id":16,"confirmation_number":"EVN-A1B2C3D4","event":"Mumbai Indie Music Festival 2025", ...}
]
```

**`GET /api/v1/orders/16`** as Vikram returned **200** with Ananya’s order body, including **payment.provider_reference** (full PII/financial leakage).

---

## After the fix (correct)

**`GET /api/v1/orders`** — only Vikram’s order(s):

```json
[
  {
    "id":17,
    "confirmation_number":"EVN-E5F6G7H8",
    "event":"RailsConf India 2025",
    "status":"confirmed",
    "total_amount":4999.0,
    "items_count":1,
    "created_at":"2026-04-05T09:45:55.002Z"
  }
]
```

**`GET /api/v1/orders/<ananya_order_id>`** as Vikram:

```json
{"error":"Not found"}
```

HTTP status **404** (not **200**).

**Malformed id** (e.g. `GET /api/v1/orders/not-a-number`) also returns **404** with `{"error":"Not found"}` so the API does not raise a database cast error.

---

*Ids and timestamps reflect one seed run; rerun the resolver command if ids change.*
