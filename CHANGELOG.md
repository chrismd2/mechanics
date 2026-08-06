# Changelog

## 2026-08-06 — deploy-workflow-gha-tests

- Run `mix test` in GitHub Actions (Postgres service) before SSH deploy
- Stop running `make test mechanics` on the production host during deploy
