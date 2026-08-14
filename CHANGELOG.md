# Changelog

## 2026-08-13 — admin-digest-job-results

- Show digest Outcomes on `/admin/jobs/:id` (meta + candidate fallback): status, lot URL, candidate link, market price

## 2026-08-13 — admin-job-run-now

- Add Run now for scheduled/available Oban jobs on the admin jobs list and job detail

## 2026-08-13 — staggered-digest-lot-crawl

- Auto-enqueue staggered digests for new `listing_candidates`; Royal auction lot-crawl by query with pagination; admin Oban job retry; paginate source search (max 5 pages)

## 2026-08-13 — admin-job-collapsible-sections

- Make Details, Results, Args, Meta, and Errors collapsible on `/admin/jobs/:id`

## 2026-08-13 — admin-job-results-fallback

- Show crawl Results on `/admin/jobs/:id` from job meta or auction-source crawl data (so older jobs still list auctions)

## 2026-08-13 — admin-source-link-last-crawl-job

- Wrap auction-source `last_crawl_report` in the source row; link the source block to the last crawl Oban job

## 2026-08-13 — admin-job-crawl-results

- Persist crawl auction lists on Oban job `meta.results` and show them on `/admin/jobs/:id`

## 2026-08-13 — royal-past-auctions-pagination-type

- Fix Royal past-auction crawl GraphQL 400 by using `AuctionPaginationInput` (not `Pagination`)

## 2026-08-13 — royal-model-from-title-only

- Parse Royal make/model from lot title only (description was overflowing `model` varchar(255) and failing digest inserts)

## 2026-08-13 — auction-odometer-na-as-zero

- Treat auction odometer N/A / exempt / unknown as miles `0` so digest can import lots without a manual form

## 2026-08-13 — admin-oban-job-timestamp

- Fix Oban Jobs list crash: use Oban timestamps (`completed_at` / `attempted_at` / …) instead of missing `updated_at`

## 2026-08-13 — admin-oban-jobs-label

- Rename Admin “Jobs” UI labels to “Oban Jobs”

## 2026-08-13 — admin-hub-tab-panels

- Put Admin tools on one `/admin` page with Account-style panels (sources, jobs, candidates); legacy list URLs redirect to `?tab=`

## 2026-08-13 — admin-trial-search-vehicle-form

- Trial listing search on `/admin/jobs` uses the same make/model/year/miles/zip fields as price suggestions

## 2026-08-13 — admin-jobs-and-candidates-ui

- Nest Admin tools (auction sources, jobs, listing candidates); add manual crawl enqueue, trial search, Oban job detail, and candidate digest/dismiss

## 2026-08-13 — pricing-external-comps-in-agent-tools

- Wire BidWrangler/Royal search into existing `search_vehicle_market_prices` / `get_vehicle_market_price_details` for suggestions

## 2026-08-13 — multi-source-listing-search

- Add BidWrangler + Royal listing search with review queue, admin-managed auction sources (suggestions from recent market-price URLs), Craigslist stub, Oban past-auction crawl + deferred digest, and Royal lot URL extract

## 2026-08-12 — suggest-after-market-price

- After a successful market-price URL import or manual save, run a price suggestion for that vehicle and show it on the suggestion page with the form prefilled
- Match make/model with exact token-set containment so `f450` does not match `f-4500` deluxe-style names

## 2026-08-12 — pricing-bidwrangler-item-import

- Implemented module BidWrangler `/ui/auctions/:auction_id/:item_id` URLs via `/api/items/:item_id` (never the auction catalog); map sold/listing fields deterministically with compact LLM fallback; keep Open Graph meta in generic HTML extraction

## 2026-08-12 — pricing-year-specific-heuristic

- For year-specific suggests, fall back to seed-comp percentiles when the LLM returns null prices; treat blank miles as unspecified

## 2026-08-12 — pricing-trim-token-subset

- Treat trim variants as similar via bidirectional token-set containment (`f450` ↔ `F450 King Ranch`)

## 2026-08-12 — pricing-model-token-similarity

- Match make/model via alphanumeric tokens so `f450` finds `F-450` but not `f-4500` deluxe-style names

## 2026-08-12 — pricing-best-guess-list-years

- On make/model best-guess (no year), list matching market prices with their years under the aggregated suggestion

## 2026-08-12 — pricing-best-guess-without-year

- With no year, suggest a labeled best-guess price from make/model comps (skip LLM)

## 2026-08-12 — pricing-suggest-optional-year-miles

- Allow suggest with make/model only (blank year → unspecified `0`, blank miles → `0`); form fields drive seed/similar search

## 2026-08-12 — pricing-similar-comps-dismiss

- When competitive and expected-minimum are both nil, show top 3 similar market prices with Dismiss; refill from the next match

## 2026-08-12 — pricing-llm-heuristic-fallback

- Fall back to seed-comp heuristic when the pricing LLM key is missing/invalid, HTTP fails, or the client raises; keep human summaries (no raw JSON under Suggestion)

## 2026-08-12 — pricing-llm-provider-agnostic

- Read pricing LLM credentials from `PRICING_LLM_API_KEY` / `PRICING_LLM_MODEL` / `PRICING_LLM_BASE_URL` (OpenAI-compatible; no Groq-named env)

## 2026-08-12 — pricing-llm-docker-env

- Document pricing LLM env vars and Docker wiring

## 2026-08-11 — ci-deploy-pull-branch

- Redeploy on PR push (`synchronize`); hard-reset server checkout to the triggering remote branch
- Fail SSH deploy on git/make errors (`set -e`)

## 2026-08-11 — ci-deploy-workflow

- Run `mix test` in GitHub Actions (Postgres service) before deploy; skip draft PRs; trigger on ready_for_review
- Deploy over SSH only after CI tests pass (same conditions as electricquestlog)

## 2026-08-11 — pricing-zipcode

- Add `zipcode` to vehicle market prices and suggestion queries (default `00000`; backfill existing rows)
- Collect zipcode on market-price and suggest forms; include it in recent-search re-runs

## 2026-08-11 — pricing-ui-polish

- Flash clearly when a market-price URL is already saved (from-url and manual save)
- Nest Tools drawer links under Vehicle price suggestions; rename to Recent searches
- Collapsible search/filter on `/pricing/queries`; indent result price lines

## 2026-08-11 — pricing-suggest-seed-widen

- Widen suggestion comps to same make/model/year when miles ±20% is empty; always include VIN matches
- Default blank miles to 0 so VIN decode can auto-suggest
- Store vehicle market prices as a shared pool (drop `user_id`)
- Format money and miles with thousand separators on pricing pages

## 2026-08-11 — pricing-dismiss-searches

- Allow dismissing recent price searches from the suggestion sidebar and history page

## 2026-08-11 — pricing-unique-searches

- Upsert price suggestion queries per user + vehicle so re-runs refresh the existing search instead of duplicating it
- Deduplicate existing query rows before adding the unique index

## 2026-08-11 — pricing-recent-searches

- Show top 3 recent suggestion queries beside the pricing form with one-click re-run
- Add searchable/filterable `/pricing/queries` history page and Tools drawer link

## 2026-08-11 — pricing-flash-accuracy

- Use amber Notice flashes for incomplete URL extraction and VIN lookup
- Reject duplicate market-price URLs with a red error flash and stay on the URL form

## 2026-08-11 — pricing-suggest-from-vin

- Start price suggestions with a VIN check; auto-suggest when complete; fall back to the manual vehicle form when the check fails or fields are missing

## 2026-08-11 — market-price-from-url

- Start market-price entry with a URL; skip duplicates; agent-extract when possible; fall back to the manual form; always store `source_url`

## 2026-08-11 — tools-drawer

- Add a signed-in header Tools side drawer with role-gated links, including vehicle pricing for `pricing_user`

## 2026-08-11 — stale-session-user

- Clear missing `current_user_id` sessions in Authenticate instead of raising `Ecto.NoResultsError` on every page

## 2026-08-11 — vehicle-pricing-suggestions

- Add `pricing_user` role and `Accounts.add_pricing_user_role/1`
- Store vehicle market prices (`listing` or `sale`) and price suggestion queries
- Add browser pricing tool (`/pricing`, `/pricing/market-prices`) gated on `pricing_user`
- Suggest competitive and expected-minimum prices via a tool-using pricing agent (LLM client isolated for provider swaps)
