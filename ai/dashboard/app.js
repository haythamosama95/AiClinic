/**
 * AI Gateway Signal Monitor — zero-build control plane dashboard.
 * Modules: state · auth · api · poll · trace · render
 */
(function () {
  'use strict';

  const TOKEN_KEY = 'dashboard_jwt_token';
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
      desc: 'Scheduling command proposals (non-streaming); SSE streaming in a later phase',
      defaultBody: '{"task":"command","prompt":"book Ahmed with Dr Ali tomorrow 5pm","options":{"stream":false}}',
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

    const cards = [
      { label: 'Total requests', value: requests, sub: 'gateway_requests_total' },
      { label: 'Total errors', value: errors, sub: 'gateway_errors_total' },
      { label: 'Healthy runners', value: Object.values(health).filter((v) => v === 1).length, sub: `of ${Object.keys(health).length}` },
      { label: 'In-flight total', value: Object.values(inflight).reduce((a, b) => a + b, 0), sub: 'across runners' },
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

  async function sendGenerateStub() {
    const panel = $('generate-response');
    panel.hidden = false;
    try {
      const { res, body, requestId } = await apiFetch('/v1/ai/generate', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ prompt: 'dashboard probe' }),
      });
      $('generate-response-status').textContent = `${res.status} — expected 501 stub`;
      $('generate-response-status').dataset.class = res.status === 501 ? 'ok' : 'error';
      $('generate-response-body').textContent = JSON.stringify(body, null, 2) +
        (requestId ? `\n\nX-Request-ID: ${requestId}` : '');
    } catch (e) {
      $('generate-response-status').textContent = 'Probe failed';
      $('generate-response-body').textContent = String(e);
    }
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

    $('auth-save-btn').addEventListener('click', () => {
      const t = $('auth-token').value.trim();
      saveToken(t);
      applyToken(t);
      renderClientRequests();
    });
    $('auth-clear-btn').addEventListener('click', () => {
      $('auth-token').value = '';
      saveToken(null);
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
    $('generate-btn').addEventListener('click', sendGenerateStub);
  }

  async function init() {
    bindEvents();
    const saved = loadToken();
    if (saved) {
      $('auth-token').value = saved;
      applyToken(saved);
    }
    await fetchAuthConfig();
    renderClientRequests();
    renderRunners();
    renderCapabilities();
    renderMetrics();
    renderSecurity();
    renderTraceFilters();
    $('last-refresh').textContent = 'Manual mode — use Client requests or Refresh panels';
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
})();
