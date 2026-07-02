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

  /** Phase descriptor — maps phases to DOM sections and optional capability probes. */
  const PHASES = {
    1: {
      label: 'Foundation',
      sections: ['security-panel', 'endpoint-explorer'],
    },
    2: {
      label: 'Health & Registry',
      sections: ['runners-panel'],
    },
    3: {
      label: 'Observability',
      sections: ['overview-section', 'metrics-panel'],
    },
    4: {
      label: 'Auth',
      sections: [],
      probe: { path: '/v1/capabilities', method: 'GET', expectStatus: [401, 403] },
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
  };

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
      headers: { ...(opts.headers || {}) },
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
    return { ok: res.ok, status: res.status, body, headers: res.headers };
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
    const ready = state.ready.ok || gw?.ready;

    const readyBadge = $('readiness-badge');
    if (readyBadge) readyBadge.dataset.ready = ready ? 'true' : 'false';
    setText($('readiness-label'), ready ? 'Ready' : 'Not ready');

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
      state.ready.ok ? 'READY' : 'NOT READY',
      state.ready.status ? `HTTP ${state.ready.status}` : '/ready',
      state.ready.ok ? 'ok' : 'warn'
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

    const capChips = caps.map((c) => `<span class="chip chip--cap">${escapeHtml(c)}</span>`).join('');
    const featChips = features.map((f) => `<span class="chip chip--feature">${escapeHtml(f)}</span>`).join('');

    return `
      <article class="runner-card" role="listitem" data-runner-id="${escapeHtml(runner.id)}" data-status="${escapeHtml(runner.status)}">
        <header class="runner-card__header">
          <h3 class="runner-card__id">${escapeHtml(runner.id)}</h3>
          <span class="runner-card__badge ${lifecycleBadgeClass(runner.status)}">${escapeHtml(runner.status)}</span>
        </header>
        <dl class="runner-card__details">
          <div class="runner-card__row"><dt>Base URL</dt><dd class="mono">${escapeHtml(runner.base_url || '—')}</dd></div>
          <div class="runner-card__row"><dt>Model</dt><dd>${escapeHtml(model.name || '—')} <span class="digest mono">${escapeHtml(shortDigest(model.digest))}</span></dd></div>
          <div class="runner-card__row"><dt>Context</dt><dd>${model.context_tokens != null ? `${formatCount(model.context_tokens)} tokens` : '—'}</dd></div>
          <div class="runner-card__row"><dt>Last latency</dt><dd>${runner.last_latency_ms != null ? `${runner.last_latency_ms.toFixed(1)} ms` : '—'}</dd></div>
          <div class="runner-card__row"><dt>Avg latency</dt><dd>${runner.avg_latency_ms != null ? `${runner.avg_latency_ms.toFixed(1)} ms` : '—'}</dd></div>
          <div class="runner-card__row"><dt>In-flight</dt><dd>${runner.in_flight ?? 0}</dd></div>
          <div class="runner-card__row"><dt>Failures</dt><dd class="${(runner.consecutive_failures || 0) > 0 ? 'text-warn' : ''}">${runner.consecutive_failures ?? 0}</dd></div>
          <div class="runner-card__row"><dt>Last seen</dt><dd>${relativeTime(runner.last_seen_at)}</dd></div>
        </dl>
        ${caps.length ? `<div class="runner-card__chips"><span class="runner-card__chips-label">Capabilities</span>${capChips}</div>` : ''}
        ${features.length ? `<div class="runner-card__chips"><span class="runner-card__chips-label">Features</span>${featChips}</div>` : ''}
      </article>`;
  }

  function renderRunners() {
    const container = $('runner-cards');
    const empty = $('runners-empty');
    const runners = state.status?.runners || [];

    setText($('runners-count'), `${runners.length} registered`);
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
    const result = state.lastTryResult?.path === ep.path ? state.lastTryResult : null;
    const statusText = disabled ? `Phase ${ep.phase}` : result ? `HTTP ${result.status}` : '—';
    const methodClass = ep.method.toLowerCase();

    return `
      <tr class="explorer-table__row${disabled ? ' explorer-table__row--disabled' : ''}" data-path="${escapeHtml(ep.path)}">
        <td><code class="method method--${methodClass}">${escapeHtml(ep.method)}</code></td>
        <td class="mono">${escapeHtml(ep.path)}</td>
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

  function showResponsePanel(path, method, status, body) {
    state.lastTryResult = { path, method: method || 'GET', status, body };
    renderEndpointResponsePanel();
  }

  async function tryEndpoint(path, method, btn) {
    if (btn) {
      btn.disabled = true;
      btn.textContent = '…';
    }
    try {
      const result = await fetchEndpoint(path, { method: method || 'GET' });
      showResponsePanel(path, method, result.status, result.body);
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

  function renderSecurity() {
    const cfg = state.status?.config_safe;
    const gw = state.status?.gateway;

    setText($('gateway-uptime'), gw?.uptime_s != null ? formatUptime(gw.uptime_s) : '—');
    setText($('gateway-version'), gw?.version ? `· v${gw.version}` : '');

    const fields = [
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
  }

  async function probePhase(descriptor) {
    if (!descriptor.probe) return null;
    const { path, method, expectStatus } = descriptor.probe;
    try {
      const res = await fetchEndpoint(path, { method, timeoutMs: 4000 });
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
    const results = await Promise.allSettled([
      fetchEndpoint('/v1/status').then((r) => ({ kind: 'status', ...r })),
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
          if (data.ok) state.status = data.body;
          break;
        case 'health':
          state.health = { ok: data.ok, status: data.status, body: data.body };
          break;
        case 'ready':
          state.ready = { ok: data.ok, status: data.status, body: data.body };
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
    renderOverview();
    renderRunners();
    renderMetrics();
    renderEndpointExplorer();
    renderSecurity();
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

    document.addEventListener('visibilitychange', () => {
      if (document.hidden) stopPolling();
      else startPolling();
    });
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
