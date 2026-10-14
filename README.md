# React + Vite + PostgreSQL

AppThrust static React application template. Production uses non-root nginx on
`0.0.0.0:5173`, not Vite's development or preview server. The final image exposes
only `5173/tcp`; Node, dependencies, and application source stay in the build stage.

## Local Docker check

```bash
docker build -t template-react-vite:local .
docker run --rm -p 5173:5173 template-react-vite:local
```

Run `scripts/test-serving.sh` (Docker and Python 3 required) for the bounded
container acceptance test. It removes its test container on exit and keeps the
local `template-react-vite:serving-test` image for metadata inspection.

## Serving contract

- `/` and client-side deep links serve `index.html` with `Cache-Control: no-cache`.
- Vite-generated hashed files under `/assets/` have
  `public, max-age=31536000, immutable`; missing assets return 404, never SPA HTML.
  Keep unhashed public files outside `/assets/`.
- `/healthz` returns plain-text `ok` with `no-store`, independent of PostgreSQL.
  Docker checks this path; existing AppThrust readiness/liveness probes on `/`
  remain unchanged and check real content.
- Arbitrary published Host headers are accepted. Dotfiles and `/api` paths are
  denied; directory listing and nginx version disclosure are disabled.
- nginx writes logs to stdout/stderr and uses `/tmp` for PID and temporary files.

## Local tooling and configuration

Use `npm ci`, then `npm run dev` for development or `npm run build` followed by
`npm run preview` for loopback-only local preview. Preview is not a production server.
Dependencies and the lockfile are pinned. Build inputs use Node 22.23.3 and Alpine
3.23.6 images pinned by digest, with Alpine nginx 1.28.3-r7.

Vite public configuration is compiled at build time: only intentionally public
values belong in `VITE_*`. Never expose database credentials there. AppThrust's
ComponentConnection injects `DATABASE_URL` at container runtime for server-side
components; this static application has no database backend and nginx does not
substitute runtime environment values into served files. Environment-file variants
are excluded from the Docker context. The publish workflow requires the serving
smoke job to succeed before publishing the existing image names/tags.
