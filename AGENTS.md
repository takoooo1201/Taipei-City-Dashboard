# Repository Guidelines

## Project Structure & Module Organization

This repository is split into three applications. `Taipei-City-Dashboard-FE/` is the Vue 3/Vite frontend; source lives in `src/`, with UI in `src/components/`, views in `src/views/`, Pinia stores in `src/store/`, routing in `src/router/`, and static map/data assets in `public/`. `Taipei-City-Dashboard-BE/` is the Go API; entry points are `main.go` and `cmd/`, with Gin routes, controllers, and models under `app/`. `Taipei-City-Dashboard-DE/` contains Airflow/Python DAGs and CICD utilities. Docker orchestration is in `docker/`; seed SQL and CSV data are in `db-sample-data/`, `csv/`, and `new-resident.SQL`.

## Build, Test, and Development Commands

- `cd Taipei-City-Dashboard-FE && npm install`: install frontend dependencies.
- `cd Taipei-City-Dashboard-FE && npm run dev`: start the Vite dev server.
- `cd Taipei-City-Dashboard-FE && npm run build`: run ESLint with fixes, then build production assets.
- `cd Taipei-City-Dashboard-FE && npm run preview`: preview the built frontend locally.
- `cd Taipei-City-Dashboard-BE && go run main.go`: start the backend API.
- `cd Taipei-City-Dashboard-BE && go test ./...`: run Go tests when present.
- `docker compose -f docker/docker-compose-db.yaml up`: start Redis, PostGIS, and pgAdmin.
- `docker compose -f docker/docker-compose.yaml up`: start nginx, frontend, and backend.

## Coding Style & Naming Conventions

Frontend JavaScript and Vue files use tabs, ES modules, and `Taipei-City-Dashboard-FE/eslint.config.js`. Avoid `console.log`; `console.warn` and `console.error` are allowed. Use PascalCase for Vue components and camelCase for stores/utilities. Format Go code with `gofmt`; keep handlers in controllers, persistence structs in models, and shared helpers in `app/util/`.

## Testing Guidelines

There is no broad checked-in test suite yet. For backend changes, add `_test.go` files beside the package tested and run `go test ./...`. For data-engineering changes, prefer `pytest` tests near the DAG or utility changed; DE requirements already include pytest. For frontend changes, run `npm run build` at minimum because it performs linting and compilation.

## Commit & Pull Request Guidelines

Recent history uses short, imperative messages such as `add: final csv`. Keep commits focused and use a scoped prefix when helpful, for example `fix: dashboard auth` or `add: resident dataset`. Pull requests should describe the change, list validation commands, mention environment variables or migrations, link related issues, and include screenshots for UI changes.

## Security & Configuration Tips

Do not commit secrets or local `.env` files. Docker compose expects `JWT_SECRET`, database credentials, Redis settings, `VITE_API_URL`, and Mapbox/TaipeiPass variables from the environment. Keep sample data anonymized and avoid large generated outputs unless they are required fixtures.
