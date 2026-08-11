# Vehicle pricing suggestions

Browser tool for users with the `pricing_user` role. They submit observed vehicle market prices (asking listings or completed sales) and request competitive / expected-minimum price suggestions. Suggestions are produced by a pricing agent that calls local tools against those stored market prices in Postgres. The LLM provider behind the agent is configured at runtime and is intended to be swappable.

## Role

| Detail | Value |
|--------|-------|
| Role name | `pricing_user` |
| Grant | `Accounts.add_pricing_user_role/1` (idempotent; no self-service UI in v1) |
| Gate | Controllers require `"pricing_user" in current_user.roles`; others redirect home |

Valid roles also remain `mechanic` and `customer`. A user may hold `pricing_user` alongside other roles.

## Routes (browser HTML)

| Method | Path | Description |
|--------|------|-------------|
| GET | `/pricing/market-prices/new` | Start with a listing/sale URL |
| POST | `/pricing/market-prices/from-url` | Look up URL, try agent extraction, save or fall back to form |
| POST | `/pricing/market-prices` | Manual save of vehicle market price (`listing` or `sale`) |
| GET | `/pricing` | Suggest form (vin / make / model / year / miles) |
| POST | `/pricing/suggest` | Run suggestion; show result and persist query |

Signed-in users open these from the header **Tools** drawer (pricing links only when the user has `pricing_user`).

## Vehicle market price submission

`pricing_user`s grow the dataset the agent queries. Flow:

1. Submit a listing/sale **URL**.
2. If that `source_url` already exists, stop (no duplicate).
3. Otherwise fetch the page and ask the pricing agent to extract vehicle fields.
4. If extraction is complete, save immediately.
5. If not, show the manual form (prefilled when possible) and save after review.

Each row is one observed asking price or sold price for a vehicle. **`source_url` is always stored.**

| Field | Required | Notes |
|-------|----------|-------|
| `source_url` | yes | http(s) listing/sale page; unique |
| `vin` | no | |
| `make` | yes | |
| `model` | yes | |
| `year` | yes | integer |
| `miles` | yes | integer |
| `price` / `price_cents` | yes | stored as integer cents |
| `currency` | no | default `USD` |
| `price_type` | yes | `listing` (asking) or `sale` (sold) |
| `notes` | no | optional free text / source |

Stored in `vehicle_market_prices` with `user_id` of the submitter.

## Price suggestion request

| Field | Required | Notes |
|-------|----------|-------|
| `vin` | no | |
| `make` | yes | |
| `model` | yes | |
| `year` | yes | |
| `miles` | yes | |

Every attempt is stored in `vehicle_price_queries` (even when suggestions are nil / insufficient data), including suggested competitive and expected-minimum cents when available, match count, and a short agent summary when present.

## Pricing agent

The agent uses local tool calling against `vehicle_market_prices`. Provider credentials and model are read from environment (see deployment config); the client is isolated so the backend can change without changing this feature’s contract.

### Tools

| Tool | Purpose |
|------|---------|
| `search_vehicle_market_prices` | Filter by make, model, year range, miles band, optional `price_type` (`listing`, `sale`, or both). Returns ids and vehicle fields. |
| `get_vehicle_market_price_details` | Given ids, return `price_cents`, `currency`, `price_type`, year, miles. |

The agent should use sales for floor / expected-minimum context and listings for asking / competitive context, then return **competitive** and **expected minimum** prices in cents. On missing credentials, HTTP failure, or empty results: persist the query with nil suggestions and show a clear UI message.

## Context API (for tests / seeds)

- `Pricing.create_market_price/2` — create a listing or sale market price for a user
- `Pricing.import_market_price_from_url/2` — URL lookup → agent extract → save or `{:needs_form, attrs}`
- `Pricing.get_market_price_by_source_url/1` — find an existing row by URL
- `Pricing.list_market_prices/1` — filter/search (backing `search_vehicle_market_prices`)
- `Pricing.get_market_price_details/1` — details for ids (backing `get_vehicle_market_price_details`)
- `Pricing.suggest_prices/2` — run agent for a user + vehicle attrs; persist `vehicle_price_query`
- `Accounts.add_pricing_user_role/1` — grant role

## Out of scope (v1)

- External VIN-decode APIs
- JSON API
- Wiring into service listing create/edit
- Self-service “become pricing_user” UI
