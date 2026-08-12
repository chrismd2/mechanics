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
| POST | `/pricing/queries/:id/similar/:market_price_id/dismiss` | Dismiss a similar market-price row on a nil-suggestion result; refill top 3 |

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
| `zipcode` | yes | US ZIP; defaults to `00000` when blank; existing rows backfilled to `00000` |
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
| `make` | yes (manual / ready) | used as suggest / similar search input (case-insensitive) |
| `model` | yes | used as suggest / similar search input (case-insensitive) |
| `year` | no | blank → `0` (unspecified); when unset, suggestion is a **best guess** from make/model comps (no LLM); when set, seeds/similar prefer nearby years |
| `miles` | no | defaults to `0` when blank on VIN or suggest |
| `zipcode` | yes | defaults to `00000` when blank |

Every successful suggest attempt is stored in `vehicle_price_queries` for the current user (even when suggestions are nil / insufficient data), including suggested competitive and expected-minimum cents when available, match count, and a short agent summary when present. The same user + vehicle (make, model, year, miles, VIN, zipcode) updates the existing row instead of creating a duplicate.

### Similar market prices (when no price suggestion)

When **both** competitive and expected-minimum are nil, **or** when year was unspecified (best-guess search), the suggestion result lists matching comps:

- Nil prices: “I can't suggest a price, but here are some that are similar.”
- Best guess (no year): “Matching market prices (by year):” under the aggregated best-guess competitive/minimum

It lists the **top 3** similar rows from `vehicle_market_prices`. Make/model matching uses **alphanumeric tokens**: split on whitespace, strip non `[a-z0-9]` from each token, and match when either token set contains the other (so `f450` matches `F-450` / `F450 King Ranch`, and `f450 king ranch` matches base `F-450`, but `f450` does not match `f-4500` inside “space nut f-4500 deluxe”). Prefer year ±2 when year is set, otherwise any year; no miles band. Each row shows **year**, make, model, miles, and price, and has **Dismiss** (`POST /pricing/queries/:id/similar/:market_price_id/dismiss`). Dismissed ids are stored on that query as `dismissed_similar_ids`; the list refills from the next similar match so up to three remain until the pool is exhausted. Re-running suggest for the same vehicle keeps prior dismissals.

The same token matching applies to `list_market_prices` make/model filters (agent seeds / tools), so year-banded comps also treat `F450` and `F-450` as the same model.

## Recent searches

- Successful suggests appear as **recent searches** for that user.
- The suggestion page shows the **top 3** beside the form; the column header links to `/pricing/queries`.
- Each of the top 3 is a button that POSTs the same vehicle fields to `/pricing/suggest` (refreshes the existing query snapshot).
- `/pricing/queries` lists all of the user’s queries and supports filters: free-text `q` (make/model/VIN), plus `make`, `model`, `year`, and `vin`.
- Duplicate searches for the same vehicle are not stored twice; re-runs update the existing row and bump it to the top of recent.
- Users can **Dismiss** a search from the sidebar or history page to delete it.
- Miles and money on `/pricing/queries` (and suggestion results) use grouped digits (e.g. `41,921` miles, `$2,600.00`).

## Pricing agent

The agent uses local tool calling against `vehicle_market_prices`. Provider credentials and model are read from environment; the client is isolated so the backend can change without changing this feature’s contract.

### LLM environment

The client talks to any **OpenAI-compatible** `/chat/completions` host. Provider is chosen only by these env vars (or equivalent opts in tests):

| Variable | Required | Default | Notes |
|----------|----------|---------|-------|
| `PRICING_LLM_API_KEY` | yes (for LLM) | — | Without it, suggest/extract fall back to heuristics / manual form |
| `PRICING_LLM_MODEL` | no | `llama-3.3-70b-versatile` | Model id for the chosen provider (must support tool calling for suggestions) |
| `PRICING_LLM_BASE_URL` | no | `https://api.groq.com/openai/v1` | Base URL ending before `/chat/completions` |

Examples: Groq (`https://api.groq.com/openai/v1`), OpenAI (`https://api.openai.com/v1`), or any other compatible gateway — set key, model, and base URL together.

**Local Docker** (`christenson_server_host`): set `PRICING_LLM_API_KEY` (and optionally model/base URL) in `.env-local-docker` (compose `--env-file`). The `mechanics` service passes them through in `docker-compose.yml`. Recreate the container after changing env (`make down mechanics` then `make up mechanics`, or equivalent).

**Prod**: set the same `PRICING_LLM_*` vars in the host env file used for compose, then recreate `mechanics`.

### Tools

| Tool | Purpose |
|------|---------|
| `search_vehicle_market_prices` | Filter by make, model, year range, miles band, optional `price_type` (`listing`, `sale`, or both). Returns ids and vehicle fields. |
| `get_vehicle_market_price_details` | Given ids, return `price_cents`, `currency`, `price_type`, year, miles. |

The agent should use sales for floor / expected-minimum context and listings for asking / competitive context, then return **competitive** and **expected minimum** prices in cents.

**LLM unavailable** (missing/blank `PRICING_LLM_API_KEY`, invalid key / non-2xx, transport failure, or raised HTTP client error): fall back to the percentile **heuristic** over seed comps. Nil competitive/minimum only when there are no seed matches. The UI summary should stay human-readable (not raw model JSON).

### Seed matches (heuristic / match_count)

Before (and alongside) tool calling, the agent seeds comps from `vehicle_market_prices`:

1. If year is unspecified (`0` / blank): make/model **contains** match (up to 50 rows) → percentile **best guess** (skip LLM); summary notes year was not specified
2. Otherwise: same make/model, year ±1; apply miles ±20% only when miles is non-zero (blank miles skips the miles band)
3. If that band is empty, widen by dropping the miles filter (still make/model, year ±1)
4. If a VIN is present, also include any rows with that VIN (any miles)
5. If the LLM returns null prices but seed comps exist, fall back to the percentile heuristic so year-specific searches still get competitive/minimum numbers

This matters when VIN decode fills make/model/year but the user’s miles differ from stored comps, when the user searches make/model only, and when the LLM is unavailable so the heuristic fallback must use those seeds.

## Context API (for tests / seeds)

- `Pricing.create_market_price/2` — create a shared listing/sale market price (`pricing_user` gates the controller; row has no owner)
- `Pricing.import_market_price_from_url/2` — URL lookup → agent extract → save or `{:needs_form, attrs}`
- `Pricing.lookup_vehicle_from_vin/2` — VIN check → `{:ok, :ready, attrs}` or `{:needs_form, attrs}` (blank miles → `0`)
- `Pricing.get_market_price_by_source_url/1` — find an existing row by URL
- `Pricing.list_market_prices/1` — filter/search (backing `search_vehicle_market_prices`; supports `vin` as well as make/model/year/miles; no per-user ownership filter)
- `Pricing.get_market_price_details/1` — details for ids (backing `get_vehicle_market_price_details`)
- `Pricing.suggest_prices/2` — run agent for a user + vehicle attrs; upsert `vehicle_price_query` (no duplicates per user/vehicle; preserves `dismissed_similar_ids`)
- `Pricing.list_similar_market_prices/2` — looser comps for nil-suggestion / best-guess UI (`limit:`, `exclude_ids:`; alphanumeric token make/model match, including trim variants)
- `Pricing.normalize_vehicle_key/1` — downcase + strip non-alphanumerics for one token
- `Pricing.normalize_vehicle_tokens/1` — whitespace-split then normalize each token
- `Pricing.dismiss_similar_market_price/3` — append a market-price id to a query’s `dismissed_similar_ids` (owner-only)
- `Pricing.list_queries/2` — list a user’s queries (`limit:`, `filters:` with `q` / make / model / year / vin)
- `Pricing.delete_query/2` — dismiss a query owned by the user
- `Accounts.add_pricing_user_role/1` — grant role

## Out of scope (v1)

- JSON API
- Wiring into service listing create/edit
- Self-service “become pricing_user” UI
