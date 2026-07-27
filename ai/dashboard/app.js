/**
 * AI Gateway Signal Monitor — zero-build control plane dashboard.
 * Modules: state · auth · api · poll · trace · render
 */
(function () {
  'use strict';

  const TOKEN_KEY = 'dashboard_jwt_token';
  const TOKEN_NO_AI_KEY = 'dashboard_jwt_no_ai';
  const USERNAME_KEY = 'dashboard_auth_username';
  const DEFAULT_POLL_S = 0;
  const TRACE_MAX_ROWS = 200;
  const PROTECTED_PREFIXES = ['/ready', '/v1/status', '/v1/runners/', '/v1/capabilities', '/v1/ai/generate', '/v1/trace/'];
  const LIFECYCLE = ['UNKNOWN', 'STARTING', 'READY', 'BUSY', 'DEGRADED', 'UNREACHABLE'];
  const DEFAULT_AI_ACCESS = { administrator: true, doctor: true, receptionist: false, lab_staff: false };
  const DIRECTION_FLOW = {
    client_to_gateway: { from: 'client', to: 'gateway' },
    gateway_to_client: { from: 'gateway', to: 'client' },
    gateway_to_runner: { from: 'gateway', to: 'runner' },
    runner_to_gateway: { from: 'runner', to: 'gateway' },
  };
  const ENTITY_COL = { client: 1, gateway: 2, runner: 3 };
  const ENTITY_LABELS = { client: 'Client', gateway: 'Gateway', runner: 'Runner' };

  const CLIENT_REQUESTS = [
    {
      id: 'health',
      method: 'GET',
      path: '/health',
      auth: false,
      desc: 'Liveness — process is up (does not check runners)',
    },
    {
      id: 'metrics',
      method: 'GET',
      path: '/metrics',
      auth: false,
      desc: 'Prometheus exposition for monitoring scrapers',
    },
    {
      id: 'ready',
      method: 'GET',
      path: '/ready',
      auth: true,
      desc: 'Readiness — 200 only when at least one runner is READY',
    },
    {
      id: 'capabilities',
      method: 'GET',
      path: '/v1/capabilities',
      auth: true,
      desc: 'Aggregate capability snapshot for clinic clients',
    },
    {
      id: 'status',
      method: 'GET',
      path: '/v1/status',
      auth: true,
      desc: 'Control-plane snapshot (operators; also fills runner registry below)',
    },
    {
      id: 'generate',
      method: 'POST',
      path: '/v1/ai/generate',
      auth: true,
      desc: 'Scheduling command proposals (non-streaming + SSE streaming)',
      defaultBody: JSON.stringify(defaultGenerateBody('book Ahmed with Dr Ali tomorrow 5pm')),
    },
    {
      id: 'runner-models',
      method: 'GET',
      path: '/v1/runners/{runner_id}/models',
      auth: true,
      desc: 'Proxy runner model list through the gateway',
      runnerId: true,
    },
  ];

  const CATALOG_COMMAND_TYPES = [
    'create_appointment',
    'reschedule_appointment',
    'cancel_appointment',
    'update_appointment_status',
  ];

  const GENERATE_PRESETS = {
    create: 'book Ahmed Hassan with Dr Ali tomorrow 5pm',
    reschedule: "move Ahmed's appointment to Thursday 3pm",
    cancel: "cancel Ahmed's appointment tomorrow",
    status: "mark Ahmed's visit as checked in",
  };

  function defaultGenerateContext(extra = {}) {
    return {
      now: new Date().toISOString(),
      ...extra,
    };
  }

  function defaultGenerateBody(prompt = GENERATE_PRESETS.create, extra = {}) {
    return {
      task: 'command',
      prompt,
      context: defaultGenerateContext(extra.context),
      options: { stream: false, ...(extra.options || {}) },
    };
  }

  const $ = (id) => document.getElementById(id);

  const state = {
    token: null,
    staffRole: null,
    hasAiAccess: false,
    tokenExpiresAt: null,
    pollTimer: null,
    pollIntervalS: DEFAULT_POLL_S,
    health: { ok: false },
    ready: { ok: false, status: null, body: null },
    status: null,
    capabilities: null,
    metricsRaw: '',
    metricsParsed: null,
    traceConfig: null,
    traceEvents: [],
    tracePaused: false,
    tracePausedBuffer: [],
    traceSource: null,
    traceAbort: null,
    traceFilters: {
      direction: null,
      kind: null,
      runner_id: null,
      status_class: null,
      path_prefix: '',
    },
    traceEventTotal: 0,
    traceSeqCounter: 0,
    selectedTraceId: null,
    inspectorTab: 'overview',
    traceFilterPanelOpen: false,
    traceStreamConnected: false,
    roleMap: { ...DEFAULT_AI_ACCESS },
    authConfig: null,
    tokenNoAi: null,
    probeResults: {},
    probeAbort: null,
    matrixResults: {},
    matrixRunning: false,
    matrixSelectedFeatures: new Set(),
    matrixActiveTab: 'features',
    matrixHeaderCaptureAll: false,
    generateAbort: null,
  };

  /* ── Auth ─────────────────────────────────────────────── */

  function loadToken() {
    try {
      return localStorage.getItem(TOKEN_KEY) || null;
    } catch {
      return null;
    }
  }

  function saveToken(token) {
    try {
      if (token) localStorage.setItem(TOKEN_KEY, token);
      else localStorage.removeItem(TOKEN_KEY);
    } catch { /* ignore */ }
  }

  function loadTokenNoAi() {
    try {
      return localStorage.getItem(TOKEN_NO_AI_KEY) || null;
    } catch {
      return null;
    }
  }

  function saveTokenNoAi(token) {
    try {
      if (token) localStorage.setItem(TOKEN_NO_AI_KEY, token);
      else localStorage.removeItem(TOKEN_NO_AI_KEY);
    } catch { /* ignore */ }
  }

  function decodeJwtPayload(token) {
    try {
      const part = token.split('.')[1];
      const json = atob(part.replace(/-/g, '+').replace(/_/g, '/'));
      return JSON.parse(json);
    } catch {
      return null;
    }
  }

  function applyToken(token) {
    state.token = token;
    state.staffRole = null;
    state.hasAiAccess = false;
    state.tokenExpiresAt = null;
    if (!token) {
      renderAuthVitals();
      disconnectTrace();
      return;
    }
    const payload = decodeJwtPayload(token);
    if (payload) {
      state.staffRole = payload.staff_role || null;
      state.tokenExpiresAt = payload.exp ? payload.exp * 1000 : null;
      state.hasAiAccess = !!(state.staffRole && state.roleMap[state.staffRole]);
    }
    renderAuthVitals();
  }

  function renderAuthVitals() {
    const vital = $('vital-auth');
    const val = $('vital-auth-value');
    const role = $('vital-auth-role');
    if (!state.token) {
      vital.dataset.state = 'warn';
      val.textContent = 'Unsigned';
      role.textContent = 'Sign in to call protected client routes';
      renderGenerateAuthHint();
      return;
    }
    vital.dataset.state = state.hasAiAccess ? 'ok' : 'warn';
    val.textContent = state.hasAiAccess ? 'Authenticated' : 'No ai.access';
    role.textContent = state.staffRole || 'unknown role';
    $('auth-role').textContent = state.staffRole || '—';
    $('auth-access').textContent = state.hasAiAccess ? 'yes' : 'no';
    $('auth-expires').textContent = state.tokenExpiresAt
      ? new Date(state.tokenExpiresAt).toLocaleString()
      : '—';
    renderGenerateAuthHint();
  }

  function isProtected(path) {
    return PROTECTED_PREFIXES.some((p) => path === p || path.startsWith(p));
  }

  async function fetchAuthConfig() {
    try {
      const res = await fetch('/v1/dashboard/auth-config');
      if (!res.ok) return;
      state.authConfig = await res.json();
      const section = $('auth-sign-in-section');
      if (state.authConfig.sign_in_enabled) {
        section.hidden = false;
      }
      if (state.authConfig.auto_sign_in) {
        await autoSignIn();
      }
    } catch { /* offline */ }
  }

  async function autoSignIn() {
    try {
      const res = await fetch('/v1/dashboard/auto-sign-in', { method: 'POST' });
      if (!res.ok) return;
      const body = await res.json();
      if (body.access_token) {
        $('auth-token').value = body.access_token;
        saveToken(body.access_token);
        applyToken(body.access_token);
        if (body.staff_role) state.roleMap[body.staff_role] = body.has_ai_access;
        state.staffRole = body.staff_role;
        state.hasAiAccess = body.has_ai_access;
        renderAuthVitals();
        renderClientRequests();
      }
    } catch { /* ignore */ }
  }

  async function signIn() {
    const msg = $('auth-sign-in-message');
    msg.textContent = '';
    msg.dataset.type = '';
    const username = $('auth-username').value.trim();
    const password = $('auth-password').value;
    if (!username || !password) {
      msg.textContent = 'Enter username and password to sign in.';
      return;
    }
    try {
      const res = await fetch('/v1/dashboard/sign-in', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ username, password }),
      });
      const body = await res.json().catch(() => ({}));
      if (!res.ok) {
        const err = body.error?.message || 'Sign-in failed. Check clinic credentials.';
        msg.textContent = err;
        return;
      }
      $('auth-token').value = body.access_token;
      saveToken(body.access_token);
      applyToken(body.access_token);
      state.staffRole = body.staff_role;
      state.hasAiAccess = body.has_ai_access;
      renderAuthVitals();
      renderClientRequests();
      msg.dataset.type = 'ok';
      msg.textContent = 'Signed in. Use Client requests to call protected routes.';
    } catch {
      msg.textContent = 'Could not reach the gateway. Start the gateway and try again.';
    }
  }

  /* ── API ──────────────────────────────────────────────── */

  async function apiFetch(path, options = {}) {
    const headers = { ...(options.headers || {}) };
    if (state.token && isProtected(path)) {
      headers.Authorization = `Bearer ${state.token}`;
    }
    const res = await fetch(path, { ...options, headers });
    const requestId = res.headers.get('X-Request-ID');
    let body = null;
    const ct = res.headers.get('content-type') || '';
    if (ct.includes('application/json')) {
      body = await res.json().catch(() => null);
    } else if (ct.includes('text/')) {
      body = await res.text();
    }
    return { res, body, requestId };
  }

  function getByPath(obj, path) {
    if (!path) return obj;
    return String(path).split('.').reduce((o, k) => (o == null ? undefined : o[k]), obj);
  }

  async function probeFetch(probe, options = {}) {
    const headers = { ...(options.headers || {}) };
    if (probe.auth === 'jwt' && state.token) {
      headers.Authorization = `Bearer ${state.token}`;
    } else if (probe.auth === 'jwt_no_ai' && state.tokenNoAi) {
      headers.Authorization = `Bearer ${state.tokenNoAi}`;
    }
    const res = await fetch(probe.path, { ...options, headers });
    const requestId = res.headers.get('X-Request-ID');
    let body = null;
    const ct = res.headers.get('content-type') || '';
    if (ct.includes('application/json')) {
      body = await res.json().catch(() => null);
    } else if (ct.includes('text/')) {
      body = await res.text();
    }
    return { res, body, requestId };
  }

  function evaluateExpect(expect, res, body) {
    if (!expect) return { pass: null, results: [] };
    const results = [];
    let pass = true;

    if (expect.status != null) {
      const allowed = Array.isArray(expect.status) ? expect.status : [expect.status];
      const ok = allowed.includes(res.status);
      results.push({
        label: `HTTP ${allowed.join(' or ')}`,
        ok,
        actual: String(res.status),
      });
      if (!ok) pass = false;
    }

    if (expect.error_code != null) {
      const actual = body?.error?.code;
      const ok = actual === expect.error_code;
      results.push({
        label: `error.code == ${expect.error_code}`,
        ok,
        actual: actual ?? '—',
      });
      if (!ok) pass = false;
    }

    if (expect.body_status != null) {
      const actual = body?.status;
      const ok = actual === expect.body_status;
      results.push({
        label: `body.status == ${expect.body_status}`,
        ok,
        actual: actual ?? '—',
      });
      if (!ok) pass = false;
    }

    if (expect.fields) {
      for (const [path, expected] of Object.entries(expect.fields)) {
        const actual = getByPath(body, path);
        const ok = JSON.stringify(actual) === JSON.stringify(expected);
        results.push({
          label: `${path} matches expected`,
          ok,
          actual: actual === undefined ? '—' : JSON.stringify(actual),
        });
        if (!ok) pass = false;
      }
    }

    if (expect.body_contains) {
      for (const [path, expected] of Object.entries(expect.body_contains)) {
        const actual = getByPath(body, path);
        const ok = actual === expected;
        results.push({
          label: `${path} == ${JSON.stringify(expected)}`,
          ok,
          actual: actual === undefined ? '—' : JSON.stringify(actual),
        });
        if (!ok) pass = false;
      }
    }

    if (expect.min_array_length) {
      for (const [path, min] of Object.entries(expect.min_array_length)) {
        const arr = getByPath(body, path);
        const ok = Array.isArray(arr) && arr.length >= min;
        results.push({
          label: `${path}.length >= ${min}`,
          ok,
          actual: Array.isArray(arr) ? String(arr.length) : 'not an array',
        });
        if (!ok) pass = false;
      }
    }

    return { pass, results };
  }

  /* ── Metrics parser ───────────────────────────────────── */

  function parsePrometheus(text) {
    const counters = {};
    const gauges = {};
    const lines = (text || '').split('\n');
    for (const line of lines) {
      if (!line || line.startsWith('#')) continue;
      const m = line.match(/^([a-zA-Z_:][a-zA-Z0-9_:]*)(\{([^}]*)\})?\s+([+-]?\d+(?:\.\d+)?(?:e[+-]?\d+)?)/);
      if (!m) continue;
      const name = m[1];
      const labels = {};
      if (m[3]) {
        m[3].replace(/([a-zA-Z_]+)="([^"]*)"/g, (_, k, v) => { labels[k] = v; });
      }
      const value = parseFloat(m[4]);
      const entry = { name, labels, value };
      if (name.endsWith('_total') || name.includes('counter')) {
        const key = `${name}|${JSON.stringify(labels)}`;
        counters[key] = entry;
      } else {
        const key = `${name}|${JSON.stringify(labels)}`;
        gauges[key] = entry;
      }
    }
    return { counters, gauges };
  }

  function sumByName(parsed, name) {
    if (!parsed) return 0;
    return Object.values(parsed.counters)
      .filter((e) => e.name === name)
      .reduce((s, e) => s + e.value, 0);
  }

  function gaugesByLabel(parsed, name, label) {
    const out = {};
    if (!parsed) return out;
    for (const e of Object.values(parsed.gauges)) {
      if (e.name === name && e.labels[label]) {
        out[e.labels[label]] = e.value;
      }
    }
    return out;
  }

  /* ── Poll ─────────────────────────────────────────────── */

  async function pollHealth() {
    try {
      const { res } = await apiFetch('/health');
      state.health.ok = res.ok;
    } catch {
      state.health.ok = false;
    }
    const el = $('vital-health');
    const val = $('vital-health-value');
    el.dataset.state = state.health.ok ? 'ok' : 'error';
    val.textContent = state.health.ok ? 'Up' : 'Down';
  }

  async function pollReady() {
    try {
      const { res, body } = await apiFetch('/ready');
      state.ready = { ok: res.ok, status: res.status, body };
    } catch {
      state.ready = { ok: false, status: 0, body: null };
    }
    const el = $('vital-ready');
    const val = $('vital-ready-value');
    if (!state.token) {
      el.dataset.state = 'warn';
      val.textContent = 'Needs JWT';
      return;
    }
    el.dataset.state = state.ready.ok ? 'ok' : 'error';
    val.textContent = state.ready.ok ? 'Ready' : `Not ready (${state.ready.status})`;
  }

  async function pollStatus() {
    if (!state.token) {
      state.status = null;
      return;
    }
    try {
      const { res, body } = await apiFetch('/v1/status');
      if (res.ok) state.status = body;
      else state.status = null;
    } catch {
      state.status = null;
    }
    if (state.status?.gateway?.uptime_s != null) {
      $('vital-uptime-value').textContent = formatUptime(state.status.gateway.uptime_s);
    }
    renderRunners();
    renderSecurity();
    renderEndpointCatalog();
    renderModelsActions();
    updateRegistryMode();
    updateDiagramRunnerLabel();
  }

  async function pollCapabilities() {
    if (!state.token) {
      state.capabilities = null;
      $('capabilities-body').innerHTML = '<p class="panel-placeholder">Authenticate to load capabilities mirror.</p>';
      return;
    }
    try {
      const { res, body } = await apiFetch('/v1/capabilities');
      state.capabilities = res.ok ? { ok: true, body } : { ok: false };
    } catch {
      state.capabilities = { ok: false };
    }
    renderCapabilities();
  }

  async function pollMetrics() {
    try {
      const { res, body } = await apiFetch('/metrics');
      if (res.ok && typeof body === 'string') {
        state.metricsRaw = body;
        state.metricsParsed = parsePrometheus(body);
      }
    } catch {
      state.metricsParsed = null;
    }
    renderMetrics();
  }

  async function pollTraceConfig() {
    if (!state.token) return;
    try {
      const { res, body } = await apiFetch('/v1/trace/config');
      if (res.ok) {
        state.traceConfig = body;
        renderTraceFilters();
      }
    } catch { /* ignore */ }
  }

  function formatUptime(seconds) {
    const h = Math.floor(seconds / 3600);
    const m = Math.floor((seconds % 3600) / 60);
    const s = Math.floor(seconds % 60);
    if (h > 0) return `${h}h ${m}m`;
    if (m > 0) return `${m}m ${s}s`;
    return `${s}s`;
  }

  async function refreshAll() {
    await Promise.all([
      pollHealth(),
      pollReady(),
      pollStatus(),
      pollCapabilities(),
      pollMetrics(),
      pollTraceConfig(),
    ]);
    renderFeatureMatrix();
    $('last-refresh').textContent = new Date().toLocaleTimeString();
  }

  function startPolling() {
    clearInterval(state.pollTimer);
    const interval = Number($('poll-interval').value);
    if (!Number.isFinite(interval) || interval <= 0) {
      state.pollIntervalS = 0;
      return;
    }
    const clamped = Math.max(2, Math.min(60, interval));
    state.pollIntervalS = clamped;
    state.pollTimer = setInterval(refreshAll, clamped * 1000);
  }

  /* ── Trace SSE ────────────────────────────────────────── */

  function buildTraceStreamUrl() {
    const params = new URLSearchParams();
    const f = state.traceFilters;
    if (f.direction) params.set('direction', f.direction);
    if (f.kind) params.set('kind', f.kind);
    if (f.runner_id) params.set('runner_id', f.runner_id);
    if (f.status_class) params.set('status_class', f.status_class);
    if (f.path_prefix) params.set('path_prefix', f.path_prefix);
    const qs = params.toString();
    return `/v1/trace/stream${qs ? `?${qs}` : ''}`;
  }

  function disconnectTrace() {
    if (state.traceAbort) {
      state.traceAbort.abort();
      state.traceAbort = null;
    }
    state.traceSource = null;
    state.traceStreamConnected = false;
    const conn = $('trace-connection');
    conn.dataset.state = 'off';
    conn.textContent = 'Stream off';
    const pauseBtn = $('trace-pause-btn');
    if (pauseBtn) {
      pauseBtn.disabled = true;
      pauseBtn.setAttribute('aria-pressed', 'false');
      pauseBtn.textContent = 'Pause';
    }
    state.tracePaused = false;
    const connectBtn = $('trace-connect-btn');
    if (connectBtn) connectBtn.textContent = 'Connect stream';
  }

  function connectTrace() {
    disconnectTrace();
    if (!state.token || !state.hasAiAccess) {
      $('trace-empty').textContent = 'Sign in with ai.access to watch live gateway traffic.';
      return;
    }
    const controller = new AbortController();
    state.traceAbort = controller;
    state.traceSource = true;
    state.traceStreamConnected = true;

    const conn = $('trace-connection');
    conn.dataset.state = state.tracePaused ? 'paused' : 'live';
    conn.textContent = state.tracePaused ? 'Paused' : 'Connecting…';
    const pauseBtn = $('trace-pause-btn');
    if (pauseBtn) pauseBtn.disabled = false;
    const connectBtn = $('trace-connect-btn');
    if (connectBtn) connectBtn.textContent = 'Disconnect stream';

    loadTraceHistory();
    runTraceStream(controller);
  }

  async function runTraceStream(controller) {
    const url = buildTraceStreamUrl();
    try {
      const res = await fetch(url, {
        headers: { Authorization: `Bearer ${state.token}` },
        signal: controller.signal,
      });
      if (!res.ok) {
        throw new Error(`stream ${res.status}`);
      }
      const conn = $('trace-connection');
      conn.dataset.state = state.tracePaused ? 'paused' : 'live';
      conn.textContent = state.tracePaused ? 'Paused' : 'Live';
      $('trace-empty').hidden = state.traceEvents.length > 0;

      const reader = res.body.getReader();
      const decoder = new TextDecoder();
      let buffer = '';

      while (true) {
        const { done, value } = await reader.read();
        if (done) break;
        buffer += decoder.decode(value, { stream: true });
        const chunks = buffer.split('\n\n');
        buffer = chunks.pop() || '';
        for (const chunk of chunks) {
          for (const line of chunk.split('\n')) {
            if (!line.startsWith('data:')) continue;
            const raw = line.replace(/^data:\s?/, '').trim();
            if (!raw) continue;
            try {
              const event = JSON.parse(raw);
              if (state.tracePaused) {
                state.tracePausedBuffer.push(event);
              } else {
                appendTraceEvent(event, true);
              }
            } catch { /* ignore */ }
          }
        }
      }
    } catch (err) {
      if (err.name === 'AbortError') return;
      const conn = $('trace-connection');
      conn.dataset.state = 'error';
      conn.textContent = 'Stream error — check JWT and refresh';
    }
  }

  async function loadTraceHistory() {
    if (!state.token) return;
    try {
      const params = new URLSearchParams({ limit: '50' });
      const f = state.traceFilters;
      if (f.direction) params.set('direction', f.direction);
      if (f.kind) params.set('kind', f.kind);
      if (f.runner_id) params.set('runner_id', f.runner_id);
      if (f.status_class) params.set('status_class', f.status_class);
      if (f.path_prefix) params.set('path_prefix', f.path_prefix);
      const { res, body } = await apiFetch(`/v1/trace/events?${params}`);
      if (res.ok && body.events) {
        deselectTraceEvent();
        state.traceEvents = [];
        state.traceEventTotal = body.events.length;
        state.traceSeqCounter = 0;
        state.tracePausedBuffer = [];
        $('trace-stream').querySelectorAll('.trace-seq-row').forEach((el) => el.remove());
        body.events.slice().reverse().forEach((e) => appendTraceEvent(e, false));
        updateTraceLogCount();
      }
    } catch { /* ignore */ }
  }

  function statusClass(code) {
    if (code == null) return 'unknown';
    if (code < 400) return 'ok';
    if (code < 500) return 'client_error';
    return 'server_error';
  }

  function resolveEntityLabel(entity, event) {
    if (entity === 'runner') {
      return event.runner_id || $('runner-node-id')?.textContent || ENTITY_LABELS.runner;
    }
    return ENTITY_LABELS[entity] || entity;
  }

  function resolveFlow(event) {
    const flow = DIRECTION_FLOW[event.direction];
    if (!flow) return { from: '—', to: '—', fromKey: '', toKey: '' };
    return {
      from: resolveEntityLabel(flow.from, event),
      to: resolveEntityLabel(flow.to, event),
      fromKey: flow.from,
      toKey: flow.to,
    };
  }


  function messageSpan(fromKey, toKey) {
    const fromCol = ENTITY_COL[fromKey] || 1;
    const toCol = ENTITY_COL[toKey] || 2;
    const start = Math.min(fromCol, toCol);
    const end = Math.max(fromCol, toCol) + 1;
    return {
      gridColumn: `${start} / ${end}`,
      reverse: fromCol > toCol,
    };
  }

  function findTraceEvent(eventId) {
    return state.traceEvents.find((e) => (e.id || '') === eventId) || null;
  }

  function formatJsonDisplay(value) {
    if (value == null || value === '') return null;
    if (typeof value === 'object') {
      try {
        return JSON.stringify(value, null, 2);
      } catch {
        return String(value);
      }
    }
    const text = String(value);
    try {
      return JSON.stringify(JSON.parse(text), null, 2);
    } catch {
      return text;
    }
  }

  function resolveBodyField(event, field) {
    const body = event[field];
    if (body != null && body !== '') return body;
    const summaryField = field === 'request_body' ? 'request_summary' : 'response_summary';
    const summary = event[summaryField];
    if (summary != null && summary !== '') return summary;
    return null;
  }

  function renderInspectorFlow(flow) {
    const el = $('trace-inspector-flow');
    if (!el) return;
    if (!flow.fromKey || !flow.toKey) {
      el.innerHTML = '';
      return;
    }
    const nodes = [
      { key: flow.fromKey, label: flow.from },
      { key: flow.toKey, label: flow.to },
    ];
    el.innerHTML = nodes.map((node, i) => {
      const active = ' trace-inspector__node--active';
      const arrow = i === 0
        ? `<span class="trace-inspector__arrow" aria-hidden="true">→</span>`
        : '';
      return `${arrow}<span class="trace-inspector__node${active}">${escapeHtml(node.label)}</span>`;
    }).join('');
  }

  function setInspectorTab(tab) {
    state.inspectorTab = tab;
    document.querySelectorAll('.trace-inspector__tab').forEach((btn) => {
      const on = btn.dataset.tab === tab;
      btn.setAttribute('aria-selected', on ? 'true' : 'false');
    });
    document.querySelectorAll('.trace-inspector__pane').forEach((pane) => {
      const on = pane.id === `trace-pane-${tab}`;
      pane.hidden = !on;
    });
  }

  function renderTraceInspector(event) {
    const inspector = $('trace-inspector');
    if (!inspector || !event) return;

    const flow = resolveFlow(event);
    const sc = statusClass(event.status_code);
    const time = event.ts ? new Date(event.ts).toLocaleString() : '—';

    $('trace-inspector-method').textContent = event.method || '—';
    $('trace-inspector-path').textContent = event.path || '—';
    renderInspectorFlow(flow);

    const badges = $('trace-inspector-badges');
    badges.innerHTML = `
      <span class="trace-inspector__badge" data-kind="status" data-class="${sc}">${event.status_code ?? '—'}</span>
      ${event.latency_ms != null ? `<span class="trace-inspector__badge" data-kind="latency">${event.latency_ms} ms</span>` : ''}
      <span class="trace-inspector__badge">${escapeHtml(event.kind || '—')}</span>
    `;

    const overview = $('trace-inspector-overview');
    const overviewRows = [
      ['Event ID', event.id || '—'],
      ['Timestamp', time],
      ['Request ID', event.request_id || '—'],
      ['Direction', event.direction || '—'],
      ['Route', `${event.method || '—'} ${event.path || '—'}`],
      ['From → To', `${flow.from} → ${flow.to}`],
      ['Runner', event.runner_id || '—'],
      ['Status', event.status_code != null ? String(event.status_code) : '—'],
      ['Latency', event.latency_ms != null ? `${event.latency_ms} ms` : '—'],
      ['Kind', event.kind || '—'],
    ];
    overview.innerHTML = overviewRows.map(([label, value]) => `
      <dt>${escapeHtml(label)}</dt>
      <dd class="${label === 'Event ID' || label === 'Request ID' ? 'mono' : ''}">${escapeHtml(value)}</dd>
    `).join('');

    const requestBody = resolveBodyField(event, 'request_body');
    const responseBody = resolveBodyField(event, 'response_body');
    const requestText = formatJsonDisplay(requestBody);
    const responseText = formatJsonDisplay(responseBody);

    const reqEmpty = $('trace-inspector-request-empty');
    const reqPre = $('trace-inspector-request');
    if (requestText) {
      reqEmpty.hidden = true;
      reqPre.hidden = false;
      reqPre.textContent = requestText;
    } else {
      reqEmpty.hidden = false;
      reqPre.hidden = true;
      reqPre.textContent = '';
    }

    const resEmpty = $('trace-inspector-response-empty');
    const resPre = $('trace-inspector-response');
    if (responseText) {
      resEmpty.hidden = true;
      resPre.hidden = false;
      resPre.textContent = responseText;
    } else {
      resEmpty.hidden = false;
      resPre.hidden = true;
      resPre.textContent = '';
    }

    $('trace-inspector-raw').textContent = JSON.stringify(event, null, 2);
    setInspectorTab(state.inspectorTab);
    inspector.hidden = false;
  }

  function updateTraceRowSelection() {
    document.querySelectorAll('.trace-seq-row').forEach((row) => {
      const selected = row.dataset.id === state.selectedTraceId;
      row.classList.toggle('trace-seq-row--selected', selected);
      row.setAttribute('aria-selected', selected ? 'true' : 'false');
    });
  }

  function selectTraceEvent(eventId) {
    if (state.selectedTraceId === eventId) {
      deselectTraceEvent();
      return;
    }
    state.selectedTraceId = eventId;
    updateTraceRowSelection();
    const event = findTraceEvent(eventId);
    if (event) renderTraceInspector(event);
  }

  function deselectTraceEvent() {
    state.selectedTraceId = null;
    updateTraceRowSelection();
    const inspector = $('trace-inspector');
    if (inspector) inspector.hidden = true;
  }

  function appendTraceEvent(event, isNew) {
    state.traceEvents.unshift(event);
    if (state.traceEvents.length > TRACE_MAX_ROWS) state.traceEvents.pop();
    if (isNew) state.traceEventTotal += 1;

    state.traceSeqCounter += 1;
    const seq = state.traceSeqCounter;

    const stream = $('trace-stream');
    const empty = $('trace-empty');
    empty.hidden = true;

    if (event.runner_id) updateDiagramRunnerLabel(event.runner_id);
    updateTraceLogCount();

    const flow = resolveFlow(event);
    const span = messageSpan(flow.fromKey, flow.toKey);
    const time = event.ts
      ? new Date(event.ts).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit', second: '2-digit', hour12: false })
      : '—';
    const sc = statusClass(event.status_code);
    const eventKey = event.id || `seq-${seq}`;
    const latLabel = event.latency_ms != null ? `${event.latency_ms}ms` : '';

    const row = document.createElement('article');
    row.className = 'trace-seq-row' + (isNew ? ' trace-seq-row--new' : '');
    row.setAttribute('role', 'listitem');
    row.setAttribute('aria-selected', 'false');
    row.dataset.id = eventKey;
    row.dataset.seq = String(seq);
    row.dataset.direction = event.direction || '';
    row.dataset.from = flow.fromKey;
    row.dataset.to = flow.toKey;

    row.innerHTML = `
      <time class="trace-seq-time mono" datetime="${event.ts || ''}">${time}</time>
      <div class="trace-seq-stage">
        <div class="trace-seq-message${span.reverse ? ' trace-seq-message--rev' : ''}" data-status="${sc}" style="grid-column:${span.gridColumn}">
          <div class="trace-seq-call">
            <div class="trace-seq-call__label" title="${escapeHtml(`${event.method || ''} ${event.path || ''}`)}">
              <span class="trace-seq-call__method mono">${escapeHtml(event.method || '—')}</span>
              <span class="trace-seq-call__path mono">${escapeHtml(event.path || '—')}</span>
              ${latLabel ? `<span class="trace-seq-call__lat mono">${latLabel}</span>` : ''}
            </div>
            <div class="trace-seq-call__track" aria-hidden="true">
              <span class="trace-seq-call__anchor trace-seq-call__anchor--from"></span>
              <span class="trace-seq-call__line"></span>
              <span class="trace-seq-call__anchor trace-seq-call__anchor--to"></span>
            </div>
          </div>
        </div>
      </div>
      <div class="trace-seq-meta">
        <span class="trace-status-code" data-class="${sc}">${event.status_code ?? '—'}</span>
      </div>
    `;

    row.addEventListener('click', () => selectTraceEvent(eventKey));
    row.addEventListener('mouseenter', () => highlightTraceLink(eventKey, true));
    row.addEventListener('mouseleave', () => highlightTraceLink(eventKey, false));

    stream.insertBefore(row, stream.firstChild === empty ? empty.nextSibling : stream.firstChild);

    while (stream.querySelectorAll('.trace-seq-row').length > TRACE_MAX_ROWS) {
      const removed = stream.querySelector('.trace-seq-row:last-of-type');
      if (removed?.dataset.id === state.selectedTraceId) deselectTraceEvent();
      removed?.remove();
    }

    if (isNew) flashSequenceEntities(flow.fromKey, flow.toKey);

    if (!state.tracePaused && isNew) {
      stream.scrollTop = 0;
    }
  }

  function clearTraceView() {
    state.traceEvents = [];
    state.traceEventTotal = 0;
    state.traceSeqCounter = 0;
    state.tracePausedBuffer = [];
    deselectTraceEvent();
    $('trace-stream').querySelectorAll('.trace-seq-row').forEach((el) => el.remove());
    $('trace-empty').hidden = false;
    $('trace-empty').textContent = state.token
      ? 'View cleared. New events will appear here.'
      : 'Sign in to watch live gateway traffic.';
    updateTraceLogCount();
    const gwCount = $('gateway-event-count');
    if (gwCount) gwCount.textContent = '0 evt';
  }

  function updateTraceLogCount() {
    const el = $('trace-log-count');
    if (!el) return;
    const n = state.traceEvents.length;
    el.textContent = `${n} event${n === 1 ? '' : 's'}`;
    const gwCount = $('gateway-event-count');
    if (gwCount) gwCount.textContent = `${state.traceEventTotal} evt`;
  }

  function highlightTraceLink(eventKey, on) {
    if (!eventKey) return;
    document.querySelectorAll(`.trace-seq-row[data-id="${eventKey}"]`).forEach((row) => {
      row.classList.toggle('trace-seq-row--linked', on);
    });
  }

  function flashSequenceEntities(fromKey, toKey) {
    if (window.matchMedia('(prefers-reduced-motion: reduce)').matches) return;
    [fromKey, toKey].forEach((key) => {
      const cap = document.querySelector(`#entity-${key} .trace-entity-cap`);
      if (!cap) return;
      cap.classList.add('trace-entity-cap--active');
      window.setTimeout(() => cap.classList.remove('trace-entity-cap--active'), 450);
    });
  }

  function updateDiagramRunnerLabel(runnerId) {
    const label = $('runner-node-id');
    if (!label) return;
    const id = runnerId
      || state.traceFilters.runner_id
      || (state.traceConfig?.runner_ids || [])[0]
      || (state.status?.runners || [])[0]?.id;
    label.textContent = id || '—';
  }

  /* ── Trace filters ─────────────────────────────────────── */

  function countActiveFilters() {
    const f = state.traceFilters;
    let n = 0;
    if (f.direction) n += 1;
    if (f.kind) n += 1;
    if (f.runner_id) n += 1;
    if (f.status_class) n += 1;
    if (f.path_prefix) n += 1;
    return n;
  }

  function updateFilterBadge() {
    const badge = $('trace-filter-badge');
    if (!badge) return;
    const n = countActiveFilters();
    badge.hidden = n === 0;
    badge.textContent = String(n);
  }

  function syncFilterFormFromState() {
    $('filter-direction').value = state.traceFilters.direction || '';
    $('filter-kind').value = state.traceFilters.kind || '';
    $('filter-runner').value = state.traceFilters.runner_id || '';
    $('filter-status').value = state.traceFilters.status_class || '';
    $('filter-path-prefix').value = state.traceFilters.path_prefix || '';
  }

  function applyFiltersFromForm() {
    state.traceFilters.direction = $('filter-direction').value || null;
    state.traceFilters.kind = $('filter-kind').value || null;
    state.traceFilters.runner_id = $('filter-runner').value || null;
    state.traceFilters.status_class = $('filter-status').value || null;
    state.traceFilters.path_prefix = $('filter-path-prefix').value.trim();
    updateFilterBadge();
    updateDiagramRunnerLabel();
    reconnectTrace();
  }

  function clearAllFilters() {
    state.traceFilters = {
      direction: null,
      kind: null,
      runner_id: null,
      status_class: null,
      path_prefix: '',
    };
    syncFilterFormFromState();
    updateFilterBadge();
    updateDiagramRunnerLabel();
    reconnectTrace();
  }

  function openFilterPanel() {
    state.traceFilterPanelOpen = true;
    const panel = $('trace-filter-panel');
    const btn = $('trace-filter-btn');
    panel.hidden = false;
    btn.setAttribute('aria-expanded', 'true');
    syncFilterFormFromState();
    $('filter-direction').focus();
  }

  function closeFilterPanel() {
    state.traceFilterPanelOpen = false;
    const panel = $('trace-filter-panel');
    const btn = $('trace-filter-btn');
    panel.hidden = true;
    btn.setAttribute('aria-expanded', 'false');
    btn.focus();
  }

  function toggleFilterPanel() {
    if (state.traceFilterPanelOpen) closeFilterPanel();
    else openFilterPanel();
  }

  function renderTraceFilters() {
    const cfg = state.traceConfig;
    if (!cfg) return;

    populateFilterSelect('filter-direction', cfg.directions, 'All directions');
    populateFilterSelect('filter-kind', cfg.kinds, 'All kinds');
    populateFilterSelect('filter-runner', cfg.runner_ids || [], 'All runners');
    populateFilterSelect('filter-status', cfg.status_classes, 'All statuses');
    syncFilterFormFromState();
    updateFilterBadge();
    updateDiagramRunnerLabel();
  }

  function populateFilterSelect(selectId, values, allLabel) {
    const select = $(selectId);
    const current = state.traceFilters[selectKeyForId(selectId)] || '';
    select.innerHTML = `<option value="">${escapeHtml(allLabel)}</option>`;
    for (const val of values) {
      if (!val) continue;
      const opt = document.createElement('option');
      opt.value = val;
      opt.textContent = val;
      select.appendChild(opt);
    }
    select.value = current;
  }

  function selectKeyForId(id) {
    const map = {
      'filter-direction': 'direction',
      'filter-kind': 'kind',
      'filter-runner': 'runner_id',
      'filter-status': 'status_class',
    };
    return map[id];
  }

  function reconnectTrace() {
    if (state.traceStreamConnected && state.token) connectTrace();
  }

  /* ── Render panels ────────────────────────────────────── */

  function updateRegistryMode() {
    const cfg = state.status?.config_safe;
    const el = $('registry-mode');
    if (!cfg) {
      el.textContent = 'Pull-mode health poller';
      return;
    }
    el.textContent = cfg.enable_push_registration
      ? 'Push registration enabled (pull poller also active)'
      : 'Pull-mode health poller';
  }

  function renderRunners() {
    const runners = state.status?.runners || [];
    const rail = $('lifecycle-rail');
    const list = $('runner-list');

    const counts = {};
    LIFECYCLE.forEach((s) => { counts[s] = 0; });
    runners.forEach((r) => { if (counts[r.status] != null) counts[r.status]++; });

    rail.innerHTML = LIFECYCLE.map((s) =>
      `<span class="lifecycle-pill" data-active="${counts[s] > 0}">${s} (${counts[s]})</span>`
    ).join('');

    if (!runners.length) {
      list.innerHTML = '<p class="panel-placeholder">Send GET /v1/status from Client requests to load the runner registry.</p>';
      return;
    }

    list.innerHTML = runners.map((r) => {
      const model = r.loaded_model?.name || '—';
      const caps = (r.declared_capabilities || []).join(', ') || '—';
      const poll = state.status?.config_safe?.health_poll_interval_s;
      return `
        <article class="runner-card" role="listitem">
          <header class="runner-card__header">
            <h3 class="runner-card__id">${escapeHtml(r.id)}</h3>
            <span class="runner-card__status" data-status="${r.status}">${r.status}</span>
          </header>
          <dl class="runner-card__grid">
            <div><dt>Base URL</dt><dd class="mono">${escapeHtml(r.base_url)}</dd></div>
            <div><dt>Last seen</dt><dd>${r.last_seen_at ? new Date(r.last_seen_at).toLocaleString() : '—'}</dd></div>
            <div><dt>Last poll latency</dt><dd class="mono">${r.last_latency_ms != null ? `${r.last_latency_ms}ms` : '—'}</dd></div>
            <div><dt>Loaded model</dt><dd class="mono">${escapeHtml(model)}</dd></div>
            <div><dt>Capabilities</dt><dd>${escapeHtml(caps)}</dd></div>
            <div><dt>In-flight</dt><dd>${r.in_flight ?? 0}</dd></div>
            <div><dt>Failures</dt><dd>${r.consecutive_failures ?? 0}</dd></div>
            <div><dt>Poll interval</dt><dd>${poll != null ? `${poll}s` : '—'}</dd></div>
          </dl>
        </article>
      `;
    }).join('');
  }

  function renderCapabilities() {
    const el = $('capabilities-body');
    const cap = state.capabilities;
    if (!cap) {
      el.innerHTML = '<p class="panel-placeholder">Send GET /v1/capabilities from Client requests (or enable auto-refresh).</p>';
      return;
    }
    if (!cap.ok) {
      el.innerHTML = '<p class="panel-placeholder">Could not load capabilities. Check JWT and gateway logs.</p>';
      return;
    }
    const body = cap.body;
    $('capabilities-meta').textContent = `schema ${body.schema_version || '—'} · streaming ${body.streaming ? 'on' : 'off'}`;
    const runners = body.runners || [];
    const tasks = (body.tasks || []).join(', ') || '—';
    const commands = (body.commands || []).join(', ') || '—';

    el.innerHTML = `
      <p class="panel__desc">Tasks: ${escapeHtml(tasks)} · Commands: ${escapeHtml(commands)}</p>
      ${runners.map((r) => `
        <div class="cap-runner">
          <p class="cap-runner__name">${escapeHtml(r.id)} <span class="mono">(${r.status})</span></p>
          <p class="mono">${escapeHtml(r.model || 'no model')} · ctx ${r.context_tokens ?? '—'}</p>
        </div>
      `).join('') || '<p class="panel-placeholder">No runners in capabilities report.</p>'}
    `;
  }

  function renderMetrics() {
    const grid = $('metrics-grid');
    const p = state.metricsParsed;
    if (!p) {
      grid.innerHTML = '<p class="panel-placeholder">Metrics unavailable. Check GET /metrics.</p>';
      return;
    }

    const requests = sumByName(p, 'gateway_requests_total');
    const errors = sumByName(p, 'gateway_errors_total');
    const health = gaugesByLabel(p, 'gateway_runner_health', 'runner_id');
    const inflight = gaugesByLabel(p, 'gateway_inflight_requests', 'runner_id');
    const aiQueue = gaugesByLabel(p, 'ai_queue_depth', 'capability');
    const aiInflight = gaugesByLabel(p, 'ai_inflight', 'capability');
    const modelSwaps = sumByName(p, 'ai_model_swaps_total');

    const cards = [
      { label: 'Total requests', value: requests, sub: 'gateway_requests_total' },
      { label: 'Total errors', value: errors, sub: 'gateway_errors_total' },
      { label: 'Healthy runners', value: Object.values(health).filter((v) => v === 1).length, sub: `of ${Object.keys(health).length}` },
      { label: 'In-flight total', value: Object.values(inflight).reduce((a, b) => a + b, 0), sub: 'across runners' },
      { label: 'AI queue depth', value: Object.values(aiQueue).reduce((a, b) => a + b, 0), sub: 'per capability class' },
      { label: 'AI in-flight', value: Object.values(aiInflight).reduce((a, b) => a + b, 0), sub: 'generation pipeline' },
      { label: 'Model swaps', value: modelSwaps, sub: 'auto-triggered' },
    ];

    grid.innerHTML = cards.map((c) => `
      <article class="metric-card">
        <p class="metric-card__label">${c.label}</p>
        <p class="metric-card__value">${c.value}</p>
        <p class="metric-card__sub">${c.sub}</p>
      </article>
    `).join('');
  }

  function renderSecurity() {
    const dl = $('config-dl');
    const cfg = state.status?.config_safe;
    if (!cfg) {
      dl.innerHTML = '<p class="panel-placeholder">Send GET /v1/status from Client requests to load the security snapshot.</p>';
      return;
    }
    const rows = [
      ['Port', cfg.port],
      ['Health poll interval', `${cfg.health_poll_interval_s}s`],
      ['Unreachable after failures', cfg.unreachable_after_failures],
      ['Allowed origins', (cfg.allowed_origins || []).join(', ')],
      ['Log directory', cfg.log_dir],
      ['Streaming', cfg.streaming_enabled ? 'enabled' : 'disabled'],
      ['Push registration', cfg.enable_push_registration ? 'enabled' : 'disabled'],
      ['PHI redaction', cfg.log_verbatim ? 'off (verbatim)' : 'on'],
      ['Multi-command plans', cfg.enable_multi_command_plans ? 'enabled' : 'disabled'],
    ];
    dl.innerHTML = rows.map(([k, v]) => `<div><dt>${k}</dt><dd class="mono">${escapeHtml(String(v))}</dd></div>`).join('');
  }

  function renderEndpointCatalog() {
    const list = $('endpoint-catalog');
    const endpoints = state.status?.endpoints || [];
    list.innerHTML = endpoints.map((ep) => {
      const locked = isProtected(ep.path);
      return `
        <button type="button" class="catalog-item${locked ? ' catalog-item--locked' : ''}"
          data-method="${ep.method}" data-path="${escapeHtml(ep.path)}">
          <span class="catalog-item__method">${ep.method}</span>
          <span class="mono">${escapeHtml(ep.path)}</span>
        </button>
      `;
    }).join('');

    list.querySelectorAll('.catalog-item').forEach((btn) => {
      btn.addEventListener('click', () => {
        $('workbench-method').value = btn.dataset.method;
        $('workbench-path').value = btn.dataset.path;
      });
    });
  }

  function renderModelsActions() {
    const wrap = $('models-actions');
    const runners = state.status?.runners || [];
    if (!runners.length) {
      wrap.innerHTML = '<p class="panel-placeholder">No runners configured.</p>';
      return;
    }
    wrap.innerHTML = runners.map((r) =>
      `<button type="button" class="btn btn--ghost" data-runner="${escapeHtml(r.id)}">Poll ${escapeHtml(r.id)} models</button>`
    ).join('');
    wrap.querySelectorAll('[data-runner]').forEach((btn) => {
      btn.addEventListener('click', () => pollRunnerModels(btn.dataset.runner));
    });
  }

  async function pollRunnerModels(runnerId) {
    const panel = $('models-response');
    panel.hidden = false;
    try {
      const { res, body, requestId } = await apiFetch(`/v1/runners/${runnerId}/models`);
      $('models-response-status').textContent = `${res.status} ${res.statusText}`;
      $('models-response-status').dataset.class = res.ok ? 'ok' : 'error';
      $('models-response-body').textContent = JSON.stringify(body, null, 2);
      if (requestId) $('models-response-body').dataset.rid = requestId;
    } catch (e) {
      $('models-response-status').textContent = 'Request failed';
      $('models-response-status').dataset.class = 'error';
      $('models-response-body').textContent = String(e);
    }
  }

  /* ── Client requests ─────────────────────────────────── */

  function defaultRunnerId() {
    const runners = state.status?.runners || [];
    return runners[0]?.id || 'ollama-local';
  }

  function renderClientRequests() {
    const list = $('client-request-list');
    list.innerHTML = CLIENT_REQUESTS.map((req) => {
      const needsAuth = req.auth;
      const authBlocked = needsAuth && (!state.token || !state.hasAiAccess);
      const runnerField = req.runnerId
        ? `<label class="client-request__extra">
            Runner id
            <input type="text" class="client-request__runner-id mono" id="client-runner-id-${req.id}"
              value="${escapeHtml(defaultRunnerId())}" spellcheck="false" autocomplete="off">
          </label>`
        : '';
      const bodyField = req.defaultBody != null
        ? `<label class="client-request__extra">
            Body
            <textarea class="client-request__body mono" id="client-body-${req.id}" rows="2"
              spellcheck="false">${escapeHtml(req.defaultBody)}</textarea>
          </label>`
        : '';
      return `
        <article class="client-request" role="listitem" data-client-id="${req.id}">
          <div class="client-request__lead">
            <span class="client-request__method" data-method="${req.method}">${req.method}</span>
            <span class="client-request__path mono">${escapeHtml(req.path)}</span>
            <span class="client-request__auth" data-auth="${needsAuth}">${needsAuth ? 'JWT' : 'open'}</span>
          </div>
          <div class="client-request__meta">
            <p class="client-request__desc">${escapeHtml(req.desc)}</p>
            ${runnerField}${bodyField}
          </div>
          <div class="client-request__actions">
            <button type="button" class="btn btn--primary client-send-btn" data-client-id="${req.id}"
              ${authBlocked ? 'disabled title="Sign in with ai.access first"' : ''}>Send</button>
          </div>
        </article>
      `;
    }).join('');

    list.querySelectorAll('.client-send-btn').forEach((btn) => {
      btn.addEventListener('click', () => sendClientRequest(btn.dataset.clientId));
    });
  }

  function resolveClientPath(req) {
    if (!req.runnerId) return req.path;
    const input = $(`client-runner-id-${req.id}`);
    const runnerId = (input?.value || defaultRunnerId()).trim();
    return req.path.replace('{runner_id}', encodeURIComponent(runnerId));
  }

  function applyClientResponse(req, res, body) {
    if (req.id === 'health') {
      state.health.ok = res.ok;
      const el = $('vital-health');
      const val = $('vital-health-value');
      el.dataset.state = state.health.ok ? 'ok' : 'error';
      val.textContent = state.health.ok ? 'Up' : 'Down';
      return;
    }
    if (req.id === 'ready') {
      state.ready = { ok: res.ok, status: res.status, body };
      const el = $('vital-ready');
      const val = $('vital-ready-value');
      el.dataset.state = state.ready.ok ? 'ok' : 'error';
      val.textContent = state.ready.ok ? 'Ready' : `Not ready (${state.ready.status})`;
      return;
    }
    if (req.id === 'status' && res.ok) {
      state.status = body;
      if (body?.gateway?.uptime_s != null) {
        $('vital-uptime-value').textContent = formatUptime(body.gateway.uptime_s);
      }
      renderRunners();
      renderSecurity();
      renderEndpointCatalog();
      renderModelsActions();
      updateRegistryMode();
      updateDiagramRunnerLabel();
      renderClientRequests();
      return;
    }
    if (req.id === 'capabilities') {
      state.capabilities = res.ok ? { ok: true, body } : { ok: false };
      renderCapabilities();
      return;
    }
    if (req.id === 'metrics' && res.ok && typeof body === 'string') {
      state.metricsRaw = body;
      state.metricsParsed = parsePrometheus(body);
      renderMetrics();
    }
  }

  async function sendClientRequest(requestId) {
    const req = CLIENT_REQUESTS.find((r) => r.id === requestId);
    if (!req) return;

    if (req.auth && (!state.token || !state.hasAiAccess)) {
      window.alert('Sign in with a staff JWT that has ai.access before calling this route.');
      return;
    }

    if (state.token && state.hasAiAccess && !state.traceStreamConnected) {
      connectTrace();
    }

    const path = resolveClientPath(req);
    const panel = $('client-response');
    panel.hidden = false;

    const opts = { method: req.method, headers: {} };
    if (req.defaultBody != null && req.method !== 'GET' && req.method !== 'HEAD') {
      const bodyEl = $(`client-body-${req.id}`);
      const bodyText = (bodyEl?.value || req.defaultBody).trim();
      if (bodyText) {
        opts.headers['Content-Type'] = 'application/json';
        opts.body = bodyText;
      }
    }

    $('client-response-status').textContent = 'Sending…';
    $('client-response-status').dataset.class = '';
    $('client-response-path').textContent = `${req.method} ${path}`;
    $('client-response-rid').textContent = '';
    $('client-response-body').textContent = '';

    try {
      const { res, body, requestId: rid } = await apiFetch(path, opts);
      $('client-response-status').textContent = `${res.status} ${res.statusText}`;
      $('client-response-status').dataset.class = res.ok ? 'ok' : 'error';
      $('client-response-rid').textContent = rid ? `req ${rid}` : '';
      $('client-response-body').textContent = typeof body === 'string'
        ? body
        : JSON.stringify(body, null, 2);
      applyClientResponse(req, res, body);
      $('last-refresh').textContent = `Client ${req.method} ${path} · ${new Date().toLocaleTimeString()}`;
    } catch (e) {
      $('client-response-status').textContent = 'Request failed';
      $('client-response-status').dataset.class = 'error';
      $('client-response-body').textContent = `Network error. Check the gateway is running.\n\n${e}`;
    }
  }

  function toggleTraceStream() {
    if (state.traceStreamConnected) {
      disconnectTrace();
      $('trace-empty').hidden = state.traceEvents.length > 0;
      return;
    }
    if (!state.token || !state.hasAiAccess) {
      window.alert('Sign in with ai.access before connecting the live trace stream.');
      return;
    }
    connectTrace();
  }

  /* ── Probe execution (feature matrix) ────────────────── */


  function classifySseLine(line) {
    const trimmed = line.trim();
    if (trimmed.startsWith('event: final')) return 'final';
    if (trimmed.startsWith('event: summary')) return 'summary';
    if (trimmed.startsWith('event: error')) return 'error';
    if (trimmed.startsWith('event:')) return 'event';
    return '';
  }

  function formatSseHtml(rawText) {
    return (rawText || '').split('\n').map((line) => {
      const kind = classifySseLine(line);
      const cls = kind ? ` phase-probe-sse__line--${kind}` : '';
      return `<span class="phase-probe-sse__line${cls}">${escapeHtml(line)}</span>`;
    }).join('');
  }

  function concurrentRowHighlight(status, errorCode) {
    if (status === 429 || errorCode === 'rate_limited') return 'rate_limited';
    if (status === 503 && errorCode === 'ai_busy') return 'ai_busy';
    if (status >= 200 && status < 300) return 'ok';
    return '';
  }

  function formatConcurrentTableHtml(results) {
    const rows = results.map((row) => {
      const highlight = concurrentRowHighlight(row.status, row.errorCode);
      const notes = [];
      if (row.retryAfter) notes.push(`Retry-After: ${row.retryAfter}s`);
      if (row.networkError) notes.push(row.networkError);
      return `
        <tr data-highlight="${highlight}">
          <td class="mono">${row.index}</td>
          <td class="mono">${row.status ?? '—'}</td>
          <td class="mono">${escapeHtml(row.errorCode || '—')}</td>
          <td>${escapeHtml(notes.join(' · ') || '—')}</td>
        </tr>
      `;
    }).join('');
    return `
      <table class="phase-probe-table">
        <thead>
          <tr>
            <th scope="col">Req #</th>
            <th scope="col">HTTP</th>
            <th scope="col">error.code</th>
            <th scope="col">Notes</th>
          </tr>
        </thead>
        <tbody>${rows}</tbody>
      </table>
    `;
  }

  async function parseGenerateErrorCode(res) {
    const ct = res.headers.get('content-type') || '';
    if (!ct.includes('application/json')) return null;
    try {
      const body = await res.clone().json();
      return body?.error?.code || null;
    } catch {
      return null;
    }
  }

  async function fetchGenerateOnce(path, body, signal) {
    const headers = { 'Content-Type': 'application/json' };
    if (state.token) headers.Authorization = `Bearer ${state.token}`;
    const res = await fetch(path, {
      method: 'POST',
      headers,
      body: JSON.stringify(body),
      signal,
    });
    const errorCode = await parseGenerateErrorCode(res);
    return {
      status: res.status,
      errorCode,
      retryAfter: res.headers.get('Retry-After'),
      requestId: res.headers.get('X-Request-ID'),
    };
  }

  async function readSseResponseBody(res, onPartial) {
    if (!res.body) return '';
    const reader = res.body.getReader();
    const decoder = new TextDecoder();
    let raw = '';
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      raw += decoder.decode(value, { stream: true });
      if (onPartial) onPartial(raw);
    }
    return raw;
  }

  function evaluateBurstExpect(expect, results) {
    if (!expect) return { pass: null, results: [] };
    const out = [];
    let pass = true;

    if (expect.status != null || expect.error_code != null) {
      const statusMatch = expect.status == null || results.some((r) => r.status === expect.status);
      const codeMatch = expect.error_code == null || results.some((r) => r.errorCode === expect.error_code);
      const ok = statusMatch && codeMatch;
      const labelParts = [];
      if (expect.status != null) labelParts.push(`HTTP ${expect.status}`);
      if (expect.error_code != null) labelParts.push(`error.code ${expect.error_code}`);
      out.push({
        label: `At least one request: ${labelParts.join(' + ')}`,
        ok,
        actual: results.map((r) => `#${r.index}→${r.status ?? '?'}/${r.errorCode || '—'}`).join(', '),
      });
      if (!ok) pass = false;
    }

    return { pass, results: out };
  }

  function evaluateSseExpect(expect, res, raw, contentType) {
    const results = [];
    let pass = true;

    if (expect?.status != null) {
      const ok = res.status === expect.status;
      results.push({ label: `HTTP ${expect.status}`, ok, actual: String(res.status) });
      if (!ok) pass = false;
    }

    const isSse = contentType.includes('text/event-stream');
    results.push({
      label: 'Content-Type is text/event-stream',
      ok: isSse,
      actual: contentType || '—',
    });
    if (!isSse) pass = false;

    const hasFinal = /event:\s*final/m.test(raw);
    results.push({
      label: 'event:final present',
      ok: hasFinal,
      actual: hasFinal ? 'yes' : 'no',
    });
    if (!hasFinal) pass = false;

    const hasToken = /event:\s*token/m.test(raw);
    results.push({
      label: 'no event:token lines',
      ok: !hasToken,
      actual: hasToken ? 'found token events' : 'none',
    });
    if (hasToken) pass = false;

    return { pass, results };
  }

  function probeSpecialBadge(probe) {
    if (probe.special === 'manual') {
      return '<span class="pv-chip pv-chip--manual" data-special="manual">Manual</span>';
    }
    if (probe.special === 'concurrent_burst') {
      return `<span class="pv-chip pv-chip--burst" data-special="concurrent_burst">×${probe.concurrent_count || 3} burst</span>`;
    }
    if (probe.special === 'sse_stream') {
      return '<span class="pv-chip pv-chip--sse" data-special="sse_stream">SSE</span>';
    }
    if (probe.special === 'abort_mid_stream') {
      return '<span class="pv-chip pv-chip--abort" data-special="abort_mid_stream">abort @1s</span>';
    }
    if (probe.special === 'metrics_queue_depth') {
      return '<span class="pv-chip pv-chip--metrics" data-special="metrics_queue_depth">queue depth</span>';
    }
    if (probe.special === 'info_only') {
      return '<span class="pv-chip pv-chip--info" data-special="info_only">Info</span>';
    }
    return '';
  }

  const PV_SPLIT_RATIO_KEY = 'pv_split_ratio';
  const PV_SPLIT_DEFAULT = 50;
  const PV_SPLIT_MIN = 20;
  const PV_SPLIT_MAX = 80;

  function getPvSplitRatio() {
    const raw = parseFloat(localStorage.getItem(PV_SPLIT_RATIO_KEY));
    if (!Number.isFinite(raw)) return PV_SPLIT_DEFAULT;
    return Math.min(PV_SPLIT_MAX, Math.max(PV_SPLIT_MIN, raw));
  }

  function setPvSplitRatio(ratio) {
    localStorage.setItem(PV_SPLIT_RATIO_KEY, String(Math.round(ratio * 10) / 10));
  }

  function applyPvSplitRatio(splitEl, ratio) {
    const clamped = Math.min(PV_SPLIT_MAX, Math.max(PV_SPLIT_MIN, ratio));
    splitEl.style.setProperty('--pv-split-ratio', `${clamped}%`);
    const gutter = splitEl.querySelector('.pv-split__gutter');
    if (gutter) gutter.setAttribute('aria-valuenow', String(Math.round(clamped)));
    return clamped;
  }

  function pvSplitIsVertical() {
    return window.matchMedia('(min-width: 768px)').matches;
  }

  function initPvSplitters(root = document) {
    root.querySelectorAll('[data-pv-split]:not([data-pv-split-bound])').forEach((splitEl) => {
      splitEl.dataset.pvSplitBound = '1';
      const gutter = splitEl.querySelector('.pv-split__gutter');
      if (!gutter) return;

      applyPvSplitRatio(splitEl, getPvSplitRatio());

      const syncOrientation = () => {
        gutter.setAttribute('aria-orientation', pvSplitIsVertical() ? 'vertical' : 'horizontal');
      };
      syncOrientation();
      window.matchMedia('(min-width: 768px)').addEventListener('change', syncOrientation);

      const readRatio = () => {
        const raw = parseFloat(getComputedStyle(splitEl).getPropertyValue('--pv-split-ratio'));
        return Number.isFinite(raw) ? raw : getPvSplitRatio();
      };

      const nudgeRatio = (delta) => {
        const next = applyPvSplitRatio(splitEl, readRatio() + delta);
        setPvSplitRatio(next);
      };

      gutter.addEventListener('keydown', (e) => {
        const vertical = pvSplitIsVertical();
        const step = e.shiftKey ? 10 : 5;
        let handled = false;
        if (vertical && e.key === 'ArrowLeft') { nudgeRatio(-step); handled = true; }
        else if (vertical && e.key === 'ArrowRight') { nudgeRatio(step); handled = true; }
        else if (!vertical && e.key === 'ArrowUp') { nudgeRatio(-step); handled = true; }
        else if (!vertical && e.key === 'ArrowDown') { nudgeRatio(step); handled = true; }
        else if (e.key === 'Home') { setPvSplitRatio(applyPvSplitRatio(splitEl, PV_SPLIT_MIN)); handled = true; }
        else if (e.key === 'End') { setPvSplitRatio(applyPvSplitRatio(splitEl, PV_SPLIT_MAX)); handled = true; }
        if (handled) e.preventDefault();
      });

      const startDrag = (clientX, clientY) => {
        const rect = splitEl.getBoundingClientRect();
        const vertical = pvSplitIsVertical();
        const startRatio = readRatio();
        const startX = clientX;
        const startY = clientY;
        splitEl.dataset.pvDragging = '1';
        document.body.classList.add('pv-split-dragging', vertical ? 'pv-split-dragging--col' : 'pv-split-dragging--row');

        const onMove = (ev) => {
          ev.preventDefault();
          const delta = vertical
            ? ((ev.clientX - startX) / rect.width) * 100
            : ((ev.clientY - startY) / rect.height) * 100;
          applyPvSplitRatio(splitEl, startRatio + delta);
        };

        const onUp = () => {
          splitEl.removeAttribute('data-pv-dragging');
          document.body.classList.remove('pv-split-dragging', 'pv-split-dragging--col', 'pv-split-dragging--row');
          setPvSplitRatio(readRatio());
          document.removeEventListener('mousemove', onMove);
          document.removeEventListener('mouseup', onUp);
          document.removeEventListener('touchmove', onTouchMove);
          document.removeEventListener('touchend', onUp);
          document.removeEventListener('touchcancel', onUp);
        };

        const onTouchMove = (ev) => {
          if (!ev.touches[0]) return;
          onMove({ clientX: ev.touches[0].clientX, clientY: ev.touches[0].clientY, preventDefault: () => ev.preventDefault() });
        };

        document.addEventListener('mousemove', onMove);
        document.addEventListener('mouseup', onUp);
        document.addEventListener('touchmove', onTouchMove, { passive: false });
        document.addEventListener('touchend', onUp);
        document.addEventListener('touchcancel', onUp);
      };

      gutter.addEventListener('mousedown', (e) => {
        if (e.button !== 0) return;
        e.preventDefault();
        startDrag(e.clientX, e.clientY);
      });

      gutter.addEventListener('touchstart', (e) => {
        if (!e.touches[0]) return;
        e.preventDefault();
        startDrag(e.touches[0].clientX, e.touches[0].clientY);
      }, { passive: false });
    });
  }

  function renderProbeTranscriptSplit(probeKey, result) {
    const hasSse = result.renderType === 'sse' && result.sseHtml;
    const hasBurst = result.renderType === 'table' && result.tableHtml;
    const statusClass = statusClassFromCode(result.responseStatus);

    const requestLine = `${result.requestMethod || 'GET'} ${result.requestPath || '—'}`;
    const requestPane = `
      <div class="pv-split__pane pv-split__pane--request" data-pane="request">
        <div class="pv-split__pane-inner">
          <div class="pv-transcript__line pv-transcript__line--out">
            <span class="pv-transcript__arrow" aria-hidden="true">↑</span>
            <span class="pv-transcript__dir">Request</span>
          </div>
          <p class="pv-transcript__route mono">${escapeHtml(requestLine)}</p>
          ${result.requestNote ? `<p class="pv-transcript__note">${escapeHtml(result.requestNote)}</p>` : ''}
          <div class="pv-transcript__section">
            <h4 class="pv-transcript__section-title">Headers</h4>
            ${formatProbeHeadersHtml(result.requestHeaders)}
          </div>
          <div class="pv-transcript__section">
            <h4 class="pv-transcript__section-title">Body</h4>
            ${formatProbeJsonHtml(result.requestBody)}
          </div>
        </div>
      </div>`;

    let responseBodyHtml;
    if (hasSse) {
      responseBodyHtml = '<p class="pv-transcript__empty">Event stream captured below</p>';
    } else if (hasBurst) {
      responseBodyHtml = `<pre class="pv-transcript__code mono" tabindex="0">${escapeHtml(result.bodyText || '')}</pre>`;
    } else {
      responseBodyHtml = formatProbeJsonHtml(
        result.responseBody != null ? result.responseBody : result.bodyText,
      );
    }

    const responsePane = `
      <div class="pv-split__pane pv-split__pane--response" data-pane="response">
        <div class="pv-split__pane-inner">
          <div class="pv-transcript__line pv-transcript__line--in">
            <span class="pv-transcript__arrow" aria-hidden="true">↓</span>
            <span class="pv-transcript__dir">Response</span>
          </div>
          <p class="pv-transcript__status">
            <span class="pv-transcript__status-code" data-class="${statusClass}">
              ${result.responseStatus != null ? escapeHtml(String(result.responseStatus)) : '—'}
            </span>
            <span class="pv-transcript__status-text">${escapeHtml(result.statusLine || '')}</span>
          </p>
          <div class="pv-transcript__section">
            <h4 class="pv-transcript__section-title">Headers</h4>
            ${formatProbeHeadersHtml(result.responseHeaders)}
          </div>
          <div class="pv-transcript__section">
            <h4 class="pv-transcript__section-title">Body</h4>
            ${responseBodyHtml}
          </div>
        </div>
      </div>`;

    const sseSection = hasSse ? `
      <section class="pv-extra pv-extra--sse" aria-label="SSE stream">
        <h4 class="pv-extra__title">SSE stream</h4>
        <div class="phase-probe-sse mono" tabindex="0">${result.sseHtml}</div>
      </section>` : '';

    const burstSection = hasBurst ? `
      <section class="pv-extra pv-extra--burst" aria-label="Burst results">
        <h4 class="pv-extra__title">Burst table</h4>
        <div class="phase-probe-table-wrap">${result.tableHtml}</div>
      </section>` : '';

    return `
      <div class="pv-transcript" data-probe-transcript="${escapeHtml(probeKey)}">
        <div class="pv-split" data-pv-split>
          ${requestPane}
          <div class="pv-split__gutter"
            role="separator"
            aria-orientation="vertical"
            aria-valuemin="${PV_SPLIT_MIN}"
            aria-valuemax="${PV_SPLIT_MAX}"
            aria-valuenow="${PV_SPLIT_DEFAULT}"
            aria-label="Resize request and response panes"
            tabindex="0">
            <span class="pv-split__handle" aria-hidden="true"></span>
          </div>
          ${responsePane}
        </div>
        ${sseSection}
        ${burstSection}
      </div>`;
  }


  function parseProbeBody(probe, probeDomKey, probeKey) {
    if (probe.body == null || probe.method === 'GET' || probe.method === 'HEAD') return null;
    const bodyEl = $(`probe-body-${probeDomKey}`);
    let bodyObj = probe.body;
    if (bodyEl) {
      try {
        bodyObj = JSON.parse(bodyEl.value.trim());
      } catch {
        state.probeResults[probeKey] = {
          ...buildProbeRequestMeta(probe, null, { 'Content-Type': 'application/json' }),
          statusLine: 'Invalid JSON body',
          pass: false,
          expect: [],
          bodyText: 'Fix the request body JSON before sending.',
          responseStatus: null,
          responseHeaders: {},
          responseBody: null,
          requestId: null,
        };
        return null;
      }
    }
    return bodyObj;
  }

  async function executeSseStreamProbe(probeKey, probe, bodyObj) {
    if (state.probeAbort) state.probeAbort.abort();
    const controller = new AbortController();
    state.probeAbort = controller;
    const requestMeta = buildProbeRequestMeta(probe, bodyObj, { 'Content-Type': 'application/json' });

    try {
      const headers = buildProbeRequestHeaders(probe, { 'Content-Type': 'application/json' });
      const res = await fetch(probe.path, {
        method: 'POST',
        headers,
        body: JSON.stringify(bodyObj),
        signal: controller.signal,
      });
      const requestId = res.headers.get('X-Request-ID');
      const contentType = res.headers.get('content-type') || '';
      const responseHeaders = pickResponseHeaders(res);

      if (contentType.includes('text/event-stream') && res.body) {
        const raw = await readSseResponseBody(res);
        const evaluation = evaluateSseExpect(probe.expect, res, raw, contentType);
        state.probeResults[probeKey] = {
          ...requestMeta,
          statusLine: `${res.status} SSE stream`,
          pass: evaluation.pass,
          expect: evaluation.results,
          renderType: 'sse',
          sseHtml: formatSseHtml(raw),
          bodyText: raw,
          responseStatus: res.status,
          responseHeaders,
          responseBody: raw,
          requestId,
        };
        return;
      }

      const bodyText = await res.text();
      let pretty = bodyText;
      let parsedBody = {};
      try {
        parsedBody = JSON.parse(bodyText || '{}');
        pretty = JSON.stringify(parsedBody, null, 2);
      } catch { /* keep raw text */ }
      const evaluation = evaluateExpect(probe.expect, res, parsedBody);
      state.probeResults[probeKey] = {
        ...requestMeta,
        statusLine: `${res.status} silent fallback (JSON, not SSE)`,
        pass: evaluation.pass,
        expect: [
          ...(evaluation.results || []),
          {
            label: 'Content-Type is application/json (fallback)',
            ok: contentType.includes('application/json'),
            actual: contentType || '—',
          },
        ],
        bodyText: pretty,
        responseStatus: res.status,
        responseHeaders,
        responseBody: parsedBody,
        requestId,
      };
    } finally {
      if (state.probeAbort === controller) state.probeAbort = null;
    }
  }

  async function executeConcurrentBurstProbe(probeKey, probe, bodyObj) {
    const count = probe.concurrent_count || 3;
    const requestMeta = buildProbeRequestMeta(probe, bodyObj, { 'Content-Type': 'application/json' });
    const tasks = Array.from({ length: count }, (_, i) =>
      fetchGenerateOnce(probe.path, bodyObj, null)
        .then((result) => ({ index: i + 1, ...result }))
        .catch((err) => ({
          index: i + 1,
          status: null,
          errorCode: null,
          networkError: err.name === 'AbortError' ? 'aborted' : String(err),
        }))
    );
    const results = await Promise.all(tasks);
    const evaluation = evaluateBurstExpect(probe.expect, results);
    const has429 = results.some((r) => r.status === 429 || r.errorCode === 'rate_limited');
    const hasBusy = results.some((r) => r.errorCode === 'ai_busy');
    let statusLine = `${count} parallel requests`;
    if (has429) statusLine += ' · 429 detected';
    if (hasBusy) statusLine += ' · ai_busy detected';

    state.probeResults[probeKey] = {
      ...requestMeta,
      requestNote: `×${count} parallel identical requests`,
      statusLine,
      pass: evaluation.pass,
      expect: evaluation.results,
      renderType: 'table',
      tableHtml: formatConcurrentTableHtml(results),
      bodyText: results.map((r) => `req ${r.index}: HTTP ${r.status} ${r.errorCode || ''}`).join('\n'),
      responseStatus: results[0]?.status ?? null,
      responseHeaders: results.find((r) => r.requestId)
        ? { 'X-Request-ID': results.find((r) => r.requestId).requestId }
        : {},
      responseBody: results,
      requestId: results.find((r) => r.requestId)?.requestId || null,
    };
  }

  async function executeAbortMidStreamProbe(probeKey, probe, bodyObj) {
    if (state.probeAbort) state.probeAbort.abort();
    const controller = new AbortController();
    state.probeAbort = controller;
    const requestMeta = buildProbeRequestMeta(probe, bodyObj, { 'Content-Type': 'application/json' });
    const abortTimer = window.setTimeout(() => controller.abort(), 1000);
    const started = Date.now();
    let partialRaw = '';

    try {
      const headers = buildProbeRequestHeaders(probe, { 'Content-Type': 'application/json' });
      const res = await fetch(probe.path, {
        method: 'POST',
        headers,
        body: JSON.stringify(bodyObj),
        signal: controller.signal,
      });
      if (res.body) {
        partialRaw = await readSseResponseBody(res, (raw) => { partialRaw = raw; });
      }
      window.clearTimeout(abortTimer);
      const elapsed = Date.now() - started;
      const responseHeaders = pickResponseHeaders(res);
      state.probeResults[probeKey] = {
        ...requestMeta,
        statusLine: `Completed in ${elapsed}ms (abort did not fire first)`,
        pass: null,
        expect: [],
        renderType: 'sse',
        sseHtml: formatSseHtml(partialRaw || '(empty stream)'),
        bodyText: partialRaw,
        responseStatus: res.status,
        responseHeaders,
        responseBody: partialRaw,
        requestId: res.headers.get('X-Request-ID'),
      };
    } catch (e) {
      window.clearTimeout(abortTimer);
      const elapsed = Date.now() - started;
      if (e.name === 'AbortError') {
        state.probeResults[probeKey] = {
          ...requestMeta,
          statusLine: `Aborted after ~${elapsed}ms`,
          pass: null,
          expect: [{
            label: 'Client disconnect logged as cancelled',
            ok: true,
            actual: 'Check gateway.jsonl for outcome=cancelled',
          }],
          renderType: 'sse',
          sseHtml: formatSseHtml(partialRaw || '(no SSE lines before abort)'),
          bodyText: partialRaw || '(no SSE lines before abort)',
          responseStatus: null,
          responseHeaders: {},
          responseBody: partialRaw || null,
          requestId: null,
        };
        return;
      }
      throw e;
    } finally {
      if (state.probeAbort === controller) state.probeAbort = null;
    }
  }

  async function executeMetricsQueueDepthProbe(probeKey, probe) {
    const requestMeta = buildProbeRequestMeta(probe, null);
    const { res, body, requestId } = await probeFetch(probe, { method: 'GET' });
    const text = typeof body === 'string' ? body : '';
    state.metricsRaw = text;
    state.metricsParsed = parsePrometheus(text);
    renderMetrics();

    const gauges = gaugesByLabel(state.metricsParsed, 'ai_queue_depth', 'capability');
    const entries = Object.entries(gauges);
    const total = entries.reduce((sum, [, v]) => sum + v, 0);
    const lines = entries.length
      ? entries.map(([cap, depth]) => `ai_queue_depth{capability="${cap}"} ${depth}`).join('\n')
      : '(no ai_queue_depth samples)';
    const excerpt = text.split('\n').filter((l) => l.includes('ai_queue')).join('\n') || '(none)';

    const evaluation = evaluateExpect(probe.expect, res, body);
    state.probeResults[probeKey] = {
      ...requestMeta,
      statusLine: `${res.status} · ai_queue_depth total ${total}`,
      pass: evaluation.pass,
      expect: [
        ...evaluation.results,
        {
          label: 'ai_queue_depth gauge present',
          ok: entries.length > 0,
          actual: entries.length ? `${entries.length} capability class(es)` : 'none',
        },
      ],
      bodyText: `${lines}\n\n--- /metrics excerpt ---\n${excerpt}`,
      responseStatus: res.status,
      responseHeaders: pickResponseHeaders(res),
      responseBody: text,
      requestId,
    };
  }

  async function executeStandardProbe(probeKey, probe, bodyObj) {
    const opts = { method: probe.method, headers: {} };
    if (bodyObj != null) {
      opts.headers['Content-Type'] = 'application/json';
      opts.body = JSON.stringify(bodyObj);
    }
    const requestMeta = buildProbeRequestMeta(probe, bodyObj, opts.headers);

    const { res, body, requestId } = await probeFetch(probe, opts);
    let evaluation = evaluateExpect(probe.expect, res, body);

    if ((probe.id === 'phase6-adversarial' || probe.id === 'safety-adversarial') && res.ok) {
      const commandType = body?.command_type;
      const catalogOk = CATALOG_COMMAND_TYPES.includes(commandType);
      evaluation = {
        pass: evaluation.pass !== false && catalogOk,
        results: [
          ...evaluation.results,
          {
            label: 'command_type in catalog (UI check)',
            ok: catalogOk,
            actual: commandType ?? '—',
          },
        ],
      };
    }

    const code = body?.error?.code;
    const retryAfter = res.headers.get('Retry-After');
    const retryHint = code === 'ai_busy' && retryAfter ? ` · Retry-After: ${retryAfter}s` : '';
    state.probeResults[probeKey] = {
      ...requestMeta,
      statusLine: `${res.status} ${res.statusText}${code ? ` (${code})` : ''}${retryHint}`,
      pass: evaluation.pass,
      expect: evaluation.results,
      bodyText: typeof body === 'string' ? body : JSON.stringify(body, null, 2),
      responseStatus: res.status,
      responseHeaders: pickResponseHeaders(res),
      responseBody: body,
      requestId,
    };

    if ((probe.id === 'phase6-phi-generate' || probe.id === 'safety-phi-generate') && requestId) {
      state.lastPhiRequestId = requestId;
      state.probeResults[probeKey].requestIdProminent = true;
    }

    if (probe.path === '/health' && res.ok) {
      state.health.ok = true;
      $('vital-health').dataset.state = 'ok';
      $('vital-health-value').textContent = 'Up';
    }
    if (probe.path === '/ready') {
      state.ready = { ok: res.ok, status: res.status, body };
      const el = $('vital-ready');
      const val = $('vital-ready-value');
      el.dataset.state = res.ok ? 'ok' : 'error';
      val.textContent = res.ok ? 'Ready' : `Not ready (${res.status})`;
    }
    if (probe.path === '/v1/capabilities' && res.ok) {
      state.capabilities = { ok: true, body };
      renderCapabilities();
    }

    $('last-refresh').textContent = `Probe ${probe.method} ${probe.path} · ${new Date().toLocaleTimeString()}`;
  }




  function probeAuthLabel(auth) {
    if (auth === 'jwt') return 'JWT';
    if (auth === 'jwt_no_ai') return 'no ai.access';
    return 'open';
  }

  function probeAuthBlocked(probe) {
    if (probe.auth === 'jwt') return !state.token;
    if (probe.auth === 'jwt_no_ai') return !state.tokenNoAi;
    return false;
  }

  function probeAuthBlockedTitle(probe) {
    if (probe.auth === 'jwt') return 'Save a staff JWT in Dashboard auth first';
    if (probe.auth === 'jwt_no_ai') return 'Paste a receptionist JWT in the no ai.access field';
    return '';
  }

  const RESPONSE_HEADER_KEYS = ['X-Request-ID', 'Content-Type', 'Retry-After'];

  function redactAuthorizationHeader(value, authMode) {
    if (!value) return value;
    if (authMode === 'jwt_no_ai') return 'Bearer •••• (no ai.access)';
    return 'Bearer ••••';
  }

  function buildProbeRequestHeaders(probe, extraHeaders = {}) {
    const headers = { ...extraHeaders };
    if (probe.auth === 'jwt' && state.token) {
      headers.Authorization = `Bearer ${state.token}`;
    } else if (probe.auth === 'jwt_no_ai' && state.tokenNoAi) {
      headers.Authorization = `Bearer ${state.tokenNoAi}`;
    }
    return headers;
  }

  function displayProbeRequestHeaders(probe, rawHeaders) {
    const display = { ...rawHeaders };
    if (display.Authorization) {
      display.Authorization = redactAuthorizationHeader(display.Authorization, probe.auth);
    }
    return display;
  }

  function pickResponseHeaders(res) {
    if (!res?.headers) return {};
    if (state.matrixHeaderCaptureAll) {
      const out = {};
      res.headers.forEach((v, k) => { out[k] = v; });
      return out;
    }
    const out = {};
    for (const key of RESPONSE_HEADER_KEYS) {
      const val = res.headers.get(key);
      if (val) out[key] = val;
    }
    return out;
  }

  function buildProbeRequestMeta(probe, bodyObj, extraHeaders = {}) {
    const rawHeaders = buildProbeRequestHeaders(probe, extraHeaders);
    return {
      requestMethod: probe.method || 'GET',
      requestPath: probe.path,
      requestHeaders: displayProbeRequestHeaders(probe, rawHeaders),
      requestBody: bodyObj != null ? bodyObj : null,
    };
  }

  function formatProbeHeadersHtml(headers) {
    if (!headers || !Object.keys(headers).length) {
      return '<p class="pv-transcript__empty">No headers</p>';
    }
    return `<dl class="pv-headers mono">${Object.entries(headers).map(([k, v]) =>
      `<div><dt>${escapeHtml(k)}</dt><dd>${escapeHtml(v)}</dd></div>`).join('')}</dl>`;
  }

  function formatProbeJsonHtml(value) {
    if (value == null) {
      return '<p class="pv-transcript__empty">No body</p>';
    }
    const text = typeof value === 'string' ? value : JSON.stringify(value, null, 2);
    return `<pre class="pv-transcript__code mono" tabindex="0">${escapeHtml(text)}</pre>`;
  }

  function statusClassFromCode(status) {
    if (status == null) return '';
    if (status >= 200 && status < 300) return 'ok';
    if (status >= 400 && status < 500) return 'warn';
    if (status >= 500) return 'error';
    return '';
  }





  async function dispatchProbeExecution(probeKey, probe, bodyObj) {
    switch (probe.special) {
      case 'sse_stream':
        await executeSseStreamProbe(probeKey, probe, bodyObj);
        break;
      case 'concurrent_burst':
        await executeConcurrentBurstProbe(probeKey, probe, bodyObj);
        break;
      case 'abort_mid_stream':
        await executeAbortMidStreamProbe(probeKey, probe, bodyObj);
        break;
      case 'metrics_queue_depth':
        await executeMetricsQueueDepthProbe(probeKey, probe);
        break;
      default:
        await executeStandardProbe(probeKey, probe, bodyObj);
    }
  }


  /* ── Workbench ────────────────────────────────────────── */

  async function sendWorkbench(ev) {
    ev.preventDefault();
    const method = $('workbench-method').value;
    const path = $('workbench-path').value.trim();
    const bodyText = $('workbench-body').value.trim();
    const panel = $('workbench-response');
    panel.hidden = false;

    const opts = { method, headers: {} };
    if (bodyText && method !== 'GET' && method !== 'HEAD') {
      opts.headers['Content-Type'] = 'application/json';
      opts.body = bodyText;
    }

    try {
      const { res, body, requestId } = await apiFetch(path, opts);
      $('workbench-response-status').textContent = `${res.status} ${res.statusText}`;
      $('workbench-response-status').dataset.class = res.ok ? 'ok' : 'error';
      $('workbench-response-path').textContent = `${method} ${path}`;
      $('workbench-response-rid').textContent = requestId ? `req ${requestId}` : '';
      $('workbench-response-body').textContent = typeof body === 'string'
        ? body
        : JSON.stringify(body, null, 2);
    } catch (e) {
      $('workbench-response-status').textContent = 'Request failed';
      $('workbench-response-status').dataset.class = 'error';
      $('workbench-response-body').textContent = `Network error. Check the path and gateway logs.\n\n${e}`;
    }
  }

  async function sendGenerateRequest(ev) {
    ev.preventDefault();
    if (!state.token || !state.hasAiAccess) {
      renderGenerateAuthHint();
      $('generate-auth-hint')?.scrollIntoView({ behavior: 'smooth', block: 'nearest' });
      return;
    }

    let bodyObj;
    try {
      bodyObj = buildGenerateBody();
    } catch (e) {
      renderGenerateResult({
        ...buildGenerateRequestMeta({}),
        statusLine: 'Invalid request',
        ok: false,
        responseStatus: null,
        responseHeaders: {},
        responseBody: { error: { code: 'bad_request', message: String(e) } },
        requestId: null,
      });
      return;
    }

    if (state.generateAbort) state.generateAbort.abort();
    const controller = new AbortController();
    state.generateAbort = controller;
    setGenerateLoading(true);

    const started = performance.now();
    const isStreaming = !!bodyObj.options?.stream;
    const requestMeta = buildGenerateRequestMeta(bodyObj, { stream: isStreaming });
    const path = '/v1/ai/generate';

    if (isStreaming) {
      resetGenerateStreamOutput();
    } else {
      hideGenerateStreamOutput({ force: true });
    }

    try {
      const headers = { 'Content-Type': 'application/json' };
      if (state.token) headers.Authorization = `Bearer ${state.token}`;

      const res = await fetch(path, {
        method: 'POST',
        headers,
        body: JSON.stringify(bodyObj),
        signal: controller.signal,
      });

      const elapsedMs = Math.round(performance.now() - started);
      const requestId = res.headers.get('X-Request-ID');
      const responseHeaders = pickAllResponseHeaders(res);
      const contentType = res.headers.get('content-type') || '';

      if (contentType.includes('text/event-stream') && res.body) {
        const raw = await readSseResponseBody(res, (partialRaw) => {
          updateGenerateStreamOutput(partialRaw);
        });
        const sseEvents = parseSseEvents(raw);
        const errorEvent = sseEvents.find((e) => e.event === 'error');
        const finalEvent = sseEvents.find((e) => e.event === 'final');
        const errCode = errorEvent?.data?.error?.code;
        const retryAfter = res.headers.get('Retry-After');
        const retryHint = errCode === 'ai_busy' && retryAfter ? ` · Retry-After: ${retryAfter}s` : '';
        const streamOk = res.ok && !errorEvent;

        updateGenerateStreamOutput(raw);
        finishGenerateStreamOutput({
          ok: streamOk,
          errorMessage: errorEvent?.data?.error?.message || (streamOk ? null : 'Stream failed'),
        });

        renderGenerateResult({
          ...requestMeta,
          statusLine: `${res.status} SSE stream${errCode ? ` (${errCode})` : ''}${retryHint}`,
          ok: streamOk,
          renderType: 'sse',
          sseHtml: formatSseHtml(raw),
          bodyText: raw,
          responseStatus: res.status,
          responseHeaders,
          responseBody: finalEvent?.data || errorEvent?.data || raw,
          requestId,
          elapsedMs,
        });
        return;
      }

      let body = null;
      if (isStreaming) {
        finishGenerateStreamOutput({ ok: false, errorMessage: 'No SSE stream' });
      } else {
        hideGenerateStreamOutput({ force: true });
      }
      if (contentType.includes('application/json')) {
        body = await res.json().catch(() => null);
      } else {
        body = await res.text();
      }

      const errCode = body?.error?.code;
      const retryAfter = res.headers.get('Retry-After');
      const retryHint = errCode === 'ai_busy' && retryAfter ? ` · Retry-After: ${retryAfter}s` : '';

      renderGenerateResult({
        ...requestMeta,
        statusLine: `${res.status} ${res.statusText}${errCode ? ` (${errCode})` : ''}${retryHint}`,
        ok: res.ok,
        responseStatus: res.status,
        responseHeaders,
        responseBody: body,
        bodyText: typeof body === 'string' ? body : JSON.stringify(body, null, 2),
        requestId,
        elapsedMs,
      });
    } catch (e) {
      const elapsedMs = Math.round(performance.now() - started);
      if (e.name === 'AbortError') {
        if (isStreaming) {
          finishGenerateStreamOutput({ ok: false, errorMessage: 'Cancelled' });
        }
        renderGenerateResult({
          ...requestMeta,
          statusLine: 'Cancelled',
          ok: false,
          responseStatus: null,
          responseHeaders: {},
          responseBody: { error: { code: 'aborted', message: 'Request cancelled by operator' } },
          requestId: null,
          elapsedMs,
          networkError: 'aborted',
        });
      } else {
        if (isStreaming) {
          finishGenerateStreamOutput({ ok: false, errorMessage: 'Network error' });
        }
        renderGenerateResult({
          ...requestMeta,
          statusLine: 'Network error',
          ok: false,
          responseStatus: null,
          responseHeaders: {},
          responseBody: null,
          requestId: null,
          elapsedMs,
          networkError: String(e),
        });
      }
    } finally {
      if (state.generateAbort === controller) state.generateAbort = null;
      setGenerateLoading(false);
    }
  }

  function pickAllResponseHeaders(res) {
    const out = {};
    if (!res?.headers) return out;
    res.headers.forEach((v, k) => { out[k] = v; });
    return out;
  }

  function buildGenerateRequestMeta(bodyObj, options = {}) {
    const rawHeaders = { 'Content-Type': 'application/json' };
    if (state.token) rawHeaders.Authorization = `Bearer ${state.token}`;
    const display = { ...rawHeaders };
    if (display.Authorization) display.Authorization = 'Bearer ••••';
    return {
      requestMethod: 'POST',
      requestPath: '/v1/ai/generate',
      requestHeaders: display,
      requestBody: bodyObj,
      requestNote: options.stream ? 'Streaming enabled — expects text/event-stream' : null,
    };
  }

  function buildGenerateContext() {
    const text = $('generate-context').value.trim();
    let context = defaultGenerateContext();
    if (text) {
      try {
        const parsed = JSON.parse(text);
        if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed)) {
          throw new Error('Context must be a JSON object.');
        }
        context = { ...context, ...parsed };
        if (!context.now) {
          context.now = new Date().toISOString();
        }
      } catch (e) {
        throw new Error(`Invalid context JSON: ${e.message}`);
      }
    }
    return context;
  }

  function buildGenerateBody() {
    const prompt = $('generate-prompt').value.trim();
    if (!prompt) throw new Error('Enter a prompt before routing.');

    const body = {
      task: 'command',
      prompt,
      context: buildGenerateContext(),
    };

    const stream = $('generate-stream').checked;
    const confidenceHint = $('generate-confidence').checked;
    const options = {};
    if (stream) options.stream = true;
    if (!confidenceHint) options.confidence_hint = false;
    if (Object.keys(options).length) body.options = options;

    return body;
  }

  function setGenerateLoading(loading) {
    const submit = $('generate-submit-btn');
    const cancel = $('generate-cancel-btn');
    submit.disabled = loading;
    submit.textContent = loading ? 'Routing…' : 'Route to runner';
    cancel.hidden = !loading;
  }

  function renderGenerateAuthHint() {
    const hint = $('generate-auth-hint');
    if (!hint) return;
    hint.hidden = !!(state.token && state.hasAiAccess);
  }

  function parseSseEvents(raw) {
    const events = [];
    const blocks = (raw || '').split(/\n\n+/);
    for (const block of blocks) {
      const lines = block.split('\n');
      let event = 'message';
      let data = '';
      for (const line of lines) {
        if (line.startsWith('event: ')) event = line.slice(7).trim();
        else if (line.startsWith('data: ')) data += (data ? '\n' : '') + line.slice(6);
      }
      if (data) {
        try {
          events.push({ event, data: JSON.parse(data) });
        } catch {
          events.push({ event, data });
        }
      }
    }
    return events;
  }

  /** Extract runner text from output/summary/token SSE events (not wire format or final envelope). */
  function extractRunnerOutputFromSse(raw) {
    let output = '';
    let hasOutputEvents = false;
    for (const e of parseSseEvents(raw)) {
      if (e.event === 'output' && e.data?.delta) {
        hasOutputEvents = true;
        output += e.data.delta;
      }
    }
    if (hasOutputEvents) return output;
    for (const e of parseSseEvents(raw)) {
      if ((e.event === 'summary' || e.event === 'token') && e.data?.delta) {
        output += e.data.delta;
      }
    }
    return output;
  }

  function resetGenerateStreamOutput() {
    const panel = $('generate-stream-output');
    const body = $('generate-stream-output-body');
    const status = $('generate-stream-output-status');
    if (!panel || !body || !status) return;
    panel.hidden = false;
    panel.dataset.state = 'streaming';
    body.textContent = '';
    status.textContent = 'Streaming…';
    status.dataset.state = 'streaming';
  }

  function updateGenerateStreamOutput(raw) {
    const body = $('generate-stream-output-body');
    if (!body) return;
    const text = extractRunnerOutputFromSse(raw);
    body.textContent = text;
    if (text) body.scrollTop = body.scrollHeight;
  }

  function finishGenerateStreamOutput({ ok = true, errorMessage = null } = {}) {
    const panel = $('generate-stream-output');
    const status = $('generate-stream-output-status');
    if (!panel || !status) return;
    panel.dataset.state = ok ? 'complete' : 'error';
    if (ok) {
      status.textContent = 'Complete';
      status.dataset.state = 'complete';
    } else {
      status.textContent = errorMessage || 'Error';
      status.dataset.state = 'error';
    }
  }

  function hideGenerateStreamOutput({ force = false } = {}) {
    const panel = $('generate-stream-output');
    const status = $('generate-stream-output-status');
    if (!panel) return;
    if (!force && $('generate-stream')?.checked) return;
    panel.hidden = true;
    if (status) {
      status.textContent = '—';
      status.dataset.state = 'idle';
    }
  }

  function renderGenerateResult(result) {
    const panel = $('generate-result');
    panel.hidden = false;

    const statusEl = $('generate-result-status');
    const code = result.responseBody?.error?.code;
    const statusClass = statusClassFromCode(result.responseStatus)
      || (code === 'ai_busy' ? 'warn' : (result.ok === false ? 'error' : 'ok'));
    statusEl.textContent = result.statusLine || '—';
    statusEl.dataset.class = statusClass;

    $('generate-result-rid').textContent = result.requestId ? `req ${result.requestId}` : '';

    const errBanner = $('generate-error-banner');
    const err = result.responseBody?.error;
    if (err) {
      errBanner.hidden = false;
      $('generate-error-code').textContent = err.code || 'error';
      $('generate-error-message').textContent = err.message || 'Request failed';
      $('generate-error-rid').textContent = err.request_id || result.requestId || '';
    } else if (result.networkError && result.networkError !== 'aborted') {
      errBanner.hidden = false;
      $('generate-error-code').textContent = 'network_error';
      $('generate-error-message').textContent = result.networkError;
      $('generate-error-rid').textContent = result.requestId || '';
    } else {
      errBanner.hidden = true;
    }

    const warnings = result.responseBody?.warnings;
    const warnPanel = $('generate-warnings');
    const warnList = $('generate-warnings-list');
    if (warnings?.length) {
      warnPanel.hidden = false;
      warnList.innerHTML = warnings.map((w) => `<li>${escapeHtml(w)}</li>`).join('');
    } else {
      warnPanel.hidden = true;
      warnList.innerHTML = '';
    }

    $('generate-transcript').innerHTML = renderProbeTranscriptSplit('generate', result);
    initPvSplitters(panel);

    const timingEl = $('generate-timing');
    if (result.elapsedMs != null) {
      timingEl.hidden = false;
      timingEl.textContent = `${result.elapsedMs} ms`;
    } else {
      timingEl.hidden = true;
    }
  }

  function cancelGenerateRequest() {
    if (state.generateAbort) state.generateAbort.abort();
  }

  function initGenerateForm() {
    const promptEl = $('generate-prompt');
    if (promptEl && !promptEl.value) promptEl.value = GENERATE_PRESETS.create;
    renderGenerateAuthHint();
  }

  function bindGenerateEvents() {
    $('generate-form').addEventListener('submit', sendGenerateRequest);
    $('generate-cancel-btn').addEventListener('click', cancelGenerateRequest);
    $('generate-stream')?.addEventListener('change', () => {
      const panel = $('generate-stream-output');
      const status = $('generate-stream-output-status');
      if (!$('generate-stream')?.checked) {
        if (panel) panel.hidden = true;
        if (status) {
          status.textContent = '—';
          status.dataset.state = 'idle';
        }
        return;
      }
      if (panel && status?.dataset.state !== 'streaming') {
        panel.hidden = false;
        if (status.dataset.state === 'idle') {
          status.textContent = 'Ready';
        }
      }
    });
    document.querySelectorAll('.generate-preset').forEach((btn) => {
      btn.addEventListener('click', () => {
        const preset = GENERATE_PRESETS[btn.dataset.preset];
        if (preset) $('generate-prompt').value = preset;
      });
    });
  }

  /* ── Feature test matrix ─────────────────────────────── */

  const MATRIX_GROUP_ICONS = {
    health: '◉',
    discovery: '◈',
    commands: '⌘',
    streaming: '≋',
    'auth-validation': '⛨',
    resilience: '⚡',
    safety: '◆',
    observability: '▤',
  };

  function getFeatureMatrix() {
    return window.FeatureMatrix || {};
  }

  function isMatrixVerbose() {
    const el = $('matrix-verbose');
    return el ? el.checked : true;
  }

  function getAllMatrixFeatures() {
    const groups = getFeatureMatrix().groups || [];
    const features = [];
    groups.forEach((group) => {
      (group.features || []).forEach((feature) => {
        features.push({ ...feature, groupId: group.id });
      });
    });
    return features;
  }

  function findMatrixFeature(featureId) {
    for (const group of getFeatureMatrix().groups || []) {
      const feature = (group.features || []).find((f) => f.id === featureId);
      if (feature) return { ...feature, groupId: group.id };
    }
    return null;
  }

  function findMatrixScenario(scenarioId) {
    return (getFeatureMatrix().scenarios || []).find((s) => s.id === scenarioId) || null;
  }

  function matrixScenarioKey(scenarioId) {
    return `scenario:${scenarioId}`;
  }

  function normalizeMatrixFeature(feature) {
    return {
      ...feature,
      label: feature.title || feature.label || feature.id,
      desc: feature.description || feature.desc || '',
      title: feature.title || feature.label || feature.id,
      description: feature.description || feature.desc || '',
    };
  }

  function captureMatrixUiState() {
    const openGroups = new Set();
    document.querySelectorAll('.matrix-group[data-group-id]').forEach((el) => {
      if (el.open) openGroups.add(el.dataset.groupId);
    });
    return { openGroups, selected: new Set(state.matrixSelectedFeatures) };
  }

  function renderMatrixFeatureTags(tags) {
    if (!tags?.length) return '';
    return tags.map((tag) => `<span class="matrix-tag">${escapeHtml(tag)}</span>`).join('');
  }

  function renderMatrixTranscript(key, result) {
    if (!isMatrixVerbose()) return '';
    if (!result || result.infoOnly) {
      return `<p class="matrix-step-log__skip">${escapeHtml(result?.description || result?.statusLine || 'Info only — no request sent')}</p>`;
    }
    const authLine = result.authMode != null
      ? `<span>Auth: <span class="mono">${escapeHtml(probeAuthLabel(result.authMode))}</span></span>`
      : '';
    const timing = result.latency_ms != null
      ? `<span class="matrix-transcript__timing mono">${result.latency_ms} ms</span>`
      : '';
    const bar = (authLine || timing)
      ? `<div class="matrix-transcript__bar">${authLine}${timing}</div>`
      : '';
    return `
      <div class="matrix-transcript" data-matrix-transcript="${escapeHtml(key)}">
        ${bar}
        ${renderProbeTranscriptSplit(key, result)}
      </div>
    `;
  }

  function renderMatrixFeatureResult(featureId) {
    const result = state.matrixResults[featureId];
    if (!result) return '';
    const summaryClass = result.pass === true ? 'ok' : (result.pass === false ? 'error' : '');
    const verdictHtml = result.pass != null
      ? `<span class="pv-verdict" data-pass="${result.pass}">
          ${result.pass ? 'Expectations met' : 'Expectations failed'}
        </span>`
      : '';
    const expectHtml = result.expect?.length
      ? `<ul class="pv-expect" role="list">
          ${result.expect.map((row) => `
            <li class="pv-expect__row" data-pass="${row.ok}">
              <span class="pv-expect__icon" aria-hidden="true">${row.ok ? '✓' : '✗'}</span>
              <span class="pv-expect__label">${escapeHtml(row.label)}</span>
              <span class="pv-expect__actual mono">${escapeHtml(row.actual)}</span>
            </li>
          `).join('')}
        </ul>`
      : '';

    return `
      <div class="matrix-result" data-matrix-result="${escapeHtml(featureId)}">
        <header class="matrix-result__header">
          <div class="matrix-result__summary">
            <span class="matrix-result__status" data-class="${summaryClass}">
              ${escapeHtml(result.statusLine || '—')}
            </span>
            ${verdictHtml}
          </div>
          <div class="matrix-result__meta">
            ${result.requestId ? `<span class="mono">X-Request-ID: ${escapeHtml(result.requestId)}</span>` : ''}
            ${result.latency_ms != null ? `<span class="mono">${result.latency_ms} ms</span>` : ''}
          </div>
        </header>
        ${expectHtml}
        ${renderMatrixTranscript(featureId, result)}
      </div>
    `;
  }

  function renderMatrixScenarioSteps(scenario) {
    return (scenario.steps || []).map((step) => {
      if (step.featureId) {
        const feature = findMatrixFeature(step.featureId);
        return `<li>${escapeHtml(step.label || feature?.title || step.featureId)}</li>`;
      }
      return `<li>${escapeHtml(step.label || `${step.method || 'GET'} ${step.path || '—'}`)}</li>`;
    }).join('');
  }

  function renderMatrixScenarioResult(scenarioId) {
    const result = state.matrixResults[matrixScenarioKey(scenarioId)];
    if (!result) return '';
    const summaryClass = result.pass === true ? 'ok' : (result.pass === false ? 'error' : '');
    const stepsHtml = (result.steps || []).map((step, i) => `
      <article class="matrix-step-log__item" data-step-index="${i + 1}">
        <header class="matrix-step-log__head">
          <span class="matrix-step-log__label">${escapeHtml(step.label || `Step ${i + 1}`)}</span>
          ${step.latency_ms != null ? `<span class="matrix-step-log__timing mono">${step.latency_ms} ms</span>` : ''}
        </header>
        ${step.skipped
        ? `<p class="matrix-step-log__skip">${escapeHtml(step.statusLine || 'Skipped')}</p>`
        : renderMatrixTranscript(`${scenarioId}:step${i + 1}`, step)}
      </article>
    `).join('');

    return `
      <div class="matrix-result matrix-result--scenario" data-scenario-result="${escapeHtml(scenarioId)}">
        <header class="matrix-result__header">
          <div class="matrix-result__summary">
            <span class="matrix-result__status" data-class="${summaryClass}">
              ${escapeHtml(result.statusLine || '—')}
            </span>
          </div>
          <div class="matrix-result__meta">
            ${result.latency_ms != null ? `<span class="mono">Total ${result.latency_ms} ms</span>` : ''}
          </div>
        </header>
        <div class="matrix-step-log">${stepsHtml}</div>
      </div>
    `;
  }

  function renderFeatureMatrix() {
    const pane = $('matrix-features-pane');
    if (!pane) return;

    const data = getFeatureMatrix();
    const groups = data.groups || [];
    const { openGroups, selected } = captureMatrixUiState();
    state.matrixSelectedFeatures = selected;

    if (!groups.length) {
      pane.innerHTML = '<p class="matrix-empty">Feature matrix catalog not loaded — ensure <span class="mono">feature-matrix.js</span> is present.</p>';
      renderMatrixScenarios();
      return;
    }

    pane.innerHTML = `
      <div class="matrix-catalog" role="list">
        ${groups.map((group) => {
      const features = group.features || [];
      const icon = MATRIX_GROUP_ICONS[group.id] || '◇';
      const isOpen = openGroups.has(group.id);
      return `
            <details class="matrix-group" data-group-id="${escapeHtml(group.id)}"${isOpen ? ' open' : ''}>
              <summary class="matrix-group__summary">
                <span class="matrix-group__icon" aria-hidden="true">${icon}</span>
                <span class="matrix-group__head">
                  <span class="matrix-group__title">${escapeHtml(group.title || group.id)}</span>
                  <span class="matrix-group__count mono">${features.length} feature${features.length === 1 ? '' : 's'}</span>
                </span>
              </summary>
              ${group.description ? `<p class="matrix-group__desc">${escapeHtml(group.description)}</p>` : ''}
              <div class="matrix-features" role="list">
                ${features.map((rawFeature) => {
        const feature = normalizeMatrixFeature(rawFeature);
        const isInfoOnly = feature.special === 'info_only';
        const isManual = feature.special === 'manual';
        const blocked = probeAuthBlocked(feature);
        const hasResult = !!state.matrixResults[feature.id];
        const checked = state.matrixSelectedFeatures.has(feature.id);
        return `
                    <article class="matrix-feature${isInfoOnly ? ' matrix-feature--info' : ''}${hasResult ? ' matrix-feature--has-result' : ''}"
                      role="listitem" data-feature-id="${escapeHtml(feature.id)}">
                      <div class="matrix-feature__row">
                        <label class="matrix-feature__select">
                          <input type="checkbox" class="matrix-feature-checkbox" data-feature-id="${escapeHtml(feature.id)}"
                            ${checked ? 'checked' : ''} ${isInfoOnly ? 'disabled' : ''}
                            aria-label="Select ${escapeHtml(feature.title)}">
                        </label>
                        <div class="matrix-feature__route">
                          <span class="matrix-feature__method">${escapeHtml(feature.method || 'GET')}</span>
                          <span class="matrix-feature__path mono">${escapeHtml(feature.path || '—')}</span>
                        </div>
                        <div class="matrix-feature__tags">
                          <span class="pv-chip pv-chip--auth" data-auth="${feature.auth || 'none'}">${probeAuthLabel(feature.auth)}</span>
                          ${probeSpecialBadge(feature)}
                          ${renderMatrixFeatureTags(feature.tags)}
                        </div>
                        <div class="matrix-feature__actions">
                          ${isInfoOnly
            ? ''
            : `<button type="button" class="btn btn--trace matrix-feature-run-btn"
                                data-feature-id="${escapeHtml(feature.id)}"
                                ${blocked ? `disabled title="${escapeHtml(probeAuthBlockedTitle(feature))}"` : ''}>
                                ${isManual ? 'Run feature (manual)' : 'Run feature'}
                              </button>`}
                        </div>
                      </div>
                      <div class="matrix-feature__detail">
                        <h4 class="matrix-feature__title">${escapeHtml(feature.title)}</h4>
                        <p class="matrix-feature__desc">${escapeHtml(feature.description)}</p>
                      </div>
                      ${renderMatrixFeatureResult(feature.id)}
                    </article>
                  `;
      }).join('')}
              </div>
            </details>
          `;
    }).join('')}
      </div>
    `;

    bindMatrixFeatureEvents(pane);
    initPvSplitters(pane);
    renderMatrixScenarios();
  }

  function renderMatrixScenarios() {
    const pane = $('matrix-scenarios-pane');
    if (!pane) return;

    const scenarios = getFeatureMatrix().scenarios || [];
    if (!scenarios.length) {
      pane.innerHTML = '<p class="matrix-empty">No combination flows defined in the feature matrix catalog.</p>';
      return;
    }

    pane.innerHTML = `
      <div class="matrix-scenarios" role="list">
        ${scenarios.map((scenario) => {
      const isManual = scenario.manual || (scenario.steps || []).some((s) => {
        const f = s.featureId ? findMatrixFeature(s.featureId) : s;
        return f?.special === 'manual';
      });
      const hasResult = !!state.matrixResults[matrixScenarioKey(scenario.id)];
      const result = state.matrixResults[matrixScenarioKey(scenario.id)];
      const statusState = state.matrixRunning && result?.running
        ? 'running'
        : (result?.pass === true ? 'ok' : (result?.pass === false ? 'error' : ''));
      return `
            <article class="matrix-scenario${isManual ? ' matrix-scenario--manual' : ''}${hasResult ? ' matrix-scenario--has-result' : ''}"
              role="listitem" data-scenario-id="${escapeHtml(scenario.id)}">
              <header class="matrix-scenario__header">
                <div>
                  <span class="matrix-scenario__id mono">${escapeHtml(scenario.id)}</span>
                  <h3 class="matrix-scenario__title">${escapeHtml(scenario.title || scenario.id)}</h3>
                  ${scenario.description ? `<p class="matrix-scenario__desc">${escapeHtml(scenario.description)}</p>` : ''}
                </div>
                <div class="matrix-scenario__actions">
                  <button type="button" class="btn btn--primary matrix-scenario-run-btn"
                    data-scenario-id="${escapeHtml(scenario.id)}"
                    ${state.matrixRunning ? 'disabled' : ''}>
                    Run combination flow
                  </button>
                  ${result?.statusLine
          ? `<span class="matrix-scenario__status" data-state="${statusState}">${escapeHtml(result.statusLine)}</span>`
          : ''}
                </div>
              </header>
              <ol class="matrix-scenario__steps">${renderMatrixScenarioSteps(scenario)}</ol>
              ${renderMatrixScenarioResult(scenario.id)}
            </article>
          `;
    }).join('')}
      </div>
    `;

    pane.querySelectorAll('.matrix-scenario-run-btn').forEach((btn) => {
      btn.addEventListener('click', () => runMatrixScenario(btn.dataset.scenarioId));
    });
    initPvSplitters(pane);
  }

  function bindMatrixFeatureEvents(root) {
    root.querySelectorAll('.matrix-feature-checkbox').forEach((input) => {
      input.addEventListener('change', () => {
        const id = input.dataset.featureId;
        if (!id) return;
        if (input.checked) state.matrixSelectedFeatures.add(id);
        else state.matrixSelectedFeatures.delete(id);
      });
    });

    root.querySelectorAll('.matrix-feature-run-btn').forEach((btn) => {
      btn.addEventListener('click', () => runMatrixFeature(btn.dataset.featureId));
    });
  }

  function updateMatrixFeatureResult(featureId) {
    const article = document.querySelector(`.matrix-feature[data-feature-id="${featureId}"]`);
    if (!article) return;
    if (state.matrixResults[featureId]) {
      article.classList.add('matrix-feature--has-result');
    }
    const existing = article.querySelector('.matrix-result');
    const html = renderMatrixFeatureResult(featureId);
    if (html) {
      if (existing) existing.outerHTML = html;
      else article.insertAdjacentHTML('beforeend', html);
      initPvSplitters(article);
    } else if (existing) {
      existing.remove();
      article.classList.remove('matrix-feature--has-result');
    }
  }

  function updateMatrixScenarioResult(scenarioId) {
    const article = document.querySelector(`.matrix-scenario[data-scenario-id="${scenarioId}"]`);
    if (!article) return;
    const existing = article.querySelector('.matrix-result--scenario');
    const html = renderMatrixScenarioResult(scenarioId);
    const statusEl = article.querySelector('.matrix-scenario__status');
    const result = state.matrixResults[matrixScenarioKey(scenarioId)];
    if (statusEl && result?.statusLine) {
      statusEl.textContent = result.statusLine;
      statusEl.dataset.state = result.pass === true ? 'ok' : (result.pass === false ? 'error' : '');
    }
    if (html) {
      if (existing) existing.outerHTML = html;
      else article.insertAdjacentHTML('beforeend', html);
      article.classList.add('matrix-scenario--has-result');
      initPvSplitters(article);
    }
  }

  async function runMatrixFeature(featureId, options = {}) {
    const { silent = false } = options;
    const feature = findMatrixFeature(featureId);
    if (!feature) return false;

    if (feature.special === 'info_only') {
      state.matrixResults[featureId] = {
        ...buildProbeRequestMeta(feature, null),
        statusLine: 'Info only — no request sent',
        pass: null,
        expect: [],
        infoOnly: true,
        description: feature.description || feature.desc || '',
        authMode: feature.auth || 'none',
        latency_ms: 0,
      };
      if (!silent) updateMatrixFeatureResult(featureId);
      return true;
    }

    if (feature.special === 'manual') {
      const desc = feature.description || feature.desc || 'This feature requires manual gateway configuration.';
      const ok = window.confirm(
        `Manual diagnostic feature\n\n${desc}\n\nOnly continue if you have applied the required config change. Proceed?`,
      );
      if (!ok) return false;
    }

    if (probeAuthBlocked(feature)) {
      if (!silent) window.alert(probeAuthBlockedTitle(feature));
      return false;
    }

    if (state.token && state.hasAiAccess && !state.traceStreamConnected) {
      connectTrace();
    }

    const probeKey = `mx:${featureId}`;
    const article = document.querySelector(`.matrix-feature[data-feature-id="${featureId}"]`);
    const runBtn = article?.querySelector('.matrix-feature-run-btn');
    if (runBtn) {
      runBtn.disabled = true;
      runBtn.textContent = 'Running…';
    }

    const bodyObj = feature.body ?? null;
    const started = performance.now();
    state.matrixHeaderCaptureAll = isMatrixVerbose();

    try {
      await dispatchProbeExecution(probeKey, feature, bodyObj);
      state.matrixResults[featureId] = {
        ...state.probeResults[probeKey],
        latency_ms: Math.round(performance.now() - started),
        authMode: feature.auth || 'none',
      };
      delete state.probeResults[probeKey];
      if (!silent) updateMatrixFeatureResult(featureId);
      return state.matrixResults[featureId].pass !== false;
    } catch (e) {
      const requestMeta = buildProbeRequestMeta(
        feature,
        bodyObj,
        bodyObj != null ? { 'Content-Type': 'application/json' } : {},
      );
      state.matrixResults[featureId] = {
        ...requestMeta,
        statusLine: 'Request failed',
        pass: false,
        expect: [],
        bodyText: `Network error. Check the gateway is running.\n\n${e}`,
        responseStatus: null,
        responseHeaders: {},
        responseBody: null,
        requestId: null,
        latency_ms: Math.round(performance.now() - started),
        authMode: feature.auth || 'none',
      };
      if (!silent) updateMatrixFeatureResult(featureId);
      return false;
    } finally {
      state.matrixHeaderCaptureAll = false;
      if (runBtn) {
        const blocked = probeAuthBlocked(feature);
        runBtn.disabled = blocked;
        runBtn.textContent = feature.special === 'manual' ? 'Run feature (manual)' : 'Run feature';
      }
    }
  }

  async function runMatrixScenario(scenarioId) {
    const scenario = findMatrixScenario(scenarioId);
    if (!scenario || state.matrixRunning) return;

    const hasManual = (scenario.steps || []).some((step) => {
      const f = step.featureId ? findMatrixFeature(step.featureId) : step;
      return f?.special === 'manual';
    });
    if (hasManual) {
      const ok = window.confirm(
        `Combination flow "${scenario.title || scenarioId}" includes manual steps.\n\nOnly continue if required gateway configuration is in place. Proceed?`,
      );
      if (!ok) return;
    }

    state.matrixRunning = true;
    const scenarioKey = matrixScenarioKey(scenarioId);
    const flowStarted = performance.now();
    const stepResults = [];
    let allPass = true;
    let stopped = false;

    state.matrixResults[scenarioKey] = {
      running: true,
      statusLine: 'Running combination flow…',
      steps: [],
      pass: null,
    };
    updateMatrixScenarioResult(scenarioId);

    for (let i = 0; i < (scenario.steps || []).length; i += 1) {
      const step = scenario.steps[i];
      const stepLabel = step.label || (step.featureId
        ? (findMatrixFeature(step.featureId)?.title || step.featureId)
        : `${step.method || 'GET'} ${step.path || '—'}`);
      const stepStarted = performance.now();

      if (step.featureId) {
        const feature = findMatrixFeature(step.featureId);
        if (!feature) {
          stepResults.push({
            label: stepLabel,
            skipped: true,
            statusLine: `Unknown feature: ${step.featureId}`,
            pass: false,
          });
          allPass = false;
          if (scenario.stopOnFail !== false) {
            stopped = true;
            break;
          }
          continue;
        }

        if (feature.special === 'info_only') {
          stepResults.push({
            label: stepLabel,
            skipped: true,
            statusLine: 'Info only — skipped in flow',
            pass: null,
            description: feature.description || feature.desc || '',
            latency_ms: 0,
          });
          continue;
        }

        const pass = await runMatrixFeature(step.featureId, { silent: true });
        const featureResult = state.matrixResults[step.featureId];
        stepResults.push({
          label: stepLabel,
          ...featureResult,
          latency_ms: featureResult?.latency_ms ?? Math.round(performance.now() - stepStarted),
          pass: featureResult?.pass,
        });
        if (!pass) {
          allPass = false;
          if (scenario.stopOnFail !== false) {
            stopped = true;
            break;
          }
        }
        continue;
      }

      const inlineProbe = normalizeMatrixFeature(step);
      if (inlineProbe.special === 'info_only') {
        stepResults.push({
          label: stepLabel,
          skipped: true,
          statusLine: 'Info only — skipped in flow',
          pass: null,
          description: inlineProbe.description,
          latency_ms: 0,
        });
        continue;
      }

      const inlineKey = `mx:inline:${scenarioId}:${i}`;
      state.matrixHeaderCaptureAll = isMatrixVerbose();
      try {
        const bodyObj = inlineProbe.body ?? null;
        await dispatchProbeExecution(inlineKey, inlineProbe, bodyObj);
        const inlineResult = {
          ...state.probeResults[inlineKey],
          latency_ms: Math.round(performance.now() - stepStarted),
          authMode: inlineProbe.auth || 'none',
        };
        delete state.probeResults[inlineKey];
        stepResults.push({ label: stepLabel, ...inlineResult });
        if (inlineResult.pass === false) {
          allPass = false;
          if (scenario.stopOnFail !== false) {
            stopped = true;
            break;
          }
        }
      } catch (e) {
        stepResults.push({
          label: stepLabel,
          statusLine: 'Request failed',
          pass: false,
          bodyText: String(e),
          latency_ms: Math.round(performance.now() - stepStarted),
        });
        allPass = false;
        if (scenario.stopOnFail !== false) {
          stopped = true;
          break;
        }
      } finally {
        state.matrixHeaderCaptureAll = false;
      }
    }

    state.matrixResults[scenarioKey] = {
      type: 'scenario',
      scenarioId,
      steps: stepResults,
      pass: allPass,
      stopped,
      latency_ms: Math.round(performance.now() - flowStarted),
      statusLine: allPass
        ? `Combination flow passed (${stepResults.length} steps)`
        : (stopped
          ? `Stopped on failure at step ${stepResults.length}`
          : `Combination flow finished with failures (${stepResults.length} steps)`),
    };

    state.matrixRunning = false;
    renderFeatureMatrix();
    updateMatrixScenarioResult(scenarioId);
  }

  async function runMatrixSelected() {
    if (state.matrixRunning) return;
    const ids = [...state.matrixSelectedFeatures];
    if (!ids.length) {
      window.alert('Select at least one feature to run.');
      return;
    }

    state.matrixRunning = true;
    const btn = $('matrix-run-selected-btn');
    if (btn) {
      btn.disabled = true;
      btn.textContent = 'Running selected…';
    }

    for (const id of ids) {
      await runMatrixFeature(id, { silent: true });
    }

    state.matrixRunning = false;
    renderFeatureMatrix();
    if (btn) {
      btn.disabled = false;
      btn.textContent = 'Run selected';
    }
  }

  async function runMatrixAll() {
    if (state.matrixRunning) return;
    const features = getAllMatrixFeatures().filter((f) => f.special !== 'info_only');
    if (!features.length) return;

    state.matrixRunning = true;
    const btn = $('matrix-run-all-btn');
    if (btn) {
      btn.disabled = true;
      btn.textContent = 'Running all…';
    }

    for (const feature of features) {
      await runMatrixFeature(feature.id, { silent: true });
    }

    state.matrixRunning = false;
    renderFeatureMatrix();
    if (btn) {
      btn.disabled = false;
      btn.textContent = 'Run all features';
    }
  }

  function switchMatrixTab(tab) {
    state.matrixActiveTab = tab;
    document.querySelectorAll('.matrix-tab').forEach((btn) => {
      const active = btn.dataset.tab === tab;
      btn.setAttribute('aria-selected', active ? 'true' : 'false');
    });
    const featuresPane = $('matrix-features-pane');
    const scenariosPane = $('matrix-scenarios-pane');
    if (featuresPane) featuresPane.hidden = tab !== 'features';
    if (scenariosPane) scenariosPane.hidden = tab !== 'scenarios';
  }

  function bindMatrixEvents() {
    document.querySelectorAll('.matrix-tab').forEach((btn) => {
      btn.addEventListener('click', () => switchMatrixTab(btn.dataset.tab || 'features'));
    });
    $('matrix-run-selected-btn')?.addEventListener('click', runMatrixSelected);
    $('matrix-run-all-btn')?.addEventListener('click', runMatrixAll);
    $('matrix-verbose')?.addEventListener('change', () => {
      renderFeatureMatrix();
    });
  }


  /* ── Utils ────────────────────────────────────────────── */

  function escapeHtml(str) {
    return String(str)
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;');
  }

  /* ── Init ─────────────────────────────────────────────── */

  function bindEvents() {
    $('refresh-btn').addEventListener('click', refreshAll);
    $('poll-interval').addEventListener('change', startPolling);

    $('trace-connect-btn').addEventListener('click', toggleTraceStream);

    $('auth-save-btn').addEventListener('click', async () => {
      const t = $('auth-token').value.trim();
      const tNoAi = $('auth-token-no-ai').value.trim();
      saveToken(t);
      saveTokenNoAi(tNoAi);
      state.tokenNoAi = tNoAi || null;
      applyToken(t);
      renderClientRequests();
    });
    $('auth-clear-btn').addEventListener('click', async () => {
      $('auth-token').value = '';
      $('auth-token-no-ai').value = '';
      saveToken(null);
      saveTokenNoAi(null);
      state.tokenNoAi = null;
      applyToken(null);
      renderClientRequests();
    });
    $('auth-sign-in-btn').addEventListener('click', signIn);

    $('trace-pause-btn').addEventListener('click', () => {
      const wasPaused = state.tracePaused;
      state.tracePaused = !state.tracePaused;
      $('trace-pause-btn').setAttribute('aria-pressed', state.tracePaused ? 'true' : 'false');
      $('trace-pause-btn').textContent = state.tracePaused ? 'Resume' : 'Pause';
      const conn = $('trace-connection');
      conn.dataset.state = state.tracePaused ? 'paused' : 'live';
      conn.textContent = state.tracePaused ? 'Paused' : 'Live';
      $('trace-stream').setAttribute('aria-live', state.tracePaused ? 'off' : 'polite');
      if (wasPaused && !state.tracePaused && state.tracePausedBuffer.length) {
        const buffered = state.tracePausedBuffer.splice(0);
        buffered.forEach((event) => appendTraceEvent(event, true));
      }
    });

    $('trace-clear-btn').addEventListener('click', clearTraceView);

    $('trace-inspector-close').addEventListener('click', deselectTraceEvent);
    document.querySelectorAll('.trace-inspector__tab').forEach((btn) => {
      btn.addEventListener('click', () => setInspectorTab(btn.dataset.tab || 'overview'));
    });

    $('trace-filter-btn').addEventListener('click', (e) => {
      e.stopPropagation();
      toggleFilterPanel();
    });
    $('trace-filter-close').addEventListener('click', closeFilterPanel);
    $('trace-filter-reset').addEventListener('click', clearAllFilters);
    $('trace-filter-form').addEventListener('submit', (e) => {
      e.preventDefault();
      applyFiltersFromForm();
      closeFilterPanel();
    });

    ['filter-direction', 'filter-kind', 'filter-runner', 'filter-status'].forEach((id) => {
      $(id).addEventListener('change', () => {
        if (state.traceFilterPanelOpen) applyFiltersFromForm();
      });
    });
    $('filter-path-prefix').addEventListener('change', () => {
      if (state.traceFilterPanelOpen) applyFiltersFromForm();
    });

    document.addEventListener('click', (e) => {
      if (!state.traceFilterPanelOpen) return;
      const wrap = document.querySelector('.trace-filter-wrap');
      if (wrap && !wrap.contains(e.target)) closeFilterPanel();
    });
    document.addEventListener('keydown', (e) => {
      if (e.key === 'Escape' && state.traceFilterPanelOpen) closeFilterPanel();
      if (e.key === 'Escape' && state.selectedTraceId) deselectTraceEvent();
    });

    $('workbench-form').addEventListener('submit', sendWorkbench);
    bindGenerateEvents();
    bindMatrixEvents();
  }

  async function init() {
    bindEvents();
    const saved = loadToken();
    if (saved) {
      $('auth-token').value = saved;
      applyToken(saved);
    }
    const savedNoAi = loadTokenNoAi();
    if (savedNoAi) {
      $('auth-token-no-ai').value = savedNoAi;
      state.tokenNoAi = savedNoAi;
    }
    await fetchAuthConfig();
    renderClientRequests();
    renderRunners();
    renderCapabilities();
    renderMetrics();
    renderSecurity();
    renderTraceFilters();
    renderFeatureMatrix();
    initGenerateForm();
    $('last-refresh').textContent = 'Manual mode — use Client requests or Refresh panels';
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
})();
