/**
 * Model Runner console — local Ollama operator UI.
 * Served by ai/runners/scripts/console_server.py
 */

const STORAGE = {
  baseUrl: 'runner_console_base_url',
  pollInterval: 'runner_console_poll_interval_s',
  model: 'runner_console_selected_model',
  runnerId: 'runner_console_gateway_runner_id',
  declaredCaps: 'runner_console_declared_caps',
  gatewayJwt: 'runner_console_gateway_jwt',
  gatewayUrl: 'runner_console_gateway_url',
  activePanel: 'runner_console_active_panel',
};

const DEFAULT_BASE = '/api/runner';
const DEFAULT_POLL_S = 8;
const THINK_CLOSE_RE = /<\/redacted_thinking>|<\/think>/i;
const THINK_OPEN_RE = /<(?:redacted_)?think\b[^>]*>/i;
const THINK_BLOCK_RE = /<think>([\s\S]*?)<\/redacted_thinking>|`?<think[^>]*>([\s\S]*?)<\/think>`?/gi;

const state = {
  baseUrl: DEFAULT_BASE,
  pollTimer: null,
  pollIntervalS: DEFAULT_POLL_S,
  models: [],
  selectedModel: '',
  messages: [],
  abortController: null,
  lastProbe: null,
  runtime: null,
  runtimeGpuPending: null,
  compose: null,
  telemetry: null,
  telemetryTab: 'parsed',
  streamChunks: [],
  gatewayRunnerId: 'ollama-local',
  declaredCapabilities: ['json_grammar'],
  gatewayJwt: '',
  gatewayUrl: 'http://127.0.0.1:8090',
  gatewayCapabilities: null,
  gatewayFetchMessage: '',
  gatewayStatus: null,
  gatewayMetricsRaw: '',
  activePanel: 'playground',
  serverConfig: null,
};

let generateAbort = null;

function $(id) {
  return document.getElementById(id);
}

function escapeHtml(text) {
  return String(text)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

function formatJson(value) {
  if (value == null) return '—';
  if (typeof value === 'string') return value;
  try {
    return JSON.stringify(value, null, 2);
  } catch {
    return String(value);
  }
}

function truncate(text, max = 8000) {
  const s = String(text);
  return s.length > max ? `${s.slice(0, max)}\n… [truncated]` : s;
}

function splitEmbeddedThinking(text) {
  if (!text) return { thinking: '', content: '' };
  const block = THINK_BLOCK_RE.exec(text);
  THINK_BLOCK_RE.lastIndex = 0;
  if (block) {
    return {
      thinking: (block[1] || block[2] || '').trim(),
      content: text.replace(block[0], '').trim(),
    };
  }
  const closeAt = text.search(THINK_CLOSE_RE);
  if (closeAt >= 0) {
    const thinking = text.slice(0, closeAt).replace(/<think>/i, '').replace(THINK_OPEN_RE, '').trim();
    const content = text.slice(closeAt).replace(THINK_CLOSE_RE, '').trim();
    return { thinking, content };
  }
  if (THINK_OPEN_RE.test(text) || /<think>/i.test(text)) {
    return { thinking: text.replace(THINK_OPEN_RE, '').replace(/<think>/i, '').trim(), content: '' };
  }
  return { thinking: '', content: text };
}

function formatDurationSeconds(ms) {
  if (ms == null || Number.isNaN(ms)) return '—';
  const s = ms / 1000;
  return s < 10 ? `${s.toFixed(1)} s` : `${Math.round(s)} s`;
}

function shortDigest(digest) {
  if (!digest) return '—';
  const s = String(digest);
  return s.length <= 20 ? s : `${s.slice(0, 14)}…${s.slice(-6)}`;
}

function formatCount(n) {
  if (n == null || Number.isNaN(n)) return '—';
  return new Intl.NumberFormat().format(n);
}

function relativeTime(iso) {
  if (!iso) return '—';
  const diff = Date.now() - new Date(iso).getTime();
  if (diff < 5000) return 'just now';
  if (diff < 60_000) return `${Math.round(diff / 1000)}s ago`;
  if (diff < 3_600_000) return `${Math.round(diff / 60_000)}m ago`;
  return new Date(iso).toLocaleTimeString();
}

function runnerUrl(path) {
  const base = state.baseUrl.replace(/\/$/, '');
  return `${base || DEFAULT_BASE}${path}`;
}

async function runnerFetch(path, options = {}) {
  const started = performance.now();
  const res = await fetch(runnerUrl(path), options);
  return { res, latencyMs: performance.now() - started };
}

async function consoleFetch(path, options = {}) {
  return fetch(path, options);
}

function gatewayHeaders() {
  const headers = {};
  if (state.gatewayJwt) {
    const token = state.gatewayJwt.startsWith('Bearer ') ? state.gatewayJwt : `Bearer ${state.gatewayJwt}`;
    headers.Authorization = token;
  }
  return headers;
}

/* ── Navigation ──────────────────────────────────────────── */

function switchPanel(panelId) {
  state.activePanel = panelId;
  localStorage.setItem(STORAGE.activePanel, panelId);

  document.querySelectorAll('[data-panel]').forEach((btn) => {
    const active = btn.dataset.panel === panelId;
    btn.classList.toggle('side-nav__btn--active', active);
    btn.setAttribute('aria-selected', active ? 'true' : 'false');
  });

  document.querySelectorAll('.panel').forEach((panel) => {
    const active = panel.id === `panel-${panelId}`;
    panel.classList.toggle('panel--active', active);
    panel.hidden = !active;
  });
}

/* ── Connection & model rail ─────────────────────────────── */

function setConnectionState(ok, label) {
  const pill = $('connection-pill');
  const labelEl = $('connection-label');
  if (pill) pill.dataset.state = ok ? 'ok' : ok === false ? 'error' : 'loading';
  if (labelEl) labelEl.textContent = label;
}

function processorBadgeClass(processor) {
  const p = String(processor || '').toUpperCase();
  return p.includes('GPU') ? 'model-slot__badge--gpu' : 'model-slot__badge--cpu';
}

function processorLabel(processor) {
  const p = String(processor || '').trim();
  if (!p) return 'CPU';
  if (/gpu/i.test(p)) return p.includes('%') ? p : 'GPU';
  if (/cpu/i.test(p)) return p.includes('%') ? p : 'CPU';
  return p;
}

function renderModelRail() {
  const track = $('model-rail-track');
  const empty = $('model-rail-empty');
  if (!track) return;

  const rows = state.runtime?.loaded_models || [];
  track.querySelectorAll('.model-slot').forEach((el) => el.remove());

  if (!rows.length) {
    if (empty) empty.hidden = false;
    return;
  }

  if (empty) empty.hidden = true;

  for (const row of rows) {
    const slot = document.createElement('article');
    slot.className = 'model-slot';
    slot.innerHTML = `
      <p class="model-slot__name" title="${escapeHtml(row.name || '')}">${escapeHtml(row.name || 'unknown')}</p>
      <div class="model-slot__meta">
        <span class="model-slot__badge ${processorBadgeClass(row.processor)}">${escapeHtml(processorLabel(row.processor))}</span>
        ${row.context ? `<span class="model-slot__ctx">${escapeHtml(row.context)} ctx</span>` : ''}
        ${row.size ? `<span class="model-slot__size">${escapeHtml(row.size)}</span>` : ''}
      </div>`;
    track.appendChild(slot);
  }
}

/* ── Models inventory ──────────────────────────────────────── */

function syncModelSelects() {
  const selects = [$('playground-model'), $('generate-model')];
  for (const sel of selects) {
    if (!sel) continue;
    const prev = sel.value || state.selectedModel;
    sel.innerHTML = state.models.length
      ? state.models.map((m) => `<option value="${escapeHtml(m.id)}">${escapeHtml(m.id)}</option>`).join('')
      : '<option value="">— no models —</option>';
    if (prev && state.models.some((m) => m.id === prev)) {
      sel.value = prev;
      state.selectedModel = prev;
    } else if (state.models[0]) {
      sel.value = state.models[0].id;
      state.selectedModel = state.models[0].id;
    }
  }
}

function renderModelsOverview() {
  const probe = state.lastProbe;
  const primary = state.models.find((m) => m.id === state.selectedModel) || state.models[0];

  if ($('metric-latency')) {
    $('metric-latency').textContent = probe?.ok ? `${probe.latencyMs.toFixed(0)} ms` : '—';
  }
  if ($('metric-model-count')) {
    $('metric-model-count').textContent = probe?.ok ? String(state.models.length) : '—';
  }
  if ($('metric-context')) {
    $('metric-context').textContent = primary?.context_length != null ? formatCount(primary.context_length) : '—';
  }
  if ($('metric-digest')) {
    $('metric-digest').textContent = shortDigest(primary?.digest);
  }

  const tbody = $('models-table-body');
  if (!tbody) return;

  if (!state.models.length) {
    tbody.innerHTML = '<tr><td colspan="4" class="data-table__empty">No models reported — probe the runner or pull a model</td></tr>';
    return;
  }

  tbody.innerHTML = state.models.map((m) => `
    <tr>
      <td class="mono">${escapeHtml(m.id)}</td>
      <td>${m.context_length != null ? formatCount(m.context_length) : '—'}</td>
      <td class="mono">${escapeHtml(shortDigest(m.digest))}</td>
      <td><button type="button" class="btn btn--ghost btn--select-model" data-model="${escapeHtml(m.id)}">Use in playground</button></td>
    </tr>`).join('');

  tbody.querySelectorAll('.btn--select-model').forEach((btn) => {
    btn.addEventListener('click', () => {
      state.selectedModel = btn.dataset.model;
      localStorage.setItem(STORAGE.model, state.selectedModel);
      syncModelSelects();
      switchPanel('playground');
    });
  });
}

async function fetchTagsRaw() {
  try {
    const { res } = await runnerFetch('/api/tags');
    const body = await res.json();
    if ($('models-tags-raw')) $('models-tags-raw').textContent = formatJson(body);
    return body;
  } catch (err) {
    if ($('models-tags-raw')) $('models-tags-raw').textContent = String(err.message || err);
    return null;
  }
}

async function probeModels({ manual = false } = {}) {
  if (manual) setConnectionState(null, 'Probing…');

  try {
    const { res, latencyMs } = await runnerFetch('/v1/models');
    const contentType = res.headers.get('content-type') || '';
    const body = contentType.includes('application/json') ? await res.json() : await res.text();

    state.lastProbe = { ok: res.ok, status: res.status, latencyMs, body, at: new Date().toISOString() };

    if (res.ok && body && Array.isArray(body.data)) {
      state.models = body.data.filter((m) => m && m.id);
      setConnectionState(true, `Online · ${latencyMs.toFixed(0)} ms`);
    } else if (res.ok) {
      state.models = [];
      setConnectionState(true, 'Online · empty list');
    } else {
      state.models = [];
      setConnectionState(false, `HTTP ${res.status}`);
    }

    renderModelsOverview();
    syncModelSelects();
    renderGatewayDiscovery();
    if ($('last-refresh')) $('last-refresh').textContent = relativeTime(state.lastProbe.at);
    return state.lastProbe;
  } catch (err) {
    state.models = [];
    state.lastProbe = { ok: false, error: String(err), at: new Date().toISOString() };
    setConnectionState(false, 'Unreachable');
    renderModelsOverview();
    syncModelSelects();
    return state.lastProbe;
  }
}

/* ── Runtime & compose ───────────────────────────────────── */

function renderRuntime() {
  const rt = state.runtime;
  const processorEl = $('runtime-processor');
  const hintEl = $('runtime-gpu-hint');
  const toggle = $('runtime-gpu-toggle');
  const applyBtn = $('runtime-gpu-apply');
  const note = $('runtime-note');

  if (!rt) {
    if (processorEl) processorEl.textContent = '—';
    if (hintEl) hintEl.textContent = 'Loading…';
    return;
  }

  const processor = rt.processor || (rt.ollama_online ? 'idle — no model loaded' : 'Ollama offline');
  if (processorEl) processorEl.textContent = processor;

  const gpuHint = rt.gpu_available
    ? (rt.gpu_enabled ? 'GPU compose profile active' : 'CPU-only compose profile')
    : 'NVIDIA not available to Docker — install nvidia-container-toolkit';
  if (hintEl) hintEl.textContent = gpuHint;

  const desiredGpu = state.runtimeGpuPending ?? rt.gpu_enabled;
  if (toggle) {
    toggle.checked = Boolean(desiredGpu);
    toggle.disabled = !rt.gpu_available;
  }

  const dirty = state.runtimeGpuPending != null && state.runtimeGpuPending !== rt.gpu_enabled;
  if (applyBtn) applyBtn.disabled = !dirty || !rt.gpu_available;

  if (note) {
    note.className = 'runtime-note';
    if (!rt.gpu_available) {
      note.classList.add('runtime-note--warn');
      note.textContent = 'Install NVIDIA Container Toolkit so Docker can access the GPU.';
    } else if (dirty) {
      note.classList.add('runtime-note--warn');
      note.textContent = 'Applying restarts Ollama. In-flight generation will be cancelled.';
    } else {
      note.textContent = 'Toggling restarts the Ollama container (~10–30 s).';
    }
  }

  renderModelRail();
  renderComposeStatus(rt.compose || state.compose);
}

function renderComposeStatus(compose) {
  if (!compose) return;
  const yesNo = (v) => (v ? 'running' : 'stopped');
  if ($('compose-container')) $('compose-container').textContent = yesNo(compose.container_running);
  if ($('compose-reachable')) {
    $('compose-reachable').textContent = compose.ollama_reachable || state.runtime?.ollama_online ? 'responding' : 'down';
  }
  if ($('compose-gpu')) {
    $('compose-gpu').textContent = compose.gpu_enabled ? 'enabled' : 'disabled';
  }
  if ($('compose-host-models')) $('compose-host-models').textContent = compose.host_models || '—';
}

async function refreshRuntime() {
  try {
    const res = await consoleFetch('/api/runtime');
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    state.runtime = await res.json();
    state.compose = state.runtime.compose;
    if (state.runtimeGpuPending == null) state.runtimeGpuPending = state.runtime.gpu_enabled;
    renderRuntime();
    return state.runtime;
  } catch (err) {
    if ($('runtime-gpu-hint')) $('runtime-gpu-hint').textContent = String(err.message || err);
    return null;
  }
}

async function refreshComposeStatus() {
  try {
    const res = await consoleFetch('/api/compose/status');
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    state.compose = await res.json();
    renderComposeStatus(state.compose);
    return state.compose;
  } catch (err) {
    if ($('compose-container')) $('compose-container').textContent = String(err.message || err);
    return null;
  }
}

async function applyGpuRuntime() {
  const toggle = $('runtime-gpu-toggle');
  const applyBtn = $('runtime-gpu-apply');
  const enabled = Boolean(toggle?.checked);
  state.runtimeGpuPending = enabled;
  renderRuntime();

  if (applyBtn) {
    applyBtn.disabled = true;
    applyBtn.textContent = 'Restarting…';
  }
  if ($('runtime-note')) $('runtime-note').textContent = 'Restarting Ollama — up to 30 seconds…';

  try {
    const res = await consoleFetch('/api/runtime', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ enabled }),
    });
    const body = await res.json();
    state.runtime = body;
    state.runtimeGpuPending = body.gpu_enabled;
    state.compose = body.compose;
    if (!body.ok) throw new Error(body.error || 'GPU toggle failed');
    await probeModels();
  } catch (err) {
    if ($('runtime-note')) {
      $('runtime-note').className = 'runtime-note runtime-note--error';
      $('runtime-note').textContent = String(err.message || err);
    }
  } finally {
    renderRuntime();
    if (applyBtn) applyBtn.textContent = 'Apply & restart Ollama';
  }
}

async function fetchRuntimeLogs() {
  const lines = parseInt($('logs-lines')?.value || '80', 10) || 80;
  const pre = $('runtime-logs');
  if (pre) pre.textContent = 'Fetching…';
  try {
    const res = await consoleFetch(`/api/runtime/logs?lines=${lines}`);
    const body = await res.json();
    if (pre) pre.textContent = body.text || '(empty)';
  } catch (err) {
    if (pre) pre.textContent = String(err.message || err);
  }
}

/* ── Chat playground ─────────────────────────────────────── */

function getPlaygroundSettings() {
  return {
    temperature: parseFloat($('playground-temperature')?.value || '0.7'),
    maxTokens: parseInt($('playground-max-tokens')?.value || '512', 10),
    stream: Boolean($('playground-stream')?.checked),
    think: $('playground-think')?.value || 'default',
  };
}

function buildChatRequest(model, messages, settings) {
  const payload = {
    model,
    messages,
    stream: settings.stream,
    options: {
      temperature: settings.temperature,
      num_predict: settings.maxTokens,
    },
  };
  if (settings.think === 'on') payload.think = true;
  else if (settings.think === 'off') payload.think = false;
  return payload;
}

function setPlaygroundBusy(busy, statusText = '') {
  const sendBtn = $('playground-send-btn');
  const stopBtn = $('playground-stop-btn');
  const status = $('playground-status');
  if (sendBtn) sendBtn.disabled = busy;
  if (stopBtn) stopBtn.hidden = !busy;
  if (status) status.textContent = statusText;
}

function renderPlaygroundMessages() {
  const container = $('playground-messages');
  const empty = $('playground-empty');
  if (!container) return;

  if (!state.messages.length) {
    container.innerHTML = '';
    if (empty) {
      empty.className = 'chat-log__empty';
      empty.textContent = 'Send a message to run inference on this node.';
      container.appendChild(empty);
    }
    return;
  }

  container.innerHTML = state.messages.map((msg, i) => {
    const roleClass = msg.error ? 'chat-msg--error' : `chat-msg--${msg.role}`;
    const thinking = msg.thinking
      ? `<div class="chat-msg__thinking">${escapeHtml(msg.thinking)}</div>`
      : '';
    const body = escapeHtml(msg.displayedContent ?? msg.content ?? '');
    const meta = msg.meta ? `<span class="chat-msg__meta">${escapeHtml(msg.meta)}</span>` : '';
    return `<article class="chat-msg ${roleClass}" data-idx="${i}">
      <span class="chat-msg__role">${escapeHtml(msg.role)}</span>
      ${thinking}
      <p class="chat-msg__body">${body}</p>
      ${meta}
    </article>`;
  }).join('');

  container.scrollTop = container.scrollHeight;
}

function beginTelemetry(request, model) {
  state.streamChunks = [];
  state.telemetry = {
    request,
    model,
    thinking: '',
    content: '',
    usage: null,
    doneReason: null,
    finalChunk: null,
    timing: { startedAt: performance.now() },
    error: null,
  };
  paintTelemetry();
}

function ingestTelemetryChunk(chunk) {
  if (!state.telemetry) return;
  state.streamChunks.push(chunk);

  const msg = chunk.message || {};
  if (msg.thinking) {
    state.telemetry.thinking += msg.thinking;
    const elapsed = performance.now() - state.telemetry.timing.startedAt;
    if (state.telemetry.timing.firstThinkingMs == null) state.telemetry.timing.firstThinkingMs = elapsed;
  }
  if (msg.content) {
    state.telemetry.content += msg.content;
    const elapsed = performance.now() - state.telemetry.timing.startedAt;
    if (state.telemetry.timing.firstContentMs == null) state.telemetry.timing.firstContentMs = elapsed;
  }

  if (chunk.done) {
    state.telemetry.finalChunk = chunk;
    state.telemetry.doneReason = chunk.done_reason || null;
    state.telemetry.usage = {
      prompt_eval_count: chunk.prompt_eval_count,
      eval_count: chunk.eval_count,
      total_duration: chunk.total_duration,
      load_duration: chunk.load_duration,
      prompt_eval_duration: chunk.prompt_eval_duration,
      eval_duration: chunk.eval_duration,
    };
    state.telemetry.timing.totalMs = performance.now() - state.telemetry.timing.startedAt;
  }
}

function buildParsedPayload(data) {
  const inProgress = data.doneReason == null && !data.error;
  const split = splitEmbeddedThinking(data.content);
  const thinking = data.thinking || split.thinking;
  const content = split.content || (thinking ? '' : data.content);
  return {
    thinking,
    content: inProgress && !content ? '' : content,
    usage: data.usage || null,
    done_reason: data.doneReason || null,
    final_chunk: inProgress ? null : data.finalChunk || null,
    timing: data.timing || null,
  };
}

function formatMetricsBar(data) {
  if (!data) return 'Awaiting inference…';
  const parts = [
    data.timing?.totalMs != null ? `${data.timing.totalMs.toFixed(0)} ms total` : null,
    data.timing?.firstContentMs != null ? `first token ${data.timing.firstContentMs.toFixed(0)} ms` : null,
    data.usage?.eval_count != null ? `${data.usage.eval_count} completion tokens` : null,
    data.usage?.prompt_eval_count != null ? `${data.usage.prompt_eval_count} prompt tokens` : null,
    data.model || null,
    data.error ? `error: ${data.error}` : null,
  ].filter(Boolean);
  return parts.length ? parts.join(' · ') : 'Running…';
}

function paintTelemetry() {
  const data = state.telemetry;
  const metrics = $('telemetry-metrics');
  const parsedPane = $('telemetry-pane-parsed');
  const requestPane = $('telemetry-pane-request');
  const streamPane = $('telemetry-pane-stream');

  if (!data) {
    if (metrics) metrics.textContent = 'Awaiting inference…';
    if (parsedPane) parsedPane.textContent = '—';
    if (requestPane) requestPane.textContent = '—';
    if (streamPane) streamPane.textContent = '—';
    return;
  }

  if (metrics) metrics.textContent = formatMetricsBar(data);
  if (requestPane) requestPane.textContent = formatJson(data.request);
  if (parsedPane) parsedPane.textContent = formatJson(buildParsedPayload(data));
  if (streamPane) streamPane.textContent = formatJson(state.streamChunks);
}

function setTelemetryTab(tab) {
  state.telemetryTab = tab;
  document.querySelectorAll('[data-telemetry-tab]').forEach((btn) => {
    const active = btn.dataset.telemetryTab === tab;
    btn.classList.toggle('inspector-tab--active', active);
    btn.setAttribute('aria-selected', active ? 'true' : 'false');
  });

  const panes = {
    parsed: $('telemetry-pane-parsed'),
    request: $('telemetry-pane-request'),
    stream: $('telemetry-pane-stream'),
  };
  for (const [name, el] of Object.entries(panes)) {
    if (!el) continue;
    const active = name === tab;
    el.hidden = !active;
    el.classList.toggle('inspector-pane--active', active);
  }
  paintTelemetry();
}

async function pumpNdjsonStream(reader, assistantIndex) {
  const decoder = new TextDecoder();
  let buffer = '';

  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    buffer += decoder.decode(value, { stream: true });

    let newlineAt;
    while ((newlineAt = buffer.indexOf('\n')) >= 0) {
      const line = buffer.slice(0, newlineAt).trim();
      buffer = buffer.slice(newlineAt + 1);
      if (!line) continue;
      try {
        const chunk = JSON.parse(line);
        ingestTelemetryChunk(chunk);
        const delta = chunk.message || {};
        const msg = state.messages[assistantIndex];
        if (msg) {
          if (delta.thinking) msg.thinking = (msg.thinking || '') + delta.thinking;
          if (delta.content) {
            msg.rawText = (msg.rawText || '') + delta.content;
            const split = splitEmbeddedThinking(msg.rawText);
            msg.thinking = msg.thinking || split.thinking;
            msg.content = split.content || (split.thinking ? '' : msg.rawText);
            msg.displayedContent = msg.content;
          }
        }
        paintTelemetry();
        renderPlaygroundMessages();
      } catch {
        /* skip malformed line */
      }
    }
  }
}

async function sendPlaygroundMessage(text) {
  const model = $('playground-model')?.value || state.selectedModel || state.models[0]?.id;
  if (!model) {
    state.messages.push({ role: 'system', content: 'No model available. Pull a model into Ollama first.', error: true });
    renderPlaygroundMessages();
    return;
  }

  state.selectedModel = model;
  localStorage.setItem(STORAGE.model, model);

  state.messages.push({ role: 'user', content: text });
  const assistantIndex = state.messages.length;
  state.messages.push({
    role: 'assistant',
    content: '',
    thinking: '',
    rawText: '',
    displayedContent: '',
    meta: 'Generating…',
  });
  renderPlaygroundMessages();

  const settings = getPlaygroundSettings();
  const history = state.messages
    .slice(0, assistantIndex)
    .filter((m) => m.role === 'user' || m.role === 'assistant')
    .map((m) => ({ role: m.role, content: m.content }));

  const requestPayload = buildChatRequest(model, history, settings);
  beginTelemetry(requestPayload, model);

  state.abortController = new AbortController();
  setPlaygroundBusy(true, settings.stream ? 'Streaming…' : 'Waiting…');
  const wallStart = performance.now();

  try {
    const { res } = await runnerFetch('/api/chat', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(requestPayload),
      signal: state.abortController.signal,
    });

    if (!res.ok) {
      const errBody = await res.text();
      throw new Error(`HTTP ${res.status}: ${errBody.slice(0, 500)}`);
    }

    if (settings.stream) {
      const reader = res.body.getReader();
      await pumpNdjsonStream(reader, assistantIndex);
      const elapsed = performance.now() - wallStart;
      state.messages[assistantIndex].meta = formatDurationSeconds(elapsed);
    } else {
      const body = await res.json();
      ingestTelemetryChunk(body);
      const delta = body.message || {};
      state.messages[assistantIndex].thinking = delta.thinking || '';
      state.messages[assistantIndex].rawText = delta.content || '';
      const split = splitEmbeddedThinking(state.messages[assistantIndex].rawText);
      state.messages[assistantIndex].thinking = state.messages[assistantIndex].thinking || split.thinking;
      state.messages[assistantIndex].content = split.content || state.messages[assistantIndex].rawText;
      state.messages[assistantIndex].displayedContent = state.messages[assistantIndex].content;
      const elapsed = performance.now() - wallStart;
      state.messages[assistantIndex].meta = formatDurationSeconds(elapsed);
    }
  } catch (err) {
    if (state.telemetry) {
      state.telemetry.error = String(err.message || err);
      state.telemetry.timing.totalMs = performance.now() - state.telemetry.timing.startedAt;
    }
    if (err.name === 'AbortError') {
      state.messages[assistantIndex].content = state.messages[assistantIndex].content || '[stopped]';
      state.messages[assistantIndex].meta = 'Cancelled';
    } else {
      state.messages[assistantIndex].content = String(err.message || err);
      state.messages[assistantIndex].error = true;
      state.messages[assistantIndex].meta = 'Error';
    }
  } finally {
    state.abortController = null;
    setPlaygroundBusy(false, '');
    renderPlaygroundMessages();
    paintTelemetry();
    refreshRuntime().catch(() => {});
  }
}

function stopPlayground() {
  state.abortController?.abort();
}

function clearPlayground() {
  state.messages = [];
  renderPlaygroundMessages();
}

/* ── Generate ──────────────────────────────────────────────── */

async function runGenerate() {
  const model = $('generate-model')?.value || state.selectedModel;
  const prompt = $('generate-prompt')?.value?.trim();
  const stream = Boolean($('generate-stream')?.checked);
  const output = $('generate-output');
  const status = $('generate-status');
  const runBtn = $('generate-run-btn');
  const stopBtn = $('generate-stop-btn');

  if (!model || !prompt) {
    if (status) status.textContent = 'Select a model and enter a prompt.';
    return;
  }

  generateAbort = new AbortController();
  if (runBtn) runBtn.disabled = true;
  if (stopBtn) stopBtn.hidden = false;
  if (status) status.textContent = stream ? 'Streaming…' : 'Waiting…';
  if (output) output.textContent = '';

  const payload = { model, prompt, stream };
  let text = '';

  try {
    const { res } = await runnerFetch('/api/generate', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(payload),
      signal: generateAbort.signal,
    });

    if (!res.ok) throw new Error(`HTTP ${res.status}: ${(await res.text()).slice(0, 400)}`);

    if (stream) {
      const reader = res.body.getReader();
      const decoder = new TextDecoder();
      let buffer = '';
      while (true) {
        const { done, value } = await reader.read();
        if (done) break;
        buffer += decoder.decode(value, { stream: true });
        let nl;
        while ((nl = buffer.indexOf('\n')) >= 0) {
          const line = buffer.slice(0, nl).trim();
          buffer = buffer.slice(nl + 1);
          if (!line) continue;
          try {
            const chunk = JSON.parse(line);
            if (chunk.response) {
              text += chunk.response;
              if (output) output.textContent = text;
            }
            if (chunk.done && output) output.textContent = formatJson({ response: text, ...chunk });
          } catch { /* skip */ }
        }
      }
      if (status) status.textContent = 'Done';
    } else {
      const body = await res.json();
      if (output) output.textContent = formatJson(body);
      if (status) status.textContent = 'Done';
    }
  } catch (err) {
    if (err.name === 'AbortError') {
      if (status) status.textContent = 'Cancelled';
    } else {
      if (output) output.textContent = String(err.message || err);
      if (status) status.textContent = 'Error';
    }
  } finally {
    generateAbort = null;
    if (runBtn) runBtn.disabled = false;
    if (stopBtn) stopBtn.hidden = true;
    refreshRuntime().catch(() => {});
  }
}

function stopGenerate() {
  generateAbort?.abort();
}

/* ── API explorer ────────────────────────────────────────── */

const EXPLORER_ENDPOINTS = {
  models: { path: '/v1/models', resultId: 'explorer-models-result' },
  tags: { path: '/api/tags', resultId: 'explorer-tags-result' },
  version: { path: '/api/version', resultId: 'explorer-version-result' },
};

async function runExplorerEndpoint(key) {
  const ep = EXPLORER_ENDPOINTS[key];
  if (!ep) return;
  const pre = $(ep.resultId);
  if (pre) pre.textContent = 'Running…';
  try {
    const { res, latencyMs } = await runnerFetch(ep.path);
    const ct = res.headers.get('content-type') || '';
    const body = ct.includes('application/json') ? await res.json() : await res.text();
    if (pre) pre.textContent = `HTTP ${res.status} · ${latencyMs.toFixed(0)} ms\n\n${formatJson(body)}`;
  } catch (err) {
    if (pre) pre.textContent = String(err.message || err);
  }
}

async function runCustomRequest() {
  const method = $('custom-method')?.value || 'GET';
  const path = $('custom-path')?.value || '/';
  const bodyRaw = $('custom-body')?.value?.trim();
  const pre = $('custom-result');
  if (pre) pre.textContent = 'Sending…';

  const options = { method };
  if (method === 'POST' && bodyRaw) {
    options.headers = { 'Content-Type': 'application/json' };
    options.body = bodyRaw;
  }

  try {
    const { res, latencyMs } = await runnerFetch(path.startsWith('/') ? path : `/${path}`, options);
    const ct = res.headers.get('content-type') || '';
    const body = ct.includes('application/json') ? await res.json() : await res.text();
    if (pre) pre.textContent = `HTTP ${res.status} · ${latencyMs.toFixed(0)} ms\n\n${truncate(formatJson(body))}`;
  } catch (err) {
    if (pre) pre.textContent = String(err.message || err);
  }
}

/* ── Gateway ─────────────────────────────────────────────── */

function lifecycleStatusFromProbe() {
  const probe = state.lastProbe;
  if (!probe?.ok) return 'UNREACHABLE';
  if (state.runtime?.loaded_model || state.models.length > 0) return 'READY';
  return 'STARTING';
}

function buildLocalCapabilityEntry() {
  const primary = state.models.find((m) => m.id === state.selectedModel) || state.models[0];
  return {
    id: state.gatewayRunnerId,
    status: lifecycleStatusFromProbe(),
    model: primary?.id || state.runtime?.loaded_model || null,
    digest: primary?.digest || null,
    features: [...state.declaredCapabilities],
    context_tokens: primary?.context_length ?? null,
  };
}

function renderGatewayDiscovery() {
  const local = buildLocalCapabilityEntry();
  if ($('gateway-local-preview')) $('gateway-local-preview').textContent = formatJson(local);
  if ($('obs-runner-id-label')) $('obs-runner-id-label').textContent = state.gatewayRunnerId;

  const live = state.gatewayCapabilities;
  if ($('gateway-live-capabilities')) {
    $('gateway-live-capabilities').textContent = live ? formatJson(live) : '—';
  }
  if ($('gateway-fetch-message')) {
    $('gateway-fetch-message').textContent = state.gatewayFetchMessage;
  }
}

function parsePrometheusForRunner(metricsText, runnerId) {
  if (!metricsText) return null;
  const lines = metricsText.split('\n');
  const out = {};
  const prefixes = [
    `aiclinic_runner_health{runner="${runnerId}"`,
    `aiclinic_runner_poll_latency_ms{runner="${runnerId}"`,
    `aiclinic_runner_inflight{runner="${runnerId}"`,
  ];
  for (const line of lines) {
    if (line.startsWith('#')) continue;
    for (const prefix of prefixes) {
      if (line.startsWith(prefix.split('{')[0])) {
        const m = line.match(/}\s+([0-9.eE+-]+)/);
        if (m) out[prefix] = m[1];
      }
    }
    if (line.includes(`runner="${runnerId}"`) && line.includes('aiclinic_runner_status')) {
      const m = line.match(/}\s+([0-9.eE+-]+)/);
      if (m) out.status = m[1];
    }
  }
  return out;
}

function renderGatewayObservability() {
  const gs = state.gatewayStatus;
  const runnerId = state.gatewayRunnerId;

  if (gs?.runners) {
    const entry = gs.runners.find((r) => r.id === runnerId) || gs.runners[0];
    if (entry) {
      if ($('obs-runner-status')) $('obs-runner-status').textContent = entry.status || '—';
      if ($('obs-runner-health')) $('obs-runner-health').textContent = entry.health ?? '—';
      if ($('obs-runner-latency')) {
        $('obs-runner-latency').textContent = entry.poll_latency_ms != null ? `${entry.poll_latency_ms} ms` : '—';
      }
      if ($('obs-runner-inflight')) $('obs-runner-inflight').textContent = entry.inflight ?? '—';
    }
  }

  if ($('observability-metrics-raw')) {
    $('observability-metrics-raw').textContent = state.gatewayMetricsRaw
      ? truncate(state.gatewayMetricsRaw, 12000)
      : '—';
  }
}

async function fetchGatewayCapabilities() {
  state.gatewayFetchMessage = 'Fetching…';
  renderGatewayDiscovery();
  try {
    const res = await consoleFetch('/api/gateway/capabilities', { headers: gatewayHeaders() });
    const body = await res.json();
    if (!res.ok) throw new Error(body.error || body.detail || `HTTP ${res.status}`);
    state.gatewayCapabilities = body;
    state.gatewayFetchMessage = `Fetched ${new Date().toLocaleTimeString()}`;
  } catch (err) {
    state.gatewayCapabilities = null;
    state.gatewayFetchMessage = String(err.message || err);
  }
  renderGatewayDiscovery();
  await fetchGatewayObservability();
}

async function gatewayAutoSignIn() {
  state.gatewayFetchMessage = 'Signing in…';
  renderGatewayDiscovery();
  try {
    const res = await consoleFetch('/api/gateway/auto-sign-in', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: '{}',
    });
    const body = await res.json();
    if (!res.ok) throw new Error(body.error || body.detail || `HTTP ${res.status}`);
    const token = body.token || body.access_token || body.jwt;
    if (!token) throw new Error('No token in response');
    state.gatewayJwt = token;
    localStorage.setItem(STORAGE.gatewayJwt, token);
    if ($('gateway-jwt-input')) $('gateway-jwt-input').value = token;
    state.gatewayFetchMessage = 'Signed in — fetch capabilities to verify';
  } catch (err) {
    state.gatewayFetchMessage = String(err.message || err);
  }
  renderGatewayDiscovery();
}

async function fetchGatewayObservability() {
  if (!state.gatewayJwt) {
    renderGatewayObservability();
    return;
  }
  try {
    const headers = gatewayHeaders();
    const [statusRes, metricsRes] = await Promise.all([
      consoleFetch('/api/gateway/status', { headers }),
      consoleFetch('/api/gateway/metrics', { headers: { Accept: 'text/plain' } }),
    ]);
    if (statusRes.ok) state.gatewayStatus = await statusRes.json();
    if (metricsRes.ok) state.gatewayMetricsRaw = await metricsRes.text();
  } catch {
    /* gateway optional */
  }
  renderGatewayObservability();
}

/* ── Settings & server config ────────────────────────────── */

function loadSettings() {
  state.baseUrl = localStorage.getItem(STORAGE.baseUrl) || DEFAULT_BASE;
  state.pollIntervalS = parseInt(localStorage.getItem(STORAGE.pollInterval) || String(DEFAULT_POLL_S), 10);
  state.selectedModel = localStorage.getItem(STORAGE.model) || '';
  state.gatewayRunnerId = localStorage.getItem(STORAGE.runnerId) || 'ollama-local';
  state.gatewayJwt = localStorage.getItem(STORAGE.gatewayJwt) || '';
  state.gatewayUrl = localStorage.getItem(STORAGE.gatewayUrl) || 'http://127.0.0.1:8090';
  state.activePanel = localStorage.getItem(STORAGE.activePanel) || 'playground';

  const capsRaw = localStorage.getItem(STORAGE.declaredCaps);
  if (capsRaw) state.declaredCapabilities = capsRaw.split(',').map((s) => s.trim()).filter(Boolean);

  if ($('runner-base-url')) $('runner-base-url').value = state.baseUrl;
  if ($('poll-interval')) $('poll-interval').value = state.pollIntervalS;
  if ($('gateway-runner-id')) $('gateway-runner-id').value = state.gatewayRunnerId;
  if ($('gateway-declared-caps')) $('gateway-declared-caps').value = state.declaredCapabilities.join(', ');
  if ($('gateway-jwt-input')) $('gateway-jwt-input').value = state.gatewayJwt;
  if ($('gateway-url-display')) $('gateway-url-display').value = state.gatewayUrl;
}

function saveSettings() {
  state.baseUrl = $('runner-base-url')?.value?.trim() || DEFAULT_BASE;
  state.pollIntervalS = parseInt($('poll-interval')?.value || String(DEFAULT_POLL_S), 10);
  state.gatewayRunnerId = $('gateway-runner-id')?.value?.trim() || 'ollama-local';
  state.gatewayUrl = $('gateway-url-display')?.value?.trim() || 'http://127.0.0.1:8090';
  state.declaredCapabilities = ($('gateway-declared-caps')?.value || 'json_grammar')
    .split(',')
    .map((s) => s.trim())
    .filter(Boolean);
  state.gatewayJwt = $('gateway-jwt-input')?.value || '';

  localStorage.setItem(STORAGE.baseUrl, state.baseUrl);
  localStorage.setItem(STORAGE.pollInterval, String(state.pollIntervalS));
  localStorage.setItem(STORAGE.runnerId, state.gatewayRunnerId);
  localStorage.setItem(STORAGE.declaredCaps, state.declaredCapabilities.join(','));
  localStorage.setItem(STORAGE.gatewayJwt, state.gatewayJwt);
  localStorage.setItem(STORAGE.gatewayUrl, state.gatewayUrl);

  restartPolling();
  renderGatewayDiscovery();
}

async function loadServerConfig() {
  try {
    const res = await consoleFetch('/api/config');
    if (!res.ok) return;
    state.serverConfig = await res.json();
    if ($('cfg-bind')) $('cfg-bind').textContent = `${state.serverConfig.host}:${state.serverConfig.port}`;
    if ($('cfg-ollama')) $('cfg-ollama').textContent = state.serverConfig.ollama_url;
    if ($('cfg-gateway')) $('cfg-gateway').textContent = state.serverConfig.gateway_url;
    if ($('gateway-url-display') && !localStorage.getItem(STORAGE.gatewayUrl)) {
      $('gateway-url-display').value = state.serverConfig.gateway_url;
      state.gatewayUrl = state.serverConfig.gateway_url;
    }
  } catch { /* optional */ }
}

/* ── Polling ─────────────────────────────────────────────── */

function restartPolling() {
  if (state.pollTimer) clearInterval(state.pollTimer);
  const interval = Math.max(3, Math.min(120, state.pollIntervalS)) * 1000;
  state.pollTimer = setInterval(() => {
    probeModels().catch(() => {});
    refreshRuntime().catch(() => {});
  }, interval);
}

async function refreshAll() {
  await Promise.all([probeModels({ manual: true }), refreshRuntime(), refreshComposeStatus()]);
}

/* ── Init ────────────────────────────────────────────────── */

function bindEvents() {
  document.querySelectorAll('[data-panel]').forEach((btn) => {
    btn.addEventListener('click', () => switchPanel(btn.dataset.panel));
  });

  $('refresh-btn')?.addEventListener('click', () => refreshAll());
  $('probe-btn')?.addEventListener('click', () => probeModels({ manual: true }));
  $('save-settings-btn')?.addEventListener('click', () => saveSettings());
  $('models-refresh-btn')?.addEventListener('click', () => {
    probeModels({ manual: true });
    fetchTagsRaw();
  });

  $('playground-form')?.addEventListener('submit', (e) => {
    e.preventDefault();
    const input = $('playground-input');
    const text = input?.value?.trim();
    if (!text) return;
    input.value = '';
    sendPlaygroundMessage(text);
  });

  $('playground-input')?.addEventListener('keydown', (e) => {
    if (e.key === 'Enter' && !e.shiftKey) {
      e.preventDefault();
      $('playground-form')?.requestSubmit();
    }
  });

  $('playground-stop-btn')?.addEventListener('click', stopPlayground);
  $('playground-clear-btn')?.addEventListener('click', clearPlayground);

  $('playground-model')?.addEventListener('change', (e) => {
    state.selectedModel = e.target.value;
    localStorage.setItem(STORAGE.model, state.selectedModel);
  });

  document.querySelectorAll('[data-telemetry-tab]').forEach((btn) => {
    btn.addEventListener('click', () => setTelemetryTab(btn.dataset.telemetryTab));
  });

  $('generate-run-btn')?.addEventListener('click', runGenerate);
  $('generate-stop-btn')?.addEventListener('click', stopGenerate);

  document.querySelectorAll('[data-endpoint]').forEach((btn) => {
    btn.addEventListener('click', () => runExplorerEndpoint(btn.dataset.endpoint));
  });
  $('custom-run-btn')?.addEventListener('click', runCustomRequest);

  $('runtime-gpu-toggle')?.addEventListener('change', () => {
    state.runtimeGpuPending = $('runtime-gpu-toggle')?.checked;
    renderRuntime();
  });
  $('runtime-gpu-apply')?.addEventListener('click', applyGpuRuntime);
  $('compose-refresh-btn')?.addEventListener('click', refreshComposeStatus);
  $('logs-fetch-btn')?.addEventListener('click', fetchRuntimeLogs);

  $('gateway-fetch-btn')?.addEventListener('click', () => {
    saveSettings();
    fetchGatewayCapabilities();
  });
  $('gateway-auto-sign-in-btn')?.addEventListener('click', gatewayAutoSignIn);

  $('gateway-runner-id')?.addEventListener('change', () => {
    state.gatewayRunnerId = $('gateway-runner-id').value;
    renderGatewayDiscovery();
  });
}

async function init() {
  loadSettings();
  bindEvents();
  switchPanel(state.activePanel);
  setTelemetryTab('parsed');

  await loadServerConfig();
  await refreshAll();
  fetchTagsRaw().catch(() => {});
  restartPolling();
}

init();
