/**
 * AI Model Runner console — local Ollama playground.
 * Served by ai/runners/scripts/console_server.py (static + /api/runtime + /api/runner proxy).
 */

const STORAGE_BASE_URL = 'runner_console_base_url';
const STORAGE_POLL_INTERVAL = 'runner_console_poll_interval_s';
const STORAGE_MODEL = 'runner_console_selected_model';

const DEFAULT_BASE_URL = '/api/runner';
const DEFAULT_POLL_S = 8;

const STORAGE_RUNNER_ID = 'runner_console_gateway_runner_id';
const STORAGE_DECLARED_CAPS = 'runner_console_declared_caps';
const STORAGE_GATEWAY_JWT = 'runner_console_gateway_jwt';

const THINK_CLOSE_RE = /<\/redacted_thinking>|<\/think>/i;
const THINK_OPEN_RE = /<(?:redacted_)?think\b[^>]*>/i;
const THINK_BLOCK_RE = /<think>([\s\S]*?)<\/redacted_thinking>|`?<think[^>]*>([\s\S]*?)<\/think>`?/gi;

const state = {
  baseUrl: DEFAULT_BASE_URL,
  pollTimer: null,
  pollIntervalS: DEFAULT_POLL_S,
  models: [],
  selectedModel: '',
  messages: [],
  abortController: null,
  lastProbe: null,
  runtime: null,
  runtimeGpuPending: null,
  telemetry: null,
  telemetryTab: 'parsed',
  gatewayRunnerId: 'ollama-local',
  declaredCapabilities: ['json_grammar'],
  gatewayJwt: '',
  gatewayCapabilities: null,
  gatewayFetchMessage: '',
};

let streamingAssistantIndex = null;
let streamingEls = null;
let streamPump = null;
let typewriterPump = null;

const PARSED_TELEMETRY_THROTTLE_MS = 500;
const SCROLL_NEAR_BOTTOM_PX = 80;
const TYPEWRITER_CHARS_PER_FRAME = 2;
const TYPEWRITER_FINISH_MS = 200;
let parsedTelemetryLastPaint = 0;

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

function truncate(text, max = 6000) {
  const s = String(text);
  return s.length > max ? `${s.slice(0, max)}\n… [truncated]` : s;
}

function splitEmbeddedThinking(text) {
  if (!text) return { thinking: '', content: '' };

  const block = THINK_BLOCK_RE.exec(text);
  THINK_BLOCK_RE.lastIndex = 0;
  if (block) {
    const thinking = (block[1] || block[2] || '').trim();
    const content = text.replace(block[0], '').trim();
    return { thinking, content };
  }

  const closeAt = text.search(THINK_CLOSE_RE);
  if (closeAt >= 0) {
    const thinking = text.slice(0, closeAt).replace(/<think>/i, '').replace(THINK_OPEN_RE, '').trim();
    const content = text.slice(closeAt).replace(THINK_CLOSE_RE, '').trim();
    return { thinking, content };
  }

  if (THINK_OPEN_RE.test(text) || /<think>/i.test(text)) {
    const thinking = text.replace(THINK_OPEN_RE, '').replace(/<think>/i, '').trim();
    return { thinking, content: '' };
  }

  return { thinking: '', content: text };
}

function stripThinkingFromContent(text) {
  if (!text) return '';
  return splitEmbeddedThinking(text).content;
}

function formatDurationSeconds(ms) {
  if (ms == null || Number.isNaN(ms)) return '—';
  const s = ms / 1000;
  return s < 10 ? `${s.toFixed(1)} s` : `${Math.round(s)} s`;
}

function shortDigest(digest) {
  if (!digest) return '—';
  const s = String(digest);
  if (s.length <= 20) return s;
  return `${s.slice(0, 14)}…${s.slice(-6)}`;
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
  if (!base) return `/api/runner${path}`;
  return `${base}${path}`;
}

async function runnerFetch(path, options = {}) {
  const started = performance.now();
  const res = await fetch(runnerUrl(path), options);
  return { res, latencyMs: performance.now() - started };
}

async function consoleFetch(path, options = {}) {
  return fetch(path, options);
}

function setConnectionState(ok, label) {
  const indicator = $('connection-indicator');
  const connectionLabel = $('connection-label');
  if (indicator) indicator.dataset.state = ok ? 'ok' : ok === false ? 'error' : 'loading';
  if (connectionLabel) connectionLabel.textContent = label;
}

function setLoadedModelBadge(model) {
  const badge = $('loaded-model-badge');
  const label = $('loaded-model-label');
  if (!badge || !label) return;
  if (model?.id) {
    badge.dataset.loaded = 'yes';
    label.textContent = model.id;
  } else {
    badge.dataset.loaded = 'no';
    label.textContent = 'No model loaded';
  }
}

function setWorkspaceStreaming(active) {
  const workspace = $('inference-workspace');
  if (workspace) workspace.dataset.streaming = active ? 'true' : 'false';
}

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
  const localPreview = $('gateway-local-preview');
  if (localPreview) {
    localPreview.textContent = formatJson(buildLocalCapabilityEntry());
  }

  const live = $('gateway-live-capabilities');
  if (live) {
    live.textContent = state.gatewayCapabilities
      ? formatJson(state.gatewayCapabilities)
      : 'Paste a gateway JWT or use dev auto sign-in, then Fetch capabilities.';
  }

  const fetched = $('gateway-capabilities-fetched');
  if (fetched) {
    fetched.textContent = state.gatewayCapabilities?.fetchedAt
      ? `Live · ${relativeTime(state.gatewayCapabilities.fetchedAt)}`
      : 'Not fetched';
  }

  const msg = $('gateway-fetch-message');
  if (msg) msg.textContent = state.gatewayFetchMessage || '';
}

async function fetchGatewayCapabilities({ manual = false } = {}) {
  const msgEl = $('gateway-fetch-message');
  const btn = $('gateway-fetch-btn');
  if (manual && btn) {
    btn.disabled = true;
    btn.textContent = 'Fetching…';
  }
  state.gatewayFetchMessage = '';

  const headers = { Accept: 'application/json' };
  if (state.gatewayJwt) {
    headers.Authorization = state.gatewayJwt.startsWith('Bearer ')
      ? state.gatewayJwt
      : `Bearer ${state.gatewayJwt}`;
  }

  try {
    const res = await consoleFetch('/api/gateway/capabilities', { headers });
    const body = await res.json().catch(() => ({}));
    if (!res.ok) {
      const errMsg = body?.error?.message || `HTTP ${res.status}`;
      state.gatewayFetchMessage = errMsg;
      if (manual) state.gatewayCapabilities = null;
      renderGatewayDiscovery();
      return null;
    }
    state.gatewayCapabilities = { ...body, fetchedAt: new Date().toISOString() };
    state.gatewayFetchMessage = manual ? 'Capabilities fetched.' : '';
    renderGatewayDiscovery();
    return body;
  } catch (err) {
    state.gatewayFetchMessage = String(err.message || err);
    if (manual) state.gatewayCapabilities = null;
    renderGatewayDiscovery();
    return null;
  } finally {
    if (btn) {
      btn.disabled = false;
      btn.textContent = 'Fetch capabilities';
    }
  }
}

async function gatewayAutoSignIn() {
  const btn = $('gateway-auto-sign-in-btn');
  if (btn) {
    btn.disabled = true;
    btn.textContent = 'Signing in…';
  }
  state.gatewayFetchMessage = '';

  try {
    const res = await consoleFetch('/api/gateway/auto-sign-in', {
      method: 'POST',
      headers: { Accept: 'application/json' },
    });
    const data = await res.json().catch(() => ({}));
    if (!res.ok) {
      state.gatewayFetchMessage = data?.error?.message || `Auto sign-in failed (HTTP ${res.status})`;
      renderGatewayDiscovery();
      return false;
    }
    state.gatewayJwt = data.access_token || '';
    localStorage.setItem(STORAGE_GATEWAY_JWT, state.gatewayJwt);
    const jwtInput = $('gateway-jwt-input');
    if (jwtInput) jwtInput.value = state.gatewayJwt;
    state.gatewayFetchMessage = data.staff_role
      ? `Signed in as ${data.staff_role}. Fetching capabilities…`
      : 'Signed in. Fetching capabilities…';
    renderGatewayDiscovery();
    await fetchGatewayCapabilities({ manual: true });
    return true;
  } catch (err) {
    state.gatewayFetchMessage = String(err.message || err);
    renderGatewayDiscovery();
    return false;
  } finally {
    if (btn) {
      btn.disabled = false;
      btn.textContent = 'Dev auto sign-in';
    }
  }
}

function saveGatewayConfigFromInputs() {
  const runnerId = $('gateway-runner-id')?.value?.trim();
  const capsRaw = $('gateway-declared-caps')?.value || '';
  const jwt = $('gateway-jwt-input')?.value?.trim() || '';

  if (runnerId) {
    state.gatewayRunnerId = runnerId;
    localStorage.setItem(STORAGE_RUNNER_ID, runnerId);
  }

  state.declaredCapabilities = capsRaw
    .split(',')
    .map((c) => c.trim())
    .filter(Boolean);
  localStorage.setItem(STORAGE_DECLARED_CAPS, state.declaredCapabilities.join(','));

  state.gatewayJwt = jwt;
  if (jwt) localStorage.setItem(STORAGE_GATEWAY_JWT, jwt);
  else localStorage.removeItem(STORAGE_GATEWAY_JWT);

  renderGatewayDiscovery();
}

/* ── Overview ─────────────────────────────────────────────── */

function renderOverview() {
  const probe = state.lastProbe;
  $('metric-latency').textContent = probe?.latencyMs != null ? probe.latencyMs.toFixed(1) : '—';
  $('metric-latency-hint').textContent = probe?.ok ? 'ms · OK' : probe ? 'ms · failed' : 'ms';
  $('metric-model-count').textContent = state.models.length ? String(state.models.length) : '0';

  const primary = state.models[0];
  $('metric-context').textContent = primary?.context_length != null
    ? formatCount(primary.context_length)
    : '—';
  $('metric-digest').textContent = shortDigest(primary?.digest);
}

/* ── Model dropdown (playground) ──────────────────────────── */

function syncModelSelect() {
  const select = $('playground-model');
  if (!select) return;

  if (!state.models.length) {
    select.innerHTML = '<option value="">— no models —</option>';
    setLoadedModelBadge(null);
    return;
  }

  const prev = state.selectedModel;
  select.innerHTML = state.models.map((m) => `
    <option value="${escapeHtml(m.id)}"${m.id === prev ? ' selected' : ''}>${escapeHtml(m.id)}</option>
  `).join('');

  if (!state.selectedModel && state.models[0]?.id) {
    state.selectedModel = state.models[0].id;
    select.value = state.selectedModel;
    localStorage.setItem(STORAGE_MODEL, state.selectedModel);
  }

  setLoadedModelBadge(state.models.find((m) => m.id === state.selectedModel) || state.models[0]);
}

/* ── Playground (chat) ───────────────────────────────────── */

function renderPlaygroundMessages() {
  const container = $('playground-messages');
  const empty = $('playground-empty');
  if (!container) return;

  container.querySelectorAll('.msg').forEach((el) => el.remove());

  if (!state.messages.length) {
    if (empty) empty.hidden = false;
    return;
  }

  if (empty) empty.hidden = true;

  state.messages.forEach((msg, index) => {
    container.appendChild(buildMessageElement(msg, index));
  });

  scrollMessagesContainer(container, true);
}

function streamingDisplayText(msg) {
  if (!msg) return '';
  if (msg.streaming) return msg.displayedContent ?? '';
  return msg.content || '';
}

function buildMessageElement(msg, index) {
  const article = document.createElement('article');
  article.className = `msg msg--${msg.role}${msg.error ? ' msg--error' : ''}${msg.streaming ? ' msg--streaming' : ''}`;
  article.dataset.msgIndex = String(index);

  const role = document.createElement('span');
  role.className = 'msg__role';
  role.textContent = msg.role;
  article.appendChild(role);

  if (msg.thinking) {
    const think = document.createElement('div');
    think.className = 'msg__thinking';
    const thinkLabel = document.createElement('span');
    thinkLabel.className = 'msg__thinking-label';
    thinkLabel.textContent = 'Reasoning';
    const thinkBody = document.createElement('p');
    thinkBody.className = 'msg__thinking-body';
    thinkBody.textContent = msg.thinking;
    think.append(thinkLabel, thinkBody);
    article.appendChild(think);
  }

  const body = document.createElement('p');
  body.className = 'msg__body';
  if (msg.streaming) {
    const bodyText = document.createElement('span');
    bodyText.className = 'msg__body-text';
    bodyText.textContent = streamingDisplayText(msg);
    body.appendChild(bodyText);
  } else {
    body.textContent = msg.content || '';
  }
  article.appendChild(body);

  if (msg.meta) {
    const meta = document.createElement('span');
    meta.className = 'msg__meta';
    meta.textContent = msg.meta;
    article.appendChild(meta);
  }

  return article;
}

function patchMessage(index, { scroll = true } = {}) {
  const container = $('playground-messages');
  const msg = state.messages[index];
  if (!container || !msg) return;

  const empty = $('playground-empty');
  if (empty) empty.hidden = true;

  let article = container.querySelector(`[data-msg-index="${index}"]`);
  if (!article) {
    article = buildMessageElement(msg, index);
    container.appendChild(article);
  } else {
    article.className = `msg msg--${msg.role}${msg.error ? ' msg--error' : ''}${msg.streaming ? ' msg--streaming' : ''}`;

    let thinkEl = article.querySelector('.msg__thinking');
    if (msg.thinking) {
      if (!thinkEl) {
        thinkEl = document.createElement('div');
        thinkEl.className = 'msg__thinking';
        const thinkLabel = document.createElement('span');
        thinkLabel.className = 'msg__thinking-label';
        thinkLabel.textContent = 'Reasoning';
        const thinkBody = document.createElement('p');
        thinkBody.className = 'msg__thinking-body';
        thinkEl.append(thinkLabel, thinkBody);
        article.insertBefore(thinkEl, article.querySelector('.msg__body'));
      }
      thinkEl.querySelector('.msg__thinking-body').textContent = msg.thinking;
    } else if (thinkEl) {
      thinkEl.remove();
    }

    const bodyEl = article.querySelector('.msg__body');
    if (bodyEl) {
      if (msg.streaming) {
        const textEl = ensureStreamingBodyText(bodyEl);
        textEl.textContent = streamingDisplayText(msg);
      } else {
        bodyEl.textContent = msg.content || '';
      }
    }

    let metaEl = article.querySelector('.msg__meta');
    if (msg.meta) {
      if (!metaEl) {
        metaEl = document.createElement('span');
        metaEl.className = 'msg__meta';
        article.appendChild(metaEl);
      }
      metaEl.textContent = msg.meta;
    } else if (metaEl) {
      metaEl.remove();
    }
  }

  if (scroll) scrollMessagesContainer(container);
}

function scrollMessagesContainer(container, force = false) {
  if (!container) return;
  if (!force && !isMessagesNearBottom(container)) return;
  container.scrollTop = container.scrollHeight;
}

function isMessagesNearBottom(container, threshold = SCROLL_NEAR_BOTTOM_PX) {
  if (!container) return true;
  const distance = container.scrollHeight - container.scrollTop - container.clientHeight;
  return distance <= threshold;
}

function ensureStreamingBodyText(body) {
  if (!body) return null;
  let textEl = body.querySelector('.msg__body-text');
  if (!textEl) {
    const initial = body.textContent;
    body.textContent = '';
    textEl = document.createElement('span');
    textEl.className = 'msg__body-text';
    textEl.textContent = initial === '▍' ? '' : initial;
    body.appendChild(textEl);
  }
  return textEl;
}

function scrollStreamingMessageIfFollowed() {
  const { container } = streamingEls || {};
  scrollMessagesContainer(container);
}

function paintTypewriterDisplay() {
  const msg = streamingAssistantIndex != null ? state.messages[streamingAssistantIndex] : null;
  const { bodyText } = streamingEls || {};
  if (!msg || !bodyText) return;
  bodyText.textContent = msg.displayedContent ?? '';
  scrollStreamingMessageIfFollowed();
}

function flushStreamingThinking() {
  if (streamingAssistantIndex == null || !streamingEls) return;
  const msg = state.messages[streamingAssistantIndex];
  if (!msg) return;

  const { article, body } = streamingEls;

  if (msg.thinking) {
    if (!streamingEls.thinkSection) {
      const thinkEl = document.createElement('div');
      thinkEl.className = 'msg__thinking';
      const thinkLabel = document.createElement('span');
      thinkLabel.className = 'msg__thinking-label';
      thinkLabel.textContent = 'Reasoning';
      const thinkBody = document.createElement('p');
      thinkBody.className = 'msg__thinking-body';
      thinkEl.append(thinkLabel, thinkBody);
      article.insertBefore(thinkEl, body);
      streamingEls.thinkSection = thinkEl;
      streamingEls.thinkBody = thinkBody;
    }
    if (streamingEls.thinkBody) {
      streamingEls.thinkBody.textContent = msg.thinking;
    }
  }
}

function attachStreamingElements(assistantIndex) {
  const container = $('playground-messages');
  const msg = state.messages[assistantIndex];
  if (!container || !msg) return;

  const empty = $('playground-empty');
  if (empty) empty.hidden = true;

  let article = container.querySelector(`[data-msg-index="${assistantIndex}"]`);
  if (!article) {
    article = buildMessageElement(msg, assistantIndex);
    container.appendChild(article);
  }

  const body = article.querySelector('.msg__body');
  const bodyText = ensureStreamingBodyText(body);

  streamingAssistantIndex = assistantIndex;
  const entry = state.messages[assistantIndex];
  if (entry && entry.displayedContent == null) {
    entry.displayedContent = '';
  }

  streamingEls = {
    container,
    article,
    body,
    bodyText,
    thinkSection: article.querySelector('.msg__thinking'),
    thinkBody: article.querySelector('.msg__thinking-body'),
  };
}

function flushStreamingMessage() {
  flushStreamingThinking();
  paintTypewriterDisplay();
}

function detachStreamingElements() {
  streamingAssistantIndex = null;
  streamingEls = null;
}

function createTypewriterPump(assistantIndex) {
  const pump = {
    assistantIndex,
    rafId: null,
    aborted: false,
    finishMode: false,
    finishStart: 0,
    resolveDone: null,
    donePromise: null,
  };
  pump.donePromise = new Promise((resolve) => {
    pump.resolveDone = resolve;
  });
  return pump;
}

function runTypewriterFrame(pump) {
  pump.rafId = null;
  if (pump.aborted) {
    if (pump.finishMode) pump.resolveDone?.();
    return;
  }

  const msg = state.messages[pump.assistantIndex];
  if (!msg) {
    if (pump.finishMode) pump.resolveDone?.();
    return;
  }

  const target = msg.content || '';
  const display = msg.displayedContent ?? '';
  const gap = target.length - display.length;

  if (gap > 0) {
    let reveal = TYPEWRITER_CHARS_PER_FRAME;
    if (pump.finishMode) {
      const elapsed = performance.now() - pump.finishStart;
      const progress = Math.min(1, elapsed / TYPEWRITER_FINISH_MS);
      const targetLen = Math.floor(display.length + gap * progress);
      reveal = Math.max(1, targetLen - display.length);
    }
    msg.displayedContent = target.slice(0, display.length + reveal);
    paintTypewriterDisplay();
  }

  const remaining = (msg.content || '').length - (msg.displayedContent ?? '').length;
  if (remaining > 0) {
    pump.rafId = requestAnimationFrame(() => runTypewriterFrame(pump));
    return;
  }

  if (pump.finishMode) {
    pump.resolveDone?.();
  }
}

function ensureTypewriterRunning(pump) {
  if (!pump || pump.aborted || pump.rafId != null) return;
  pump.rafId = requestAnimationFrame(() => runTypewriterFrame(pump));
}

function stopTypewriterPump(pump) {
  if (!pump) return;
  pump.aborted = true;
  if (pump.rafId != null) {
    cancelAnimationFrame(pump.rafId);
    pump.rafId = null;
  }
  pump.resolveDone?.();
}

function startTypewriter(assistantIndex) {
  const pump = createTypewriterPump(assistantIndex);
  typewriterPump = pump;
  ensureTypewriterRunning(pump);
  return pump;
}

async function finishTypewriter(pump) {
  if (!pump || pump.aborted) return;
  const msg = state.messages[pump.assistantIndex];
  if (!msg) return;

  const gap = (msg.content || '').length - (msg.displayedContent ?? '').length;
  if (gap <= 0) return;

  pump.finishMode = true;
  pump.finishStart = performance.now();
  pump.donePromise = new Promise((resolve) => {
    pump.resolveDone = resolve;
  });
  ensureTypewriterRunning(pump);
  await pump.donePromise;
}

function createStreamPump(assistantIndex) {
  const pump = {
    assistantIndex,
    queue: [],
    rafId: null,
    producerDone: false,
    aborted: false,
    resolveDone: null,
    donePromise: null,
  };
  pump.donePromise = new Promise((resolve) => {
    pump.resolveDone = resolve;
  });
  return pump;
}

function ingestStreamChunk(assistantIndex, chunk) {
  ingestTelemetryChunk(chunk);
  const delta = chunk.message || {};
  applyStreamDelta(assistantIndex, delta.thinking, delta.content);
}

function paintStreamTelemetryDuringPump() {
  paintTelemetryMetrics(state.telemetry);
  if (state.telemetryTab !== 'parsed') return;

  const now = performance.now();
  if (now - parsedTelemetryLastPaint < PARSED_TELEMETRY_THROTTLE_MS) return;
  parsedTelemetryLastPaint = now;

  const parsedPane = $('telemetry-pane-parsed');
  if (parsedPane) {
    parsedPane.textContent = formatJson(buildParsedPayload(state.telemetry));
  }
}

function runStreamPumpFrame(pump) {
  pump.rafId = null;
  if (pump.aborted) {
    pump.resolveDone?.();
    return;
  }

  let drained = false;
  while (pump.queue.length > 0) {
    ingestStreamChunk(pump.assistantIndex, pump.queue.shift());
    drained = true;
  }

  if (drained) {
    flushStreamingThinking();
    paintStreamTelemetryDuringPump();
    ensureTypewriterRunning(typewriterPump);
  }

  const keepPumping = !pump.aborted && (!pump.producerDone || pump.queue.length > 0);
  if (keepPumping) {
    pump.rafId = requestAnimationFrame(() => runStreamPumpFrame(pump));
  } else {
    pump.resolveDone?.();
  }
}

function ensureStreamPumpRunning(pump) {
  if (pump.aborted || pump.rafId != null) return;
  pump.rafId = requestAnimationFrame(() => runStreamPumpFrame(pump));
}

function stopStreamPump(pump) {
  if (!pump) return;
  pump.aborted = true;
  if (pump.rafId != null) {
    cancelAnimationFrame(pump.rafId);
    pump.rafId = null;
  }
  pump.resolveDone?.();
}

async function pumpNdjsonStream(reader, assistantIndex) {
  const pump = createStreamPump(assistantIndex);
  streamPump = pump;
  ensureStreamPumpRunning(pump);

  try {
    await readNdjsonStream(reader, (chunk) => {
      pump.queue.push(chunk);
      ensureStreamPumpRunning(pump);
    });
    pump.producerDone = true;
    ensureStreamPumpRunning(pump);
    await pump.donePromise;
  } finally {
    if (streamPump === pump) streamPump = null;
    stopStreamPump(pump);
  }
}

function getPlaygroundSettings() {
  return {
    temperature: Number($('playground-temperature')?.value) || 0.7,
    maxTokens: Number($('playground-max-tokens')?.value) || 512,
    stream: Boolean($('playground-stream')?.checked),
  };
}

function buildChatRequest(model, messages, settings) {
  return {
    model,
    messages,
    stream: settings.stream,
    options: {
      temperature: settings.temperature,
      num_predict: settings.maxTokens,
    },
    think: false,
  };
}

function hasThinkingMarkers(text) {
  return THINK_OPEN_RE.test(text) || /<think>/i.test(text);
}

function applyStreamDelta(assistantIndex, apiThinking, apiContent) {
  const entry = state.messages[assistantIndex];
  if (apiThinking) entry.thinking = (entry.thinking || '') + apiThinking;
  if (apiContent) entry.rawText = (entry.rawText || '') + apiContent;

  const raw = entry.rawText || '';
  if (entry.thinking) {
    entry.content = stripThinkingFromContent(raw);
    return;
  }

  if (!entry._sawThinkingTag) {
    if (hasThinkingMarkers(raw)) {
      entry._sawThinkingTag = true;
    } else {
      entry.content = raw;
      return;
    }
  }

  const split = splitEmbeddedThinking(raw);
  if (split.thinking) entry.thinking = split.thinking;
  entry.content = split.content || (split.thinking ? '' : raw);
}

function setPlaygroundBusy(busy, statusText = '') {
  const sendBtn = $('playground-send-btn');
  const stopBtn = $('playground-stop-btn');
  const input = $('playground-input');
  const status = $('playground-status');

  if (sendBtn) sendBtn.disabled = busy;
  if (input) input.disabled = busy;
  if (stopBtn) stopBtn.hidden = !busy;
  if (status) status.textContent = statusText;
  setWorkspaceStreaming(busy);
}

async function readNdjsonStream(reader, onChunk) {
  const decoder = new TextDecoder();
  let buffer = '';

  while (true) {
    const { done, value } = await reader.read();
    if (done) break;

    buffer += decoder.decode(value, { stream: true });
    const lines = buffer.split('\n');
    buffer = lines.pop() || '';

    for (const line of lines) {
      const trimmed = line.trim();
      if (!trimmed) continue;
      try {
        onChunk(JSON.parse(trimmed));
      } catch {
        /* skip malformed lines */
      }
    }
  }

  const tail = buffer.trim();
  if (tail) {
    try {
      onChunk(JSON.parse(tail));
    } catch {
      /* skip */
    }
  }
}

async function sendPlaygroundMessage(text) {
  const model = state.selectedModel || state.models[0]?.id;
  if (!model) {
    state.messages.push({
      role: 'system',
      content: 'No model available. Pull a model into Ollama first.',
      error: true,
    });
    renderPlaygroundMessages();
    return;
  }

  state.messages.push({ role: 'user', content: text });
  const assistantIndex = state.messages.length;
  state.messages.push({
    role: 'assistant',
    content: '',
    thinking: '',
    rawText: '',
    meta: 'Generating…',
    streaming: false,
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
      state.messages[assistantIndex].streaming = true;
      state.messages[assistantIndex].displayedContent = '';
      state.messages[assistantIndex].meta = '';
      attachStreamingElements(assistantIndex);
      const twPump = startTypewriter(assistantIndex);
      flushStreamingMessage();

      const reader = res.body.getReader();
      await pumpNdjsonStream(reader, assistantIndex);

      applyStreamDelta(assistantIndex, '', '');
      await finishTypewriter(twPump);
      const elapsed = performance.now() - wallStart;
      state.messages[assistantIndex].meta = formatDurationSeconds(elapsed);
    } else {
      const body = await res.json();
      ingestTelemetryChunk(body);
      const delta = body.message || {};
      state.messages[assistantIndex].thinking = delta.thinking || '';
      state.messages[assistantIndex].rawText = delta.content || '';
      applyStreamDelta(assistantIndex, '', '');
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
    stopTypewriterPump(typewriterPump);
    typewriterPump = null;
    detachStreamingElements();
    if (state.messages[assistantIndex]) {
      const finalMsg = state.messages[assistantIndex];
      finalMsg.displayedContent = finalMsg.content;
      finalMsg.streaming = false;
    }
    state.abortController = null;
    setPlaygroundBusy(false, '');
    patchMessage(assistantIndex);
    paintTelemetry();
    refreshRuntime().catch(() => {});
  }
}

function stopPlayground() {
  stopStreamPump(streamPump);
  if (typewriterPump && streamingAssistantIndex != null) {
    const msg = state.messages[streamingAssistantIndex];
    if (msg) {
      msg.displayedContent = msg.content || msg.displayedContent || '';
      paintTypewriterDisplay();
    }
  }
  stopTypewriterPump(typewriterPump);
  typewriterPump = null;
  state.abortController?.abort();
}

function clearPlayground() {
  state.messages = [];
  renderPlaygroundMessages();
}

/* ── Telemetry (raw input) ───────────────────────────────── */

function beginTelemetry(request, model) {
  parsedTelemetryLastPaint = 0;
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

  const msg = chunk.message || {};
  if (msg.thinking) {
    state.telemetry.thinking += msg.thinking;
    const elapsed = performance.now() - state.telemetry.timing.startedAt;
    if (state.telemetry.timing.firstThinkingMs == null) {
      state.telemetry.timing.firstThinkingMs = elapsed;
    }
  }
  if (msg.content) {
    state.telemetry.content += msg.content;
    const elapsed = performance.now() - state.telemetry.timing.startedAt;
    if (state.telemetry.timing.firstContentMs == null) {
      state.telemetry.timing.firstContentMs = elapsed;
    }
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

function formatMetricsBar(data) {
  if (!data) return 'Awaiting inference…';

  const parts = [
    data.timing?.totalMs != null ? `${data.timing.totalMs.toFixed(0)} ms total` : null,
    data.timing?.firstContentMs != null ? `first content ${data.timing.firstContentMs.toFixed(0)} ms` : null,
    data.usage?.eval_count != null ? `${data.usage.eval_count} completion tokens` : null,
    data.usage?.prompt_eval_count != null ? `${data.usage.prompt_eval_count} prompt tokens` : null,
    data.model || null,
    data.error ? `error: ${data.error}` : null,
  ].filter(Boolean);

  return parts.length ? parts.join(' · ') : 'Running…';
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

function paintTelemetryMetrics(data) {
  const metrics = $('telemetry-metrics');
  if (metrics) metrics.textContent = formatMetricsBar(data);
}

function paintTelemetry() {
  const data = state.telemetry;
  const metrics = $('telemetry-metrics');
  const parsedPane = $('telemetry-pane-parsed');
  const requestPane = $('telemetry-pane-request');

  if (!data) {
    if (metrics) metrics.textContent = 'Awaiting inference…';
    if (parsedPane) parsedPane.textContent = '—';
    if (requestPane) requestPane.textContent = '—';
    return;
  }

  if (metrics) metrics.textContent = formatMetricsBar(data);
  if (requestPane) requestPane.textContent = formatJson(data.request);
  if (parsedPane) parsedPane.textContent = formatJson(buildParsedPayload(data));
}

function setTelemetryTab(tab) {
  state.telemetryTab = tab;
  document.querySelectorAll('[data-telemetry-tab]').forEach((btn) => {
    const active = btn.dataset.telemetryTab === tab;
    btn.classList.toggle('telemetry-tab--active', active);
    btn.setAttribute('aria-selected', active ? 'true' : 'false');
  });

  const panes = { parsed: $('telemetry-pane-parsed'), request: $('telemetry-pane-request') };
  for (const [name, el] of Object.entries(panes)) {
    if (!el) continue;
    const active = name === tab;
    el.hidden = !active;
    el.classList.toggle('telemetry-pane--active', active);
  }

  if (tab === 'parsed' && state.telemetry && streamPump && !streamPump.aborted) {
    const parsedPane = $('telemetry-pane-parsed');
    if (parsedPane) {
      parsedPane.textContent = formatJson(buildParsedPayload(state.telemetry));
      parsedTelemetryLastPaint = performance.now();
    }
  }
}

/* ── Runtime ─────────────────────────────────────────────── */

function renderRuntime() {
  const rt = state.runtime;
  const processorEl = $('runtime-processor');
  const hintEl = $('runtime-gpu-hint');
  const statusBox = $('runtime-status');
  const toggle = $('runtime-gpu-toggle');
  const applyBtn = $('runtime-gpu-apply');
  const note = $('runtime-note');

  if (!rt) {
    if (processorEl) processorEl.textContent = '—';
    if (hintEl) hintEl.textContent = 'Loading runtime…';
    return;
  }

  const processor = rt.processor || (rt.ollama_online ? 'idle (no model loaded)' : 'Ollama offline');
  if (processorEl) processorEl.textContent = processor;
  if (statusBox) statusBox.dataset.processor = processor;

  const gpuHint = rt.gpu_available
    ? (rt.gpu_enabled ? 'GPU mode enabled in compose' : 'CPU-only compose profile')
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
      note.textContent = 'nvidia-smi works on the host but Docker cannot access the GPU yet. Install NVIDIA Container Toolkit, then retry.';
    } else if (dirty) {
      note.classList.add('runtime-note--warn');
      note.textContent = 'Applying will stop and restart the Ollama container. In-flight generation will be cancelled.';
    } else {
      note.textContent = 'Requires nvidia-container-toolkit on the host. Toggling stops and restarts the Ollama container (~10–30 s).';
    }
  }
}

async function refreshRuntime() {
  try {
    const res = await consoleFetch('/api/runtime');
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    state.runtime = await res.json();
    if (state.runtimeGpuPending == null) {
      state.runtimeGpuPending = state.runtime.gpu_enabled;
    }
    renderRuntime();
    return state.runtime;
  } catch (err) {
    if ($('runtime-gpu-hint')) $('runtime-gpu-hint').textContent = String(err.message || err);
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
    applyBtn.textContent = 'Restarting Ollama…';
  }
  if ($('runtime-note')) {
    $('runtime-note').textContent = 'Restarting Ollama — this may take up to 30 seconds…';
  }

  try {
    const res = await consoleFetch('/api/runtime/gpu', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ enabled }),
    });
    const body = await res.json();
    state.runtime = body;
    state.runtimeGpuPending = body.gpu_enabled;
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

/* ── Model probe ─────────────────────────────────────────── */

async function probeModels({ manual = false } = {}) {
  if (manual) setConnectionState(null, 'Probing…');

  try {
    const { res, latencyMs } = await runnerFetch('/v1/models');
    const contentType = res.headers.get('content-type') || '';
    const body = contentType.includes('application/json') ? await res.json() : await res.text();

    state.lastProbe = {
      ok: res.ok,
      status: res.status,
      latencyMs,
      body,
      at: new Date().toISOString(),
    };

    if (res.ok && body && Array.isArray(body.data)) {
      state.models = body.data.filter((m) => m && m.id);
      setConnectionState(true, `Runner online · ${latencyMs.toFixed(0)} ms`);
    } else if (res.ok) {
      state.models = [];
      setConnectionState(true, 'Runner online · empty model list');
    } else {
      state.models = [];
      setConnectionState(false, `HTTP ${res.status}`);
    }

    renderOverview();
    syncModelSelect();
    renderGatewayDiscovery();
    $('last-refresh').textContent = `Updated ${relativeTime(state.lastProbe.at)}`;
    return state.lastProbe;
  } catch (err) {
    state.models = [];
    state.lastProbe = { ok: false, error: String(err), at: new Date().toISOString() };
    setConnectionState(false, 'Unreachable');
    renderOverview();
    syncModelSelect();
    renderGatewayDiscovery();
    $('last-refresh').textContent = `Failed ${relativeTime(state.lastProbe.at)}`;
    if (manual) throw err;
    return state.lastProbe;
  }
}

/* ── API explorer ────────────────────────────────────────── */

async function runExplorerEndpoint(endpoint) {
  const paths = {
    models: { path: '/v1/models', resultId: 'explorer-models-result' },
    tags: { path: '/api/tags', resultId: 'explorer-tags-result' },
    version: { path: '/api/version', resultId: 'explorer-version-result' },
  };
  const spec = paths[endpoint];
  if (!spec) return;

  const el = $(spec.resultId);
  if (el) el.textContent = 'Loading…';

  try {
    const { res, latencyMs } = await runnerFetch(spec.path);
    const contentType = res.headers.get('content-type') || '';
    const body = contentType.includes('application/json') ? await res.json() : await res.text();
    if (el) {
      el.textContent = truncate(
        `HTTP ${res.status} · ${latencyMs.toFixed(1)} ms\n\n${formatJson(body)}`,
        4000,
      );
    }
  } catch (err) {
    if (el) el.textContent = String(err);
  }
}

/* ── Preferences & events ────────────────────────────────── */

function applyBaseUrl() {
  const input = $('runner-base-url');
  const url = (input?.value || DEFAULT_BASE_URL).trim().replace(/\/$/, '');
  state.baseUrl = url;
  localStorage.setItem(STORAGE_BASE_URL, url);
  if (input) input.value = url;
  probeModels({ manual: true }).catch(() => {});
}

function startPolling() {
  if (state.pollTimer) clearInterval(state.pollTimer);
  state.pollTimer = setInterval(() => {
    if (state.abortController) return;
    probeModels().catch(() => {});
    refreshRuntime().catch(() => {});
  }, state.pollIntervalS * 1000);
}

function bindEvents() {
  $('save-base-url-btn')?.addEventListener('click', applyBaseUrl);
  $('runner-base-url')?.addEventListener('keydown', (e) => {
    if (e.key === 'Enter') applyBaseUrl();
  });

  $('probe-btn')?.addEventListener('click', () => probeModels({ manual: true }));
  $('refresh-btn')?.addEventListener('click', () => {
    probeModels({ manual: true });
    refreshRuntime();
  });

  $('poll-interval')?.addEventListener('change', (e) => {
    const s = Math.min(120, Math.max(3, Number(e.target.value) || DEFAULT_POLL_S));
    state.pollIntervalS = s;
    e.target.value = String(s);
    localStorage.setItem(STORAGE_POLL_INTERVAL, String(s));
    startPolling();
  });

  $('playground-model')?.addEventListener('change', (e) => {
    state.selectedModel = e.target.value;
    localStorage.setItem(STORAGE_MODEL, state.selectedModel);
    const model = state.models.find((m) => m.id === state.selectedModel);
    setLoadedModelBadge(model || null);
  });

  $('playground-form')?.addEventListener('submit', (e) => {
    e.preventDefault();
    const input = $('playground-input');
    const text = (input?.value || '').trim();
    if (!text) return;
    if (input) input.value = '';
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

  $('runtime-gpu-toggle')?.addEventListener('change', (e) => {
    state.runtimeGpuPending = Boolean(e.target.checked);
    renderRuntime();
  });

  $('runtime-gpu-apply')?.addEventListener('click', () => applyGpuRuntime());

  document.querySelectorAll('[data-telemetry-tab]').forEach((btn) => {
    btn.addEventListener('click', () => setTelemetryTab(btn.dataset.telemetryTab || 'parsed'));
  });

  document.querySelectorAll('[data-endpoint]').forEach((btn) => {
    btn.addEventListener('click', () => runExplorerEndpoint(btn.dataset.endpoint));
  });

  $('gateway-runner-id')?.addEventListener('change', saveGatewayConfigFromInputs);
  $('gateway-declared-caps')?.addEventListener('change', saveGatewayConfigFromInputs);
  $('gateway-jwt-input')?.addEventListener('change', saveGatewayConfigFromInputs);
  $('gateway-fetch-btn')?.addEventListener('click', () => {
    saveGatewayConfigFromInputs();
    fetchGatewayCapabilities({ manual: true });
  });
  $('gateway-auto-sign-in-btn')?.addEventListener('click', () => gatewayAutoSignIn());
}

function loadPreferences() {
  const savedUrl = localStorage.getItem(STORAGE_BASE_URL);
  if (savedUrl) {
    state.baseUrl = savedUrl === 'http://127.0.0.1:11434' ? DEFAULT_BASE_URL : savedUrl;
    const input = $('runner-base-url');
    if (input) input.value = state.baseUrl;
  }

  const savedPoll = Number(localStorage.getItem(STORAGE_POLL_INTERVAL));
  if (savedPoll >= 3 && savedPoll <= 120) {
    state.pollIntervalS = savedPoll;
    const pollInput = $('poll-interval');
    if (pollInput) pollInput.value = String(savedPoll);
  }

  const savedModel = localStorage.getItem(STORAGE_MODEL);
  if (savedModel) state.selectedModel = savedModel;

  const savedRunnerId = localStorage.getItem(STORAGE_RUNNER_ID);
  if (savedRunnerId) state.gatewayRunnerId = savedRunnerId;

  const savedCaps = localStorage.getItem(STORAGE_DECLARED_CAPS);
  if (savedCaps) {
    state.declaredCapabilities = savedCaps.split(',').map((c) => c.trim()).filter(Boolean);
  }

  const savedJwt = localStorage.getItem(STORAGE_GATEWAY_JWT);
  if (savedJwt) state.gatewayJwt = savedJwt;

  const runnerIdInput = $('gateway-runner-id');
  if (runnerIdInput) runnerIdInput.value = state.gatewayRunnerId;
  const capsInput = $('gateway-declared-caps');
  if (capsInput) capsInput.value = state.declaredCapabilities.join(', ');
  const jwtInput = $('gateway-jwt-input');
  if (jwtInput) jwtInput.value = state.gatewayJwt;
}

async function init() {
  loadPreferences();
  bindEvents();
  setTelemetryTab(state.telemetryTab);
  renderGatewayDiscovery();
  await Promise.all([probeModels(), refreshRuntime()]);
  startPolling();
}

init();
