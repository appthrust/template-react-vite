# Agent Guide

Keep this template buildable with `docker build .`. The AppThrust launch workflow expects the app to bind to `0.0.0.0:5173`.

Production must use the Dockerfile's non-root nginx runtime, never `vite preview`.
Keep exactly `5173/tcp` exposed (do not inherit nginx base-image ports).
Preserve SPA HTML/no-cache, hashed assets/immutable with missing-asset 404,
`/healthz` plain-text `ok`/no-store, dotfile denial, and no API-to-HTML fallback.
Do not put unhashed public files under `/assets/` or runtime secrets in browser
configuration. Keep the lockfile in sync with pinned dependencies; builds use
`npm ci`. `npm run preview` is loopback-only local tooling.

After serving changes, run `scripts/test-serving.sh` and `git diff --check`;
avoid repo-wide sweeps. The script uses Docker and Python 3, bounded waits, and
trap-based container cleanup. CI's serving-smoke job must gate publication.
