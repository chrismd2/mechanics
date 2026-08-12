# Changelog

## 2026-08-12 — pricing-llm-docker-env

- Document pricing LLM env vars (`GROQ_API_KEY`, optional model/base URL) and Docker wiring

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
