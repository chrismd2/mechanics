# Changelog

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
