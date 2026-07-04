/**
 * AI Control Plane Dashboard — vanilla JS client for the AI Gateway.
 * Polls gateway endpoints and renders live observability panels.
 */
(function () {
  'use strict';

  const DEFAULT_POLL_INTERVAL_S = 5;
  const STALE_MULTIPLIER = 2;
  const DOWN_MULTIPLIER = 3;
  const SPARKLINE_MAX_POINTS = 60;
  const RUNNER_LIFECYCLE = ['UNKNOWN', 'STARTING', 'READY', 'DEGRADED', 'UNREACHABLE'];
  const AUTH_TOKEN_STORAGE_KEY = 'dashboard_jwt_token';

  /** Routes that require Authorization: Bearer (Phase 4+). */
  const PROTECTED_PATH_PREFIXES = ['/ready', '/v1/status', '/v1/runners/', '/v1/capabilities', '/v1/ai/generate'];

  const DEFAULT_AI_ACCESS_ROLES = {
    administrator: true,
    doctor: true,
    receptionist: false,
    lab_staff: false,
  };

  /** Phase descriptor — maps phases to DOM sections and optional capability probes. */
  const PHASES = {
    1: {
      label: 'Setup',
      sections: ['architecture-panel'],
    },
    2: {
      label: 'Foundational',
      sections: ['security-panel', 'error-envelope-panel'],
    },
    3: {
      label: 'Health spine',
      sections: [
        'overview-section',
        'runners-panel',
        'metrics-panel',
        'endpoint-explorer',
        'phase-coverage-panel',
      ],
    },
    4: {
      label: 'Auth',
      sections: ['auth-panel'],
      probe: { path: '/ready', method: 'GET', expectStatus: [401], skipAuth: true },
    },
    5: {
      label: 'Capabilities & Generate',
      sections: ['capabilities-section', 'generate-section'],
      probe: { path: '/v1/capabilities', method: 'GET', expectStatus: 200 },
    },
    6: {
      label: 'Polish & Hardening',
      sections: [],
    },
  };

  const ERROR_CODES = [
    { code: 'bad_request', http: 400, phaseActive: true },
    { code: 'ai_no_capacity', http: 503, phaseActive: true },
    { code: 'ai_timeout', http: 504, phaseActive: true },
    { code: 'unauthenticated', http: 401, phaseActive: true },
    { code: 'forbidden', http: 403, phaseActive: true },
    { code: 'not_implemented', http: 501, phaseActive: false },
    { code: 'rate_limited', http: 429, phaseActive: false },
  ];

  /** Checklist aligned with docs/ai/phase-capabilities.md Phases 1–4. */
  const PHASE_COVERAGE = [
    { phase: 1, label: 'Isolated ai/ project skeleton', mode: 'static' },
    { phase: 1, label: 'Gateway + Ollama runner layout', mode: 'live', check: (s) => !!s.status?.architecture },
    { phase: 1, label: 'Docker image & dev tooling (ruff, pytest)', mode: 'static' },
    { phase: 2, label: 'Boot gateway with typed config', mode: 'live', check: (s) => !!s.status?.config_safe },
    { phase: 2, label: 'GET /health liveness', mode: 'live', check: (s) => s.health.ok },
    { phase: 2, label: 'GET /metrics Prometheus scrape', mode: 'live', check: (s) => !!s.metricsParsed },
    { phase: 2, label: 'Uniform error envelope', mode: 'live', check: (s) => hasErrorEnvelopeSample(s) },
    { phase: 2, label: 'Structured JSON logs (log_dir)', mode: 'live', check: (s) => !!s.status?.config_safe?.log_dir },
    { phase: 2, label: 'X-Request-ID correlation header', mode: 'live', check: (s) => !!s.lastRequestId },
    { phase: 2, label: 'CORS allowlist', mode: 'live', check: (s) => Array.isArray(s.status?.config_safe?.allowed_origins) },
    { phase: 3, label: 'GET /ready honest readiness', mode: 'live', check: (s) => s.ready.status != null },
    { phase: 3, label: 'Runner lifecycle state machine', mode: 'live', check: (s) => (s.status?.runners?.length || 0) > 0 },
    { phase: 3, label: 'In-memory runner registry', mode: 'live', check: (s) => Array.isArray(s.status?.runners) },
    { phase: 3, label: 'Background health poller', mode: 'live', check: (s) => !!s.status?.poller },
    { phase: 3, label: 'Model discovery GET /v1/models', mode: 'live', check: (s) => hasModelDiscovery(s) },
    { phase: 3, label: 'Runners not client-routable', mode: 'static' },
    { phase: 3, label: 'Isolation scan CI gate', mode: 'static', hint: 'cd ai/gateway && .venv/bin/python scripts/isolation_scan.py' },
    { phase: 3, label: 'Failover timing (~poll × failures)', mode: 'live', check: (s) => s.status?.poller?.estimated_failover_s != null },
    { phase: 3, label: 'Control plane dashboard', mode: 'live', check: () => true },
    { phase: 4, label: 'JWT required on protected routes', mode: 'live', check: (s) => s.auth?.enforced === true },
    { phase: 4, label: '401 unauthenticated (missing/invalid token)', mode: 'live', check: (s) => s.auth?.saw401 === true || seenErrorCodes().has('unauthenticated') },
    { phase: 4, label: '403 forbidden (role without ai.access)', mode: 'static', hint: 'Use receptionist JWT in explorer' },
    { phase: 4, label: 'Offline HS256 / JWKS validation', mode: 'static', hint: 'No Supabase network per request' },
    { phase: 4, label: 'Reloadable role → ai.access map', mode: 'static', hint: 'role_ai_access in gateway.yaml or role_ai_access.yaml' },
    { phase: 4, label: 'Dashboard Bearer token for API polls', mode: 'live', check: (s) => !!s.auth?.tokenPresent },
  ];

  function hasErrorEnvelopeSample(s) {
    const readyErr = s.ready.body?.error;
    if (readyErr?.code && readyErr?.request_id) return true;
    const statusErr = s.statusAuthError?.error;
    if (statusErr?.code && statusErr?.request_id) return true;
    const parsed = s.metricsParsed;
    if (!parsed) return false;
    return Object.values(parsed.counters).some((e) => e.name === 'gateway_errors_total');
  }

  function hasModelDiscovery(s) {
    if (Object.keys(s.runnerModelsPolls).length > 0) return true;
    return (s.status?.runners || []).some((r) => r.loaded_model?.name);
  }

  const GATEWAY_ROOT = '';

  /** Routes used only for observability — excluded from API request totals in the overview. */
  const CONTROL_PLANE_ENDPOINTS = new Set(['/health', '/ready', '/metrics', '/v1/status']);

  function isControlPlaneEndpoint(path) {
    if (!path) return false;
    if (CONTROL_PLANE_ENDPOINTS.has(path)) return true;
    return path === '/dashboard' || path.startsWith('/dashboard/');
  }

  const state = {
    pollIntervalMs: DEFAULT_POLL_INTERVAL_S * 1000,
    pollTimer: null,
    lastPollAt: null,
    lastSuccessAt: null,
    connectionState: 'unknown',
    status: null,
    health: { ok: false, status: null, body: null },
    ready: { ok: false, status: null, body: null },
    metricsRaw: '',
    metricsParsed: null,
    requestHistory: [],
    prevCounters: null,
    phaseProbes: {},
    lastTryResult: null,
    runnerModelsPolls: {},
    lastRequestId: null,
    authToken: null,
    auth: {
      tokenPresent: false,
      enforced: false,
      saw401: false,
      staffRole: null,
      hasAiAccess: null,
    },
    statusAuthError: null,
  };

  function requiresAuth(path) {
    if (!path) return false;
    if (path === '/health' || path === '/metrics') return false;
    if (path === '/dashboard' || path.startsWith('/dashboard/')) return false;
    return PROTECTED_PATH_PREFIXES.some((prefix) => path === prefix || path.startsWith(prefix));
  }

  function loadAuthToken() {
    try {
      return localStorage.getItem(AUTH_TOKEN_STORAGE_KEY) || null;
    } catch {
      return null;
    }
  }

  function saveAuthToken(token) {
    const trimmed = (token || '').trim();
    state.authToken = trimmed || null;
    try {
      if (state.authToken) localStorage.setItem(AUTH_TOKEN_STORAGE_KEY, state.authToken);
      else localStorage.removeItem(AUTH_TOKEN_STORAGE_KEY);
    } catch {
      /* ignore */
    }
    updateAuthStateFromToken();
  }

  function decodeJwtPayload(token) {
    if (!token) return null;
    const parts = token.split('.');
    if (parts.length < 2) return null;
    try {
      const base64 = parts[1].replace(/-/g, '+').replace(/_/g, '/');
      const padded = base64 + '='.repeat((4 - (base64.length % 4)) % 4);
      return JSON.parse(atob(padded));
    } catch {
      return null;
    }
  }

  function updateAuthStateFromToken() {
    const token = state.authToken;
    state.auth.tokenPresent = !!token;
    const payload = decodeJwtPayload(token);
    const role = payload?.staff_role || null;
    state.auth.staffRole = role;
    state.auth.hasAiAccess = role ? !!DEFAULT_AI_ACCESS_ROLES[role] : null;
  }

  function authHeadersFor(path, options) {
    const opts = options || {};
    if (opts.skipAuth) return {};
    if (!requiresAuth(path)) return {};
    if (!state.authToken) return {};
    return { Authorization: `Bearer ${state.authToken}` };
  }

  function $(id) {
    return document.getElementById(id);
  }

  function $qa(sel, root) {
    return Array.from((root || document).querySelectorAll(sel));
  }

  function setText(el, text) {
    if (!el) return;
    el.textContent = text == null ? '—' : String(text);
  }

  function setHTML(el, html) {
    if (!el) return;
    el.innerHTML = html;
  }

  function escapeHtml(str) {
    return String(str)
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;');
  }

  function relativeTime(isoOrDate) {
    if (!isoOrDate) return 'never';
    const then = typeof isoOrDate === 'string' ? new Date(isoOrDate) : isoOrDate;
    if (Number.isNaN(then.getTime())) return 'unknown';
    const sec = Math.floor((Date.now() - then.getTime()) / 1000);
    if (sec < 5) return 'just now';
    if (sec < 60) return `${sec}s ago`;
    const min = Math.floor(sec / 60);
    if (min < 60) return `${min}m ago`;
    const hr = Math.floor(min / 60);
    if (hr < 24) return `${hr}h ago`;
    return `${Math.floor(hr / 24)}d ago`;
  }

  function formatUptime(seconds) {
    if (seconds == null) return '—';
    const s = Math.floor(seconds);
    const h = Math.floor(s / 3600);
    const m = Math.floor((s % 3600) / 60);
    const r = s % 60;
    if (h > 0) return `${h}h ${m}m`;
    if (m > 0) return `${m}m ${r}s`;
    return `${r}s`;
  }

  function shortDigest(digest) {
    if (!digest) return '—';
    const d = String(digest);
    if (d.length <= 16) return d;
    return `${d.slice(0, 8)}…${d.slice(-6)}`;
  }

  function runnerModelsPath(runnerId) {
    return `/v1/runners/${encodeURIComponent(runnerId)}/models`;
  }

  function formatCount(n) {
    if (n == null || Number.isNaN(n)) return '—';
    if (n >= 1_000_000) return `${(n / 1_000_000).toFixed(1)}M`;
    if (n >= 1_000) return `${(n / 1_000).toFixed(1)}K`;
    if (Number.isInteger(n)) return String(n);
    return n.toFixed(1);
  }

  async function fetchEndpoint(path, options) {
    const opts = options || {};
    const url = GATEWAY_ROOT + path;
    const init = {
      method: opts.method || 'GET',
      headers: { ...authHeadersFor(path, opts), ...(opts.headers || {}) },
      signal: AbortSignal.timeout(opts.timeoutMs || 8000),
    };
    if (opts.body != null) {
      init.body = opts.body;
      init.headers['Content-Type'] = init.headers['Content-Type'] || 'application/json';
    }
    const res = await fetch(url, init);
    const contentType = res.headers.get('content-type') || '';
    let body;
    if (contentType.includes('application/json')) {
      body = await res.json();
    } else {
      body = await res.text();
    }
    return { ok: res.ok, status: res.status, body, headers: res.headers, requestId: res.headers.get('X-Request-ID') };
  }

  function parsePrometheus(text) {
    const metrics = { counters: {}, gauges: {}, histograms: {} };
    const lines = String(text || '').split('\n');

    for (const line of lines) {
      const trimmed = line.trim();
      if (!trimmed || trimmed.startsWith('#')) continue;

      const match = trimmed.match(/^([a-zA-Z_:][a-zA-Z0-9_:]*)(\{([^}]*)\})?\s+([^\s]+)/);
      if (!match) continue;

      const name = match[1];
      const labelStr = match[3] || '';
      const value = parseFloat(match[4]);
      if (Number.isNaN(value)) continue;

      const labels = {};
      if (labelStr) {
        const labelRe = /([a-zA-Z_][a-zA-Z0-9_]*)="((?:\\.|[^"\\])*)"/g;
        let lm;
        while ((lm = labelRe.exec(labelStr)) !== null) {
          labels[lm[1]] = lm[2].replace(/\\"/g, '"').replace(/\\\\/g, '\\');
        }
      }

      if (name.endsWith('_bucket')) {
        const base = name.slice(0, -'_bucket'.length);
        const runnerId = labels.runner_id || '_default';
        if (!metrics.histograms[base]) metrics.histograms[base] = {};
        if (!metrics.histograms[base][runnerId]) {
          metrics.histograms[base][runnerId] = { buckets: [], sum: 0, count: 0 };
        }
        if (labels.le != null) {
          metrics.histograms[base][runnerId].buckets.push({ le: labels.le, value });
        }
      } else if (name.endsWith('_sum')) {
        const base = name.slice(0, -'_sum'.length);
        const runnerId = labels.runner_id || '_default';
        if (!metrics.histograms[base]) metrics.histograms[base] = {};
        if (!metrics.histograms[base][runnerId]) {
          metrics.histograms[base][runnerId] = { buckets: [], sum: 0, count: 0 };
        }
        metrics.histograms[base][runnerId].sum = value;
      } else if (name.endsWith('_count')) {
        const base = name.slice(0, -'_count'.length);
        const runnerId = labels.runner_id || '_default';
        if (!metrics.histograms[base]) metrics.histograms[base] = {};
        if (!metrics.histograms[base][runnerId]) {
          metrics.histograms[base][runnerId] = { buckets: [], sum: 0, count: 0 };
        }
        metrics.histograms[base][runnerId].count = value;
      } else {
        const key = metricKey(name, labels);
        if (name.endsWith('_total')) {
          metrics.counters[key] = { name, labels, value };
        } else {
          metrics.gauges[key] = { name, labels, value };
        }
      }
    }

    return metrics;
  }

  function metricKey(name, labels) {
    const parts = Object.keys(labels)
      .sort()
      .map((k) => `${k}=${labels[k]}`);
    return parts.length ? `${name}{${parts.join(',')}}` : name;
  }

  function sumCounterByName(parsed, baseName, options) {
    const excludeControlPlane = options?.excludeControlPlane === true;
    let total = 0;
    for (const entry of Object.values(parsed.counters)) {
      if (entry.name !== baseName) continue;
      if (excludeControlPlane && isControlPlaneEndpoint(entry.labels.endpoint)) continue;
      total += entry.value;
    }
    return total;
  }

  function groupCountersByLabel(parsed, baseName, label) {
    const groups = {};
    for (const entry of Object.values(parsed.counters)) {
      if (entry.name !== baseName) continue;
      const key = entry.labels[label] || 'unknown';
      groups[key] = (groups[key] || 0) + entry.value;
    }
    return groups;
  }

  function gaugesByName(parsed, baseName, labelKey) {
    const groups = {};
    for (const entry of Object.values(parsed.gauges)) {
      if (entry.name !== baseName) continue;
      const key = entry.labels[labelKey] || 'unknown';
      groups[key] = entry.value;
    }
    return groups;
  }

  function avgLatencyFromHistogram(histEntry) {
    if (!histEntry || !histEntry.count) return null;
    return (histEntry.sum / histEntry.count) * 1000;
  }

  function renderSparklineSvg(svgEl, points) {
    if (!svgEl) return;
    const width = 320;
    const height = 80;
    const pad = 6;

    if (!points.length) {
      setHTML(
        svgEl,
        `<line class="chart-placeholder-line" x1="0" y1="${height / 2}" x2="${width}" y2="${height / 2}"></line>
         <text x="${width / 2}" y="${height / 2 + 4}" text-anchor="middle" class="chart-empty">No data yet</text>`
      );
      return;
    }

    const values = points.map((p) => p.rate);
    const max = Math.max(...values, 0.001);
    const step = points.length > 1 ? (width - pad * 2) / (points.length - 1) : 0;

    const coords = points.map((p, i) => {
      const x = pad + i * step;
      const y = height - pad - (p.rate / max) * (height - pad * 2);
      return [x, y];
    });

    const polyline = coords.map(([x, y]) => `${x.toFixed(1)},${y.toFixed(1)}`).join(' ');
    const areaPath = `M ${coords[0][0]},${height - pad} L ${polyline.replace(/ /g, ' L ')} L ${coords[coords.length - 1][0]},${height - pad} Z`;

    setHTML(
      svgEl,
      `<defs>
         <linearGradient id="sparkline-gradient" x1="0" y1="0" x2="0" y2="1">
           <stop offset="0%" stop-color="var(--accent)" stop-opacity="0.35"/>
           <stop offset="100%" stop-color="var(--accent)" stop-opacity="0"/>
         </linearGradient>
       </defs>
       <path class="sparkline-area" d="${areaPath}"/>
       <polyline class="sparkline-line" points="${polyline}" fill="none" stroke-width="2"/>`
    );
  }

  function renderBarChartSvg(svgEl, items, opts) {
    if (!svgEl) return;
    const width = 320;
    const barH = 20;
    const gap = 8;
    const labelW = opts?.labelWidth || 48;
    const height = Math.max(80, items.length * (barH + gap) + gap);

    svgEl.setAttribute('viewBox', `0 0 ${width} ${height}`);

    if (!items.length) {
      setHTML(svgEl, `<text x="${width / 2}" y="${height / 2}" text-anchor="middle" class="chart-empty">No data</text>`);
      return;
    }

    const maxVal = Math.max(...items.map((i) => i.value), 0.001);
    const chartW = width - labelW - 48;

    const bars = items
      .map((item, idx) => {
        const y = gap + idx * (barH + gap);
        const barW = Math.max(2, (item.value / maxVal) * chartW);
        const color = item.color || 'var(--chart-bar)';
        return `
          <text x="0" y="${y + barH * 0.72}" class="bar-label">${escapeHtml(item.label)}</text>
          <rect x="${labelW}" y="${y}" width="${barW.toFixed(1)}" height="${barH}" rx="3" fill="${color}"/>
          <text x="${(labelW + barW + 6).toFixed(1)}" y="${y + barH * 0.72}" class="bar-value">${escapeHtml(formatCount(item.value))}</text>`;
      })
      .join('');

    setHTML(svgEl, bars);
  }

  function renderLegend(legend, items) {
    if (!legend) return;
    legend.innerHTML = items
      .map(
        (item) =>
          `<li class="chart-legend__item"><span class="chart-legend__swatch" style="background:${item.color}"></span>${escapeHtml(item.label)}</li>`
      )
      .join('');
    legend.removeAttribute('aria-hidden');
  }

  function updateConnectionIndicator() {
    const badge = $('connection-indicator');
    const label = $('connection-label');
    if (!badge) return;

    const now = Date.now();
    const interval = state.pollIntervalMs;
    let conn = 'down';

    if (state.lastSuccessAt) {
      const age = now - state.lastSuccessAt;
      if (age <= interval * STALE_MULTIPLIER) conn = 'live';
      else if (age <= interval * DOWN_MULTIPLIER) conn = 'stale';
    } else if (!state.lastPollAt) {
      conn = 'unknown';
    }

    state.connectionState = conn;
    badge.dataset.state = conn;

    const labels = { live: 'Live', stale: 'Stale', down: 'Down', unknown: 'Connecting…' };
    setText(label, labels[conn] || conn);
  }

  function renderHeader() {
    const gw = state.status?.gateway;
    const readyFromStatus = gw?.ready;
    const readyFromPoll = state.ready.ok;
    const readyDenied = state.ready.status === 401;
    const ready = readyDenied ? false : readyFromPoll || readyFromStatus;

    const readyBadge = $('readiness-badge');
    if (readyBadge) readyBadge.dataset.ready = readyDenied ? 'auth' : ready ? 'true' : 'false';
    setText(
      $('readiness-label'),
      readyDenied ? 'Auth required' : ready ? 'Ready' : 'Not ready'
    );

    const phasePill = $('phase-pill');
    if (phasePill) {
      const active = gw?.phase_active ?? 3;
      phasePill.textContent = `Phases 1–${active} active`;
    }

    setText(
      $('last-refresh'),
      state.lastPollAt ? `Updated ${new Date(state.lastPollAt).toLocaleTimeString()}` : '—'
    );

    updateConnectionIndicator();
  }

  function setStatCard(cardId, valueId, hintId, value, hint, cardStatus) {
    const card = $(cardId);
    const status = cardStatus || 'neutral';
    if (card) {
      card.dataset.status = status;
      card.dataset.state = status;
    }
    setText($(valueId), value);
    if (hintId) setText($(hintId), hint);
  }

  function renderOverview() {
    const runners = state.status?.runners || [];
    const readyCount = runners.filter((r) => r.status === 'READY' || r.status === 'BUSY').length;
    const parsed = state.metricsParsed;

    let totalRequests = parsed
      ? sumCounterByName(parsed, 'gateway_requests_total', { excludeControlPlane: true })
      : null;
    let totalErrors = parsed ? sumCounterByName(parsed, 'gateway_errors_total') : null;

    let requestDelta = null;
    let errorRate = null;

    if (parsed && state.prevCounters && state.lastPollAt) {
      const dt = (state.lastPollAt - state.prevCounters.at) / 1000;
      if (dt > 0 && totalRequests != null) {
        requestDelta = (totalRequests - state.prevCounters.requests) / dt;
      }
      if (totalRequests != null && totalErrors != null) {
        const reqD = totalRequests - state.prevCounters.requests;
        const errD = totalErrors - state.prevCounters.errors;
        if (reqD > 0) errorRate = (errD / reqD) * 100;
      }
    }

    setStatCard(
      'card-liveness',
      'metric-liveness',
      'metric-liveness-hint',
      state.health.ok ? 'UP' : 'DOWN',
      state.health.status ? `HTTP ${state.health.status}` : '/health',
      state.health.ok ? 'ok' : 'error'
    );

    setStatCard(
      'card-readiness',
      'metric-readiness',
      'metric-readiness-hint',
      state.ready.status === 401 ? 'AUTH' : state.ready.ok ? 'READY' : 'NOT READY',
      readinessHint(),
      state.ready.status === 401 ? 'warn' : state.ready.ok ? 'ok' : 'warn'
    );

    setStatCard(
      'card-total-runners',
      'metric-total-runners',
      'metric-total-runners-delta',
      runners.length,
      `${runners.length} registered`,
      'neutral'
    );

    setStatCard(
      'card-ready-runners',
      'metric-ready-runners',
      'metric-ready-runners-hint',
      readyCount,
      runners.length ? `${readyCount}/${runners.length} healthy` : 'registry',
      readyCount > 0 ? 'ok' : 'warn'
    );

    setStatCard(
      'card-total-requests',
      'metric-total-requests',
      'metric-total-requests-delta',
      totalRequests != null ? formatCount(totalRequests) : '—',
      requestDelta != null ? `${requestDelta.toFixed(2)}/s Δ` : 'excl. health & dashboard polls',
      'neutral'
    );

    const errState = errorRate != null && errorRate > 5 ? 'error' : errorRate != null && errorRate > 1 ? 'warn' : 'ok';
    setStatCard(
      'card-error-rate',
      'metric-error-rate',
      'metric-error-rate-hint',
      errorRate != null ? `${errorRate.toFixed(1)}%` : '—',
      totalErrors != null ? `${formatCount(totalErrors)} total errors` : 'session delta',
      errState
    );
  }

  function readinessHint() {
    if (state.ready.status === 401) {
      return 'HTTP 401 · save JWT in Security';
    }
    if (state.ready.ok) {
      return state.ready.status ? `HTTP ${state.ready.status}` : '/ready';
    }
    const err = state.ready.body?.error;
    if (err?.code) {
      return `HTTP ${state.ready.status || 503} · ${err.code}`;
    }
    return state.ready.status ? `HTTP ${state.ready.status}` : '/ready';
  }

  function renderArchitecture() {
    const arch = state.status?.architecture;
    const cfg = state.status?.config_safe;
    const port = cfg?.port ?? arch?.gateway?.default_port ?? 8090;
    const origin = window.location.origin || `http://localhost:${port}`;

    setText($('arch-gateway-url'), `${origin.replace(/:\d+$/, '')}:${port}`);
    setText($('arch-gateway-reach'), arch?.gateway?.reachable_by || 'clinic clients on the LAN');

    const runnerUrl =
      arch?.runners?.configured_base_urls?.[0] ||
      arch?.runners?.default_base_url ||
      'http://127.0.0.1:11434';
    setText($('arch-runner-url'), runnerUrl);
    setText($('arch-runner-reach'), arch?.runners?.reachable_by || 'gateway only — not client-routable');
  }

  function renderPollerMeta() {
    const poller = state.status?.poller;
    const el = $('poller-meta');
    if (!el) return;
    if (!poller) {
      setText(el, '—');
      return;
    }
    setText(
      el,
      `Health poller every ${poller.health_poll_interval_s}s · UNREACHABLE after ${poller.unreachable_after_failures} failures · ~${poller.estimated_failover_s}s failover`
    );
  }

  function digestStatus(runner) {
    const declared = runner.declared_models || [];
    const loaded = runner.loaded_model;
    if (!declared.length || !loaded?.digest) return null;
    const pinned = declared[0].digest;
    if (!pinned || pinned.includes('REPLACE')) return null;
    return pinned === loaded.digest ? 'match' : 'mismatch';
  }

  function renderPhaseCoverage() {
    const grid = $('phase-coverage-grid');
    if (!grid) return;

    let currentPhase = 0;
    const rows = [];

    for (const item of PHASE_COVERAGE) {
      if (item.phase !== currentPhase) {
        currentPhase = item.phase;
        rows.push(`<div class="coverage-phase"><h3 class="coverage-phase__title">Phase ${currentPhase}</h3></div>`);
      }

      let stateName = 'static';
      let symbol = '◆';
      if (item.mode === 'live') {
        const ok = item.check ? item.check(state) : false;
        stateName = ok ? 'live' : 'partial';
        symbol = ok ? '✓' : '…';
      }

      const hint = item.hint ? `<p class="coverage-item__hint">${escapeHtml(item.hint)}</p>` : '';

      rows.push(`
        <article class="coverage-item" role="listitem">
          <span class="coverage-item__badge" data-state="${stateName}" aria-hidden="true">${symbol}</span>
          <p class="coverage-item__label">${escapeHtml(item.label)}</p>
          <span class="coverage-item__phase">P${item.phase}</span>
          ${hint}
        </article>`);
    }

    grid.innerHTML = rows.join('');
  }

  function seenErrorCodes() {
    const seen = new Set();
    const readyCode = state.ready.body?.error?.code;
    if (readyCode) seen.add(readyCode);
    const statusCode = state.statusAuthError?.error?.code;
    if (statusCode) seen.add(statusCode);
    if (state.metricsParsed) {
      for (const entry of Object.values(state.metricsParsed.counters)) {
        if (entry.name === 'gateway_errors_total' && entry.labels.code) {
          seen.add(entry.labels.code);
        }
      }
    }
    return seen;
  }

  function renderErrorEnvelope() {
    const tbody = $('error-code-list');
    const sample = $('error-envelope-sample');
    if (!tbody) return;

    const seen = seenErrorCodes();
    tbody.innerHTML = ERROR_CODES.map((row) => {
      const isSeen = seen.has(row.code);
      return `
        <tr data-seen="${isSeen ? 'true' : 'false'}" data-phase-active="${row.phaseActive ? 'true' : 'false'}">
          <td class="mono">${escapeHtml(row.code)}</td>
          <td>${row.http}</td>
          <td>${row.phaseActive ? 'yes' : 'Phase 5+'}</td>
          <td>${isSeen ? 'yes' : '—'}</td>
        </tr>`;
    }).join('');

    const readyErr = state.ready.body?.error;
    const statusErr = state.statusAuthError?.error;
    const sampleErr = readyErr || statusErr;
    if (sample) {
      if (sampleErr) {
        sample.hidden = false;
        sample.textContent = JSON.stringify({ error: sampleErr }, null, 2);
      } else {
        sample.hidden = true;
        sample.textContent = '';
      }
    }
  }

  function normalizeLifecycleStatus(status) {
    return status === 'BUSY' ? 'READY' : status;
  }

  function worstLifecycleStatus(runners) {
    if (!runners.length) return null;
    const priority = { UNREACHABLE: 5, DEGRADED: 4, STARTING: 3, UNKNOWN: 2, READY: 1 };
    return runners.reduce((worst, r) => {
      const norm = normalizeLifecycleStatus(r.status);
      const p = priority[norm] || 0;
      const wp = priority[worst] || 0;
      return p > wp ? norm : worst;
    }, 'READY');
  }

  function lifecycleBadgeClass(status) {
    const map = {
      UNKNOWN: 'lifecycle-unknown',
      STARTING: 'lifecycle-starting',
      READY: 'lifecycle-ready',
      BUSY: 'lifecycle-ready',
      DEGRADED: 'lifecycle-degraded',
      UNREACHABLE: 'lifecycle-unreachable',
    };
    return map[status] || 'lifecycle-unknown';
  }

  function renderLifecycleRail(runners) {
    const counts = {};
    for (const stateName of RUNNER_LIFECYCLE) counts[stateName] = 0;
    for (const r of runners) {
      const norm = normalizeLifecycleStatus(r.status);
      if (counts[norm] != null) counts[norm] += 1;
    }

    const aggregate = worstLifecycleStatus(runners);
    const caption = $('lifecycle-caption');

    for (const stateName of RUNNER_LIFECYCLE) {
      const node = $(`lifecycle-${stateName.toLowerCase()}`);
      if (!node) continue;
      const occupied = counts[stateName] > 0;
      const isCurrent = aggregate === stateName;
      node.classList.toggle('is-active', occupied || isCurrent);
      node.classList.toggle('lifecycle-node--occupied', occupied);
      node.classList.toggle('lifecycle-node--current', isCurrent);
    }

    if (!runners.length) {
      setText(caption, 'Current aggregate state appears when runners load');
      return;
    }

    const readyN = runners.filter((r) => r.status === 'READY' || r.status === 'BUSY').length;
    const parts = RUNNER_LIFECYCLE.filter((s) => counts[s] > 0).map((s) => `${counts[s]} ${s}`);
    setText(
      caption,
      `${runners.length} runner${runners.length === 1 ? '' : 's'} · ${parts.join(', ')} · aggregate ${aggregate} · ${readyN} READY`
    );
  }

  function renderRunnerCard(runner) {
    const model = runner.loaded_model || {};
    const caps = runner.declared_capabilities || [];
    const features = model.features || [];
    const poll = state.runnerModelsPolls[runner.id];

    const capChips = caps.map((c) => `<span class="chip chip--cap">${escapeHtml(c)}</span>`).join('');
    const featChips = features.map((f) => `<span class="chip chip--feature">${escapeHtml(f)}</span>`).join('');
    const digestMatch = digestStatus(runner);
    const declared = runner.declared_models || [];
    const pinnedDigest = declared[0]?.digest;
    const digestClass =
      digestMatch === 'match' ? 'digest--match' : digestMatch === 'mismatch' ? 'digest--mismatch' : '';
    const digestNote =
      digestMatch === 'mismatch'
        ? ' <span class="digest-note text-warn">pin mismatch</span>'
        : digestMatch === 'match'
          ? ' <span class="digest-note">pinned</span>'
          : '';

    let pollBlock = '';
    if (poll) {
      const pollStatus = poll.error
        ? 'error'
        : poll.status >= 200 && poll.status < 300
          ? 'ok'
          : 'warn';
      pollBlock = `
        <div class="runner-card__poll" data-poll-state="${pollStatus}">
          <div class="runner-card__poll-header">
            <span class="runner-card__poll-label">GET /v1/models</span>
            <span class="runner-card__poll-meta">${poll.status ? `HTTP ${poll.status}` : 'Error'}${poll.latencyMs != null ? ` · ${poll.latencyMs.toFixed(1)} ms` : ''}</span>
          </div>
          <pre class="runner-card__poll-body mono" tabindex="0">${escapeHtml(truncate(formatBody(poll.body), 4000))}</pre>
        </div>`;
    }

    return `
      <article class="runner-card" role="listitem" data-runner-id="${escapeHtml(runner.id)}" data-status="${escapeHtml(runner.status)}">
        <header class="runner-card__header">
          <h3 class="runner-card__id">${escapeHtml(runner.id)}</h3>
          <span class="runner-card__badge ${lifecycleBadgeClass(runner.status)}">${escapeHtml(runner.status)}</span>
        </header>
        <dl class="runner-card__details">
          <div class="runner-card__row"><dt>Base URL</dt><dd class="mono">${escapeHtml(runner.base_url || '—')}</dd></div>
          <div class="runner-card__row"><dt>Gateway probe</dt><dd class="mono">${escapeHtml(runnerModelsPath(runner.id))}</dd></div>
          <div class="runner-card__row"><dt>Model</dt><dd>${escapeHtml(model.name || '—')} <span class="digest mono ${digestClass}">${escapeHtml(shortDigest(model.digest || pinnedDigest))}</span>${digestNote}</dd></div>
          <div class="runner-card__row"><dt>Context</dt><dd>${model.context_tokens != null ? `${formatCount(model.context_tokens)} tokens` : '—'}</dd></div>
          <div class="runner-card__row"><dt>Last latency</dt><dd>${runner.last_latency_ms != null ? `${runner.last_latency_ms.toFixed(1)} ms` : '—'}</dd></div>
          <div class="runner-card__row"><dt>Avg latency</dt><dd>${runner.avg_latency_ms != null ? `${runner.avg_latency_ms.toFixed(1)} ms` : '—'}</dd></div>
          <div class="runner-card__row"><dt>In-flight</dt><dd>${runner.in_flight ?? 0}</dd></div>
          <div class="runner-card__row"><dt>Failures</dt><dd class="${(runner.consecutive_failures || 0) > 0 ? 'text-warn' : ''}">${runner.consecutive_failures ?? 0}</dd></div>
          <div class="runner-card__row"><dt>Last seen</dt><dd>${relativeTime(runner.last_seen_at)}</dd></div>
        </dl>
        ${caps.length ? `<div class="runner-card__chips"><span class="runner-card__chips-label">Capabilities</span>${capChips}</div>` : ''}
        ${features.length ? `<div class="runner-card__chips"><span class="runner-card__chips-label">Features</span>${featChips}</div>` : ''}
        <footer class="runner-card__actions">
          <button type="button" class="btn btn--probe" data-runner-id="${escapeHtml(runner.id)}" aria-label="Poll ${escapeHtml(runner.id)} via GET /v1/models">
            Poll /v1/models
          </button>
        </footer>
        ${pollBlock}
      </article>`;
  }

  async function pollRunnerModels(runnerId, btn) {
    const path = runnerModelsPath(runnerId);
    if (btn) {
      btn.disabled = true;
      btn.textContent = 'Polling…';
    }
    try {
      const result = await fetchEndpoint(path);
      const latencyMs = result.body?.poll?.latency_ms ?? null;
      state.runnerModelsPolls[runnerId] = {
        status: result.status,
        body: result.body,
        latencyMs,
        error: !result.ok,
      };
      if (result.requestId) state.lastRequestId = result.requestId;
      state.lastTryResult = {
        path,
        method: 'GET',
        status: result.status,
        body: result.body,
        requestId: result.requestId,
      };
    } catch (err) {
      state.runnerModelsPolls[runnerId] = {
        status: 0,
        body: String(err.message || err),
        latencyMs: null,
        error: true,
      };
      state.lastTryResult = { path, method: 'GET', status: 0, body: String(err.message || err) };
    } finally {
      if (btn) {
        btn.disabled = false;
        btn.textContent = 'Poll /v1/models';
      }
      renderRunners();
      renderEndpointExplorer();
    }
  }

  function bindRunnerCardActions(container) {
    $qa('.btn--probe', container).forEach((btn) => {
      btn.addEventListener('click', () => pollRunnerModels(btn.dataset.runnerId, btn));
    });
  }

  function renderRunners() {
    const container = $('runner-cards');
    const empty = $('runners-empty');
    const runners = state.status?.runners || [];

    setText($('runners-count'), `${runners.length} registered`);
    const pollAllBtn = $('poll-all-runners-btn');
    if (pollAllBtn) {
      pollAllBtn.hidden = runners.length === 0;
    }
    renderLifecycleRail(runners);

    if (!container) return;

    if (empty) {
      const hide = runners.length > 0;
      empty.classList.toggle('is-hidden', hide);
      empty.hidden = hide;
    }

    $qa('.runner-card', container).forEach((el) => el.remove());

    if (!runners.length) return;

    container.insertAdjacentHTML('beforeend', runners.map(renderRunnerCard).join(''));
    bindRunnerCardActions(container);
  }

  function updateRequestHistory(parsed) {
    if (!parsed || !state.lastPollAt) return;

    const total = sumCounterByName(parsed, 'gateway_requests_total', { excludeControlPlane: true });
    const errors = sumCounterByName(parsed, 'gateway_errors_total');

    if (state.prevCounters) {
      const dt = (state.lastPollAt - state.prevCounters.at) / 1000;
      if (dt > 0) {
        const rate = (total - state.prevCounters.requests) / dt;
        state.requestHistory.push({ t: state.lastPollAt, rate: Math.max(0, rate), total, errors });
        if (state.requestHistory.length > SPARKLINE_MAX_POINTS) state.requestHistory.shift();
      }
    }

    state.prevCounters = { at: state.lastPollAt, requests: total, errors };
  }

  function renderMetrics() {
    const parsed = state.metricsParsed;
    if (!parsed) return;

    renderSparklineSvg($('chart-request-rate'), state.requestHistory);

    const lastRate = state.requestHistory.length
      ? state.requestHistory[state.requestHistory.length - 1].rate
      : null;
    setText($('chart-request-rate-value'), lastRate != null ? `${lastRate.toFixed(2)} req/s` : '— req/s');

    const statusGroups = groupCountersByLabel(parsed, 'gateway_requests_total', 'status');
    const statusItems = Object.entries(statusGroups)
      .sort((a, b) => a[0].localeCompare(b[0]))
      .map(([code, value]) => ({
        label: code,
        value,
        color: code.startsWith('2')
          ? 'var(--status-2xx)'
          : code.startsWith('5')
            ? 'var(--status-5xx)'
            : 'var(--status-other)',
      }));
    renderBarChartSvg($('chart-status-codes'), statusItems);
    renderLegend($('chart-status-codes-legend'), statusItems);

    const hist = parsed.histograms.gateway_runner_poll_latency_seconds || {};
    let latencyItems = Object.entries(hist)
      .filter(([id]) => id !== '_default')
      .map(([runnerId, entry]) => ({
        label: runnerId,
        value: avgLatencyFromHistogram(entry) || 0,
        color: 'var(--chart-latency)',
      }))
      .sort((a, b) => b.value - a.value);

    if (!latencyItems.length && state.status?.runners) {
      latencyItems = state.status.runners
        .filter((r) => r.avg_latency_ms != null)
        .map((r) => ({ label: r.id, value: r.avg_latency_ms, color: 'var(--chart-latency)' }));
    }

    renderBarChartSvg($('chart-runner-latency'), latencyItems, { labelWidth: 72 });

    const healthGauges = gaugesByName(parsed, 'gateway_runner_health', 'runner_id');
    let healthItems = Object.entries(healthGauges)
      .map(([runnerId, value]) => ({
        label: runnerId,
        value,
        color: value >= 1 ? 'var(--status-2xx)' : 'var(--coral)',
      }))
      .sort((a, b) => b.value - a.value);

    if (!healthItems.length && state.status?.runners) {
      healthItems = state.status.runners.map((r) => ({
        label: r.id,
        value: r.status === 'READY' || r.status === 'BUSY' ? 1 : 0,
        color: r.status === 'READY' || r.status === 'BUSY' ? 'var(--status-2xx)' : 'var(--coral)',
      }));
    }

    renderBarChartSvg($('chart-runner-health'), healthItems, { labelWidth: 72 });

    const errorGroups = groupCountersByLabel(parsed, 'gateway_errors_total', 'code');
    const errorItems = Object.entries(errorGroups)
      .sort((a, b) => b[1] - a[1])
      .map(([code, value]) => ({ label: code, value, color: 'var(--chart-error)' }));
    renderBarChartSvg($('chart-error-codes'), errorItems, { labelWidth: 80 });
    renderLegend($('chart-error-codes-legend'), errorItems);
  }

  function defaultEndpoints() {
    return [
      { path: '/health', method: 'GET', phase: 2, available: true },
      { path: '/metrics', method: 'GET', phase: 2, available: true },
      { path: '/ready', method: 'GET', phase: 3, available: true },
      { path: '/v1/status', method: 'GET', phase: 3, available: true },
      { path: '/dashboard', method: 'GET', phase: 3, available: true },
      { path: '/v1/capabilities', method: 'GET', phase: 5, available: false },
      { path: '/v1/ai/generate', method: 'POST', phase: 5, available: false },
    ];
  }

  function renderEndpointRow(ep) {
    const disabled = !ep.available;
    const needsAuth = requiresAuth(ep.path);
    const result = state.lastTryResult?.path === ep.path ? state.lastTryResult : null;
    const statusText = disabled
      ? `Phase ${ep.phase}`
      : result
        ? `HTTP ${result.status}`
        : '—';
    const methodClass = ep.method.toLowerCase();
    const runnerNote = ep.runner_id
      ? `<span class="explorer-table__runner" title="Proxies runner /v1/models">runner ${escapeHtml(ep.runner_id)}</span>`
      : '';
    const authBadge = needsAuth
      ? `<span class="explorer-table__auth" title="Requires JWT + ai.access">🔒</span>`
      : '';

    return `
      <tr class="explorer-table__row${disabled ? ' explorer-table__row--disabled' : ''}" data-path="${escapeHtml(ep.path)}">
        <td><code class="method method--${methodClass}">${escapeHtml(ep.method)}</code></td>
        <td class="mono">${escapeHtml(ep.path)}${authBadge}${runnerNote}</td>
        <td><span class="phase-tag">P${ep.phase}</span></td>
        <td class="explorer-table__status">${escapeHtml(statusText)}</td>
        <td>
          <button type="button" class="btn btn--try" data-path="${escapeHtml(ep.path)}" data-method="${escapeHtml(ep.method)}" ${disabled ? 'disabled' : ''}>Try it</button>
        </td>
      </tr>`;
  }

  function renderEndpointResponsePanel() {
    const panel = $('endpoint-response-panel');
    if (!panel) return;

    const result = state.lastTryResult;
    if (!result) {
      panel.hidden = true;
      return;
    }

    panel.hidden = false;
    const statusEl = $('endpoint-response-status');
    if (statusEl) {
      statusEl.textContent = result.status ? `HTTP ${result.status}` : 'Error';
      statusEl.dataset.status = String(result.status || 0);
    }
    setText($('endpoint-response-path'), `${result.method || 'GET'} ${result.path}`);
    const reqIdEl = $('endpoint-response-request-id');
    if (reqIdEl) {
      if (result.requestId) {
        reqIdEl.hidden = false;
        reqIdEl.textContent = result.requestId;
      } else {
        reqIdEl.hidden = true;
        reqIdEl.textContent = '';
      }
    }
    setText($('endpoint-response-body'), truncate(formatBody(result.body), 8000));
  }

  function renderEndpointExplorer() {
    const tbody = $('endpoint-list');
    const empty = $('endpoint-empty');
    if (!tbody) return;

    const endpoints = state.status?.endpoints || defaultEndpoints();

    if (!endpoints.length) {
      tbody.innerHTML = '';
      if (empty) empty.hidden = false;
      renderEndpointResponsePanel();
      return;
    }

    if (empty) empty.hidden = true;

    tbody.innerHTML = endpoints.map(renderEndpointRow).join('');

    $qa('.btn--try', tbody).forEach((btn) => {
      btn.addEventListener('click', () => tryEndpoint(btn.dataset.path, btn.dataset.method, btn));
    });

    renderEndpointResponsePanel();
  }

  function formatBody(body) {
    if (body == null) return '';
    if (typeof body === 'object') return JSON.stringify(body, null, 2);
    return String(body);
  }

  function truncate(str, max) {
    if (str.length <= max) return str;
    return `${str.slice(0, max)}\n… (truncated)`;
  }

  function showResponsePanel(path, method, status, body, requestId) {
    state.lastTryResult = { path, method: method || 'GET', status, body, requestId: requestId || null };
    if (requestId) state.lastRequestId = requestId;
    renderEndpointResponsePanel();
  }

  async function tryEndpoint(path, method, btn) {
    if (btn) {
      btn.disabled = true;
      btn.textContent = '…';
    }
    try {
      const result = await fetchEndpoint(path, { method: method || 'GET' });
      if (result.requestId) state.lastRequestId = result.requestId;
      showResponsePanel(path, method, result.status, result.body, result.requestId);
    } catch (err) {
      showResponsePanel(path, method, 0, String(err.message || err));
    } finally {
      if (btn) {
        btn.disabled = false;
        btn.textContent = 'Try it';
      }
      renderEndpointExplorer();
    }
  }

  function renderAuthPanel() {
    const statusEl = $('auth-status');
    const roleEl = $('auth-staff-role');
    const accessEl = $('auth-ai-access');
    const input = $('auth-token-input');

    if (input && document.activeElement !== input) {
      input.value = state.authToken || '';
    }

    if (!state.authToken) {
      setText(statusEl, 'No token — protected polls return 401');
      setText(roleEl, '—');
      setText(accessEl, '—');
      return;
    }

    setText(statusEl, 'Token saved');
    setText(roleEl, state.auth.staffRole || '(no staff_role claim)');
    if (state.auth.hasAiAccess === true) setText(accessEl, 'granted');
    else if (state.auth.hasAiAccess === false) setText(accessEl, 'denied');
    else setText(accessEl, 'unknown role');
  }

  function renderSecurity() {
    const cfg = state.status?.config_safe;
    const gw = state.status?.gateway;

    setText($('gateway-uptime'), gw?.uptime_s != null ? formatUptime(gw.uptime_s) : '—');
    setText($('gateway-version'), gw?.version ? `· v${gw.version}` : '');

    const fields = [
      ['config-port', cfg?.port ?? '—'],
      ['config-log-dir', cfg?.log_dir ?? '—'],
      ['config-health-poll', cfg?.health_poll_interval_s != null ? `${cfg.health_poll_interval_s}s` : '—'],
      ['config-unreachable-after', cfg?.unreachable_after_failures ?? '—'],
      [
        'config-allowed-origins',
        cfg && Array.isArray(cfg.allowed_origins) && cfg.allowed_origins.length
          ? cfg.allowed_origins.join(', ')
          : '—',
      ],
      ['config-streaming', cfg ? (cfg.streaming_enabled ? 'enabled' : 'disabled') : '—'],
      ['config-multi-command', cfg ? (cfg.enable_multi_command_plans ? 'enabled' : 'disabled') : '—'],
      ['config-push-reg', cfg ? (cfg.enable_push_registration ? 'enabled' : 'disabled') : '—'],
      ['config-log-verbatim', cfg ? (cfg.log_verbatim ? 'yes' : 'no') : '—'],
    ];

    for (const [id, value] of fields) {
      setText($(id), value);
    }

    renderAuthPanel();
  }

  async function probePhase(descriptor) {
    if (!descriptor.probe) return null;
    const { path, method, expectStatus, skipAuth } = descriptor.probe;
    try {
      const res = await fetchEndpoint(path, { method, timeoutMs: 4000, skipAuth: !!skipAuth });
      const expected = Array.isArray(expectStatus) ? expectStatus : [expectStatus];
      return expected.includes(res.status);
    } catch {
      return false;
    }
  }

  async function updatePhaseGating() {
    const gw = state.status?.gateway;
    const activePhase = gw?.phase_active ?? 3;

    for (const [numStr, descriptor] of Object.entries(PHASES)) {
      const num = Number(numStr);
      let enabled = num <= activePhase;

      if (descriptor.probe && num > activePhase) {
        if (state.phaseProbes[num] === undefined) {
          state.phaseProbes[num] = await probePhase(descriptor);
        }
        enabled = state.phaseProbes[num];
      }

      for (const sectionId of descriptor.sections) {
        const section = $(sectionId);
        if (!section) continue;

        const isFuturePanel = section.classList.contains('panel--future');
        const show = enabled || !isFuturePanel;

        section.classList.toggle('phase-disabled', !show);
        section.classList.toggle('phase-enabled', enabled);
        section.setAttribute('aria-hidden', show ? 'false' : 'true');
        if (isFuturePanel) section.hidden = !enabled;
      }
    }

    if (state.phaseProbes[5]) {
      const capPlaceholder = $('capabilities-placeholder');
      if (capPlaceholder) capPlaceholder.textContent = 'Capabilities endpoint is live — wire UI to response JSON.';
    }
  }

  async function pollOnce() {
    if (!state.authToken) {
      try {
        const anon = await fetchEndpoint('/ready', { skipAuth: true, timeoutMs: 4000 });
        state.auth.enforced = anon.status === 401;
        state.auth.saw401 = anon.status === 401;
        if (anon.status === 401) state.statusAuthError = anon.body;
      } catch {
        state.auth.enforced = false;
      }
    } else {
      state.auth.enforced = true;
    }

    const results = await Promise.allSettled([
      state.authToken
        ? fetchEndpoint('/v1/status').then((r) => ({ kind: 'status', ...r }))
        : Promise.resolve({ kind: 'status', ok: false, status: 401, body: state.statusAuthError }),
      fetchEndpoint('/health').then((r) => ({ kind: 'health', ...r })),
      fetchEndpoint('/ready').then((r) => ({ kind: 'ready', ...r })),
      fetchEndpoint('/metrics').then((r) => ({ kind: 'metrics', ...r })),
    ]);

    let anySuccess = false;
    state.lastPollAt = Date.now();

    for (const result of results) {
      if (result.status !== 'fulfilled') continue;
      const data = result.value;
      anySuccess = true;

      switch (data.kind) {
        case 'status':
          if (data.ok) {
            state.status = data.body;
            state.statusAuthError = null;
          } else if (data.status === 401) {
            state.statusAuthError = data.body;
            state.auth.saw401 = true;
          }
          break;
        case 'health':
          state.health = { ok: data.ok, status: data.status, body: data.body };
          if (data.requestId) state.lastRequestId = data.requestId;
          break;
        case 'ready':
          state.ready = { ok: data.ok, status: data.status, body: data.body };
          if (data.requestId) state.lastRequestId = data.requestId;
          if (data.status === 401) state.auth.saw401 = true;
          break;
        case 'metrics':
          state.metricsRaw = typeof data.body === 'string' ? data.body : '';
          state.metricsParsed = parsePrometheus(state.metricsRaw);
          updateRequestHistory(state.metricsParsed);
          break;
      }
    }

    if (anySuccess) state.lastSuccessAt = Date.now();

    renderHeader();
    renderArchitecture();
    renderOverview();
    renderPollerMeta();
    renderRunners();
    renderMetrics();
    renderEndpointExplorer();
    renderPhaseCoverage();
    renderSecurity();
    renderErrorEnvelope();
    await updatePhaseGating();
  }

  function startPolling() {
    stopPolling();
    pollOnce();
    state.pollTimer = setInterval(pollOnce, state.pollIntervalMs);
  }

  function stopPolling() {
    if (state.pollTimer) {
      clearInterval(state.pollTimer);
      state.pollTimer = null;
    }
  }

  function setPollInterval(seconds) {
    const s = Math.max(2, Math.min(60, Number(seconds) || DEFAULT_POLL_INTERVAL_S));
    state.pollIntervalMs = s * 1000;
    try {
      localStorage.setItem('dashboard_poll_interval_s', String(s));
    } catch {
      /* ignore */
    }
    const input = $('poll-interval');
    if (input) input.value = String(s);
    startPolling();
  }

  function bindControls() {
    const refreshBtn = $('refresh-btn');
    if (refreshBtn) {
      refreshBtn.addEventListener('click', () => {
        refreshBtn.disabled = true;
        pollOnce().finally(() => {
          refreshBtn.disabled = false;
        });
      });
    }

    const intervalInput = $('poll-interval');
    if (intervalInput) {
      intervalInput.addEventListener('change', () => setPollInterval(intervalInput.value));
      intervalInput.addEventListener('input', () => {
        clearTimeout(intervalInput._debounce);
        intervalInput._debounce = setTimeout(() => setPollInterval(intervalInput.value), 400);
      });
    }

    const pollAllBtn = $('poll-all-runners-btn');
    if (pollAllBtn) {
      pollAllBtn.addEventListener('click', async () => {
        const runners = state.status?.runners || [];
        pollAllBtn.disabled = true;
        pollAllBtn.textContent = 'Polling…';
        for (const runner of runners) {
          await pollRunnerModels(runner.id);
        }
        pollAllBtn.disabled = false;
        pollAllBtn.textContent = 'Poll all /v1/models';
      });
    }

    document.addEventListener('visibilitychange', () => {
      if (document.hidden) stopPolling();
      else startPolling();
    });

    const authSave = $('auth-token-save');
    const authClear = $('auth-token-clear');
    const authInput = $('auth-token-input');

    if (authSave && authInput) {
      authSave.addEventListener('click', () => {
        saveAuthToken(authInput.value);
        pollOnce();
      });
    }

    if (authClear) {
      authClear.addEventListener('click', () => {
        if (authInput) authInput.value = '';
        saveAuthToken('');
        pollOnce();
      });
    }
  }

  function loadSavedInterval() {
    try {
      const saved = localStorage.getItem('dashboard_poll_interval_s');
      if (saved) return Number(saved);
    } catch {
      /* ignore */
    }
    return DEFAULT_POLL_INTERVAL_S;
  }

  function init() {
    state.authToken = loadAuthToken();
    updateAuthStateFromToken();
    bindControls();
    setPollInterval(loadSavedInterval());
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }

  window.AIControlPlane = {
    PHASES,
    state,
    pollOnce,
    parsePrometheus,
    setPollInterval,
  };
})();
