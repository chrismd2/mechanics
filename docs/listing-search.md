# Multi-source listing search (for price suggestions)

External auction sources (BidWrangler, Royal Auction) feed the **existing pricing agent tools** used when a `pricing_user` requests a price suggestion. There is no separate listing-search page — the user stays on suggest / VIN / make-model flows.

Craigslist remains an adapter stub only in v1 (no live scrape).

Hits land in **`listing_candidates`** (not `listings`). Digestion imports into `vehicle_market_prices`.

## Roles

| Role | Access |
|------|--------|
| `pricing_user` | Suggest prices; agent tools may query enabled auction sources |
| `admin` | Tools → Admin: tabbed panels for auction sources, Oban jobs, listing candidates |

Grant via `Accounts.add_pricing_user_role/1` and `Accounts.add_admin_role/1` (idempotent; no self-service UI).

## Auction sources

Table `auction_sources` stores managed origins:

| Field | Notes |
|-------|--------|
| `kind` | `bidwrangler`, `royal`, `craigslist`, or `unknown` |
| `base_url` | Origin, e.g. `https://bid.sextonauctioneers.com` |
| `label` | Display name |
| `enabled` | Included in agent search / crawl when true |
| `config` | JSON map (filters, hints, `last_crawl_report`) |
| `last_crawled_at` | Updated by past-auction crawl |

**Suggestions (computed):** distinct origins from recent `vehicle_market_prices.source_url` that are not already stored as sources.

Local Docker uses the **`mechanics`** Postgres DB.

## Listing candidates

Hits from external search during a suggestion tool call (or admin trial search) are upserted into `listing_candidates` (unique `source_url`) for later Oban digestion. Agent tool ids for these rows are `candidate:<uuid>`.

**Auto-pipeline (on each newly inserted candidate):**

1. Enqueue `DigestCandidateWorker` staggered **per `auction_source_id`**: `scheduled_at = max(future digest/crawl jobs for that source) + 30s` (or now).
2. If hit metadata includes an `auction_id` and the source is **Royal**, enqueue `CrawlAuctionLotsWorker` once per `{source, auction_id, query}` (also staggered). That worker re-searches lots **in that auction** with the same query, paginates, and upserts more candidates (which get digests via step 1).

Re-running search for an existing `source_url` updates the candidate but does **not** enqueue another digest. Use Admin Digest or Oban Retry for that.

## How suggestions use external sources

When the pricing agent calls `search_vehicle_market_prices`:

1. Query local `vehicle_market_prices` as before.
2. Also search **enabled** auction sources with `"#{make} #{model}"` (BidWrangler `?query=`, Royal GraphQL `search:{text:}`), up to **5 pages** (page size 25) per source until a short/empty page.
3. Merge local + external rows (external marked `source: "external"`).
4. `get_vehicle_market_price_details` resolves both market-price ids and `candidate:` ids (price from trimmed raw snapshot).

## Adapters

| Kind | Search | Detail |
|------|--------|--------|
| BidWrangler | `GET {origin}/api/items/search?query=` | `GET {origin}/api/items/:id` |
| Royal | GraphQL `lots(..., search:{text:})`; optional `auction_id` filter for lot-crawl | GraphQL `lot(auction_lot_id:)`; make/model from title only |
| Craigslist | `{:error, :not_implemented}` | stub |

Explicit unknown odometer text (`Odom Reads N/A`, `exempt`, etc.) is stored as **miles 0** so digest/import can complete without a form.

## Admin routes

| Method | Path | Role | Description |
|--------|------|------|-------------|
| GET | `/admin` | admin | Hub with panels (`?tab=sources\|jobs\|candidates`) |
| POST | `/admin/auction-sources` | admin | Create source |
| PATCH | `/admin/auction-sources/:id` | admin | Update (enable/disable/label) |
| POST | `/admin/auction-sources/from-suggestion` | admin | Add a suggested origin |
| POST | `/admin/jobs/crawl` | admin | Enqueue `CrawlPastAuctionsWorker` |
| POST | `/admin/jobs/search` | admin | Trial search via vehicle form (`make`/`model`; same as agent; passes `user_id` for digests) |
| GET | `/admin/jobs/:id` | admin | Job args / meta / errors; crawl Results from `meta.results` or source `last_crawl_*` |
| POST | `/admin/jobs/:id/retry` | admin | Retry discarded / retryable / cancelled / completed Oban job |
| POST | `/admin/jobs/:id/run-now` | admin | Run scheduled / available / suspended job immediately |
| POST | `/admin/candidates/:id/digest` | admin | Enqueue `DigestCandidateWorker` |
| POST | `/admin/candidates/:id/dismiss` | admin | Mark candidate dismissed |
| GET | `/admin/candidates/:id` | admin | Candidate detail + raw snapshot |

Legacy list URLs (`/admin/auction-sources`, `/admin/jobs`, `/admin/candidates`) redirect to `/admin?tab=…`.

Tools drawer → **Admin** opens the hub; nested links open the matching panel.

## Background jobs (Oban)

- `CrawlPastAuctionsWorker` — enabled Royal sources (or optional `source_id`), past auctions (`auction_status: [300]` via GraphQL `AuctionPaginationInput` + `AuctionFilterInput`), writes job `meta.results`, source `config.last_crawl_report` / `last_crawl_auctions` / `last_crawl_job_id`, and `last_crawled_at`.
- `CrawlAuctionLotsWorker` — Royal-only; args `auction_source_id`, `auction_id`, `query`, `user_id`, `page`. Searches lots in that auction (same text query), upserts candidates, chains pages 1..5 with per-source stagger. Non-Royal sources cancel.
- `DigestCandidateWorker` — import a candidate URL into `vehicle_market_prices` (`user_id` + `auction_source_id` in args). Unique on `candidate_id` while available/scheduled/executing/completed.

**Stagger:** 30 seconds between jobs that share an `auction_source_id` on queues `digest` and `crawl`.

Cron: every 6 hours for past-auction crawl. Admins can also enqueue from `/admin/jobs`.

## URL import

`Agent.extract_listing_from_url/2` still recognizes BidWrangler UI item URLs and Royal lot URLs for manual “Add market price” imports.
