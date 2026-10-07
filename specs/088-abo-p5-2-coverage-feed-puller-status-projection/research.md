# Research: P5.2 coverage feed puller

## 1. R-4 local pg_cron and two-phase pg_net

**Decision:** The pull stays `pg_cron` every 30 seconds with two-phase `pg_net`. The cron command is `SELECT auth_internal.pull_coverage_feed()`. `net.http_get` keeps the extension default timeout of 5000 ms. The named longer-interval fallback is not used.

**Rationale:** The spike ran on local Supabase (`postgresql://postgres:postgres@127.0.0.1:54322/postgres`, PostgreSQL 15.8). `pg_cron` 1.6 and `pg_net` 0.14.0 are already in `shared_preload_libraries`. `pg_net` was already installed. The spike created `pg_cron`, scheduled two jobs, issued `net.http_get` against a host HTTP server at `host.docker.internal:8765`, then unscheduled the jobs, dropped the spike tables, deleted the spike `net._http_response` rows, and dropped `pg_cron`.

### 1.1 Overlapping runs

`cron.schedule(..., '30 seconds', ...)` is accepted. A job that only inserted a timestamp ran at 18:48:46, 18:49:16, 18:49:46, 18:50:16, and 18:50:46 UTC, each run about 5–7 ms. A second job that slept 40 seconds started at 18:50:21 and ended at 18:51:01. Its next run started at 18:51:01.774, after the previous run finished, and skipped the 18:50:51 slot. The same job does not overlap itself. `cron.max_running_jobs` is 32, so a different job can run at the same time. This unit schedules one pull job. `net.http_get` returned a request id in 5 ms without waiting for the body, so a pull tick stays far under 30 seconds.

### 1.2 Response size and timeout

`net.http_get` default `timeout_milliseconds` is 5000. A 76-byte JSON body, a 100010-byte body, and a 1000010-byte body came back HTTP 200 inside that default. A 5000010-byte body came back HTTP 200 when the call set `timeout_milliseconds` to 20000. An 8-second handler with the default timeout wrote `timed_out` and `Timeout of 5000 ms reached` and stored no content. A coverage page is `limit` 200. A body of about 1 MB already fits in the default timeout, which is larger than that page. A timed-out row is a pull failure: the cursor stays and `consecutive_failures` increments. The function does not pass a longer timeout.

### 1.3 `cron.job_run_details` growth

`cron.log_run` is on. Each run inserts one row. One 30-second job is 2880 rows per day. The spike rows were still present until the cleanup delete. Growth does not miss the freshness bound: the fast job kept the 30-second spacing. This unit does not add a purge. Hosted growth stays with P8.1.

### 1.4 Host reachability

From the database container, `http://host.docker.internal:8765/small` returned 200. `127.0.0.1` inside that container is not the host. `ai.platform_base_url` stays `http://127.0.0.1:8787` for `get_ai_status`. `pull_coverage_feed` rewrites only a loopback host (`127.0.0.1` or `localhost`) to `host.docker.internal` and keeps the scheme and port. Any other host is used as stored.

### 1.5 Named fallback

05 §10 names a longer pull interval within the 2-minute bound if this spike fails. The local spike passed, so the interval stays 30 seconds.

### 1.6 Staging

No staging Supabase project was used. The unit row spikes R-4 locally. Hosted confirmation stays with P8.1. The spike stops at this local result and does not open a hosted run.
