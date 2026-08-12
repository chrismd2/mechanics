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
| GET | `/pricing` | Suggest flow starts with VIN (`?manual=1` for the full form); shows top 3 recent searches |
| GET | `/pricing/queries` | Searchable / filterable list of the user’s recent searches (collapsible filter block) |
| DELETE | `/pricing/queries/:id` | Dismiss (delete) a recent suggestion query owned by the user |
| POST | `/pricing/from-vin` | Check VIN; suggest when complete, otherwise open the manual form |
| POST | `/pricing/suggest` | Run suggestion from the manual form or a recent-search re-run; show result and persist query |

Signed-in users open these from the header **Tools** drawer (pricing links only when the user has `pricing_user`).

## Vehicle market price submission

`pricing_user`s grow the dataset the agent queries. Flow:

1. Submit a listing/sale **URL**.
2. If that `source_url` already exists, fail with an error flash and stay on the URL entry view (no duplicate, no manual form).
3. Otherwise fetch the page and ask the pricing agent to extract vehicle fields.
4. If extraction is complete, save immediately.
5. If not, show a warning flash and the manual form (prefilled when possible) and save after review.

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

Stored in `vehicle_market_prices` as a **shared** dataset (no `user_id`). Any `pricing_user` can add rows; all pricing users query the same pool.

## Price suggestion request

VIN-first flow (mirrors market-price URL entry):

1. Submit a **VIN** (miles optional; **defaults to `0`** when blank).
2. `VinChecker` looks up a matching stored market price, then falls back to NHTSA vPIC decode.
3. If make/model/year are present (miles defaulted to `0` when missing), run the suggestion immediately.
4. If the check fails or make/model/year are still missing, show a warning flash and the manual form (prefilled when possible).

| Field | Required | Notes |
|-------|----------|-------|
| `vin` | for VIN step | 17-character VIN |
| `make` | yes (manual / ready) | |
| `model` | yes | |
| `year` | yes | |
| `miles` | yes | defaults to `0` when blank on VIN or suggest |

Every successful suggest attempt is stored in `vehicle_price_queries` for the current user (even when suggestions are nil / insufficient data), including suggested competitive and expected-minimum cents when available, match count, and a short agent summary when present. The same user + vehicle (make, model, year, miles, VIN) updates the existing row instead of creating a duplicate.

## Recent searches

- Successful suggests appear as **recent searches** for that user.
- The suggestion page shows the **top 3** beside the form; the column header links to `/pricing/queries`.
- Each of the top 3 is a button that POSTs the same vehicle fields to `/pricing/suggest` (refreshes the existing query snapshot).
- `/pricing/queries` lists all of the user’s queries and supports filters: free-text `q` (make/model/VIN), plus `make`, `model`, `year`, and `vin`.
- Duplicate searches for the same vehicle are not stored twice; re-runs update the existing row and bump it to the top of recent.
- Users can **Dismiss** a search from the sidebar or history page to delete it.
- Miles and money on `/pricing/queries` (and suggestion results) use grouped digits (e.g. `41,921` miles, `$2,600.00`).

## Pricing agent

The agent uses local tool calling against `vehicle_market_prices`. Provider credentials and model are read from environment (see deployment config); the client is isolated so the backend can change without changing this feature’s contract.

### Tools

| Tool | Purpose |
|------|---------|
| `search_vehicle_market_prices` | Filter by make, model, year range, miles band, optional `price_type` (`listing`, `sale`, or both). Returns ids and vehicle fields. |
| `get_vehicle_market_price_details` | Given ids, return `price_cents`, `currency`, `price_type`, year, miles. |

The agent should use sales for floor / expected-minimum context and listings for asking / competitive context, then return **competitive** and **expected minimum** prices in cents. On missing credentials, HTTP failure, or empty results: persist the query with nil suggestions and show a clear UI message.

### Seed matches (heuristic / match_count)

Before (and alongside) tool calling, the agent seeds comps from `vehicle_market_prices`:

1. Same make/model, year ±1, miles ±20%
2. If that band is empty, widen by dropping the miles filter (still make/model, year ±1)
3. If a VIN is present, also include any rows with that VIN (any miles)

This matters when VIN decode fills make/model/year but the user’s miles differ from stored comps, and when the LLM is unavailable so the heuristic fallback must use those seeds.

## Context API (for tests / seeds)

- `Pricing.create_market_price/2` — create a shared listing/sale market price (`pricing_user` gates the controller; row has no owner)
- `Pricing.import_market_price_from_url/2` — URL lookup → agent extract → save or `{:needs_form, attrs}`
- `Pricing.lookup_vehicle_from_vin/2` — VIN check → `{:ok, :ready, attrs}` or `{:needs_form, attrs}` (blank miles → `0`)
- `Pricing.get_market_price_by_source_url/1` — find an existing row by URL
- `Pricing.list_market_prices/1` — filter/search (backing `search_vehicle_market_prices`; supports `vin` as well as make/model/year/miles; no per-user ownership filter)
- `Pricing.get_market_price_details/1` — details for ids (backing `get_vehicle_market_price_details`)
- `Pricing.suggest_prices/2` — run agent for a user + vehicle attrs; upsert `vehicle_price_query` (no duplicates per user/vehicle)
- `Pricing.list_queries/2` — list a user’s queries (`limit:`, `filters:` with `q` / make / model / year / vin)
- `Pricing.delete_query/2` — dismiss a query owned by the user
- `Accounts.add_pricing_user_role/1` — grant role

## Out of scope (v1)

- JSON API
- Wiring into service listing create/edit
- Self-service “become pricing_user” UI
