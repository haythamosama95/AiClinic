/**
 * ABO console HTML shell (R2-P4, 01 §3.8 D-2).
 *
 * `GET /ops` exactly — after host validation and Access JWT verification,
 * and before the contract-version check, because a browser's first
 * navigation cannot send `Abo-Contract-Version`. The script is bundled in
 * the ABO Worker source; there is no asset binding. `GET /ops/` and every
 * other `/ops/*` path keep the version and authentication rules unchanged.
 *
 * The shell reads the versioned `GET /ops/ceremony-context` endpoint, which
 * returns the verified Access email, the RP id and origin, the accepted
 * console version and each active `{credential_id, alg}` (no key material).
 */

import { CHANNEL_VERSIONS } from "vendor-contracts";
import { verifyOpsAccess } from "../index.js";
import type { OpsEnv } from "../index.js";
import { LOCAL_HP_ACTIONS } from "./ceremony.js";

/**
 * The exact console shell route. The caller (worker fetch) invokes this only
 * for `GET /ops` on `OPS_HOST`, after host validation. Access verification
 * happens here; a missing or invalid Access JWT answers the standard
 * `unauthenticated` JSON — the shell never bypasses the ops auth rules.
 */
export async function handleOpsShell(
  request: Request,
  env: OpsEnv,
): Promise<Response> {
  const access = await verifyOpsAccess(env, request);
  if (access instanceof Response) {
    return access;
  }
  return new Response(opsShellHtml(), {
    status: 200,
    headers: {
      "content-type": "text/html; charset=utf-8",
      "cache-control": "no-store",
    },
  });
}

/** The client ceremony script, source-bundled (served inline on every load). */
function consoleScriptSource(actionDescriptors: string): string {
  // Keep this plain ES2017 JavaScript without template literals, so it can
  // be embedded verbatim inside the TS template literal below.
  return `
(function () {
  "use strict";

  var CONSOLE_VERSION = ${String(CHANNEL_VERSIONS.aboConsole)};
  var ACTIONS = ${actionDescriptors};
  var CONTEXT_PATH = "/ops/ceremony-context";
  var REGISTRATION_PATH = "/ops/operator-credentials";
  var context = null;
  var reloadRequired = false;

  function byId(id) {
    return document.getElementById(id);
  }

  function base64UrlFromBytes(bytes) {
    var binary = "";
    for (var i = 0; i < bytes.length; i = i + 1) {
      binary = binary + String.fromCharCode(bytes[i]);
    }
    return btoa(binary).replace(/\\+/g, "-").replace(/\\//g, "_").replace(/=+$/u, "");
  }

  function bytesFromBase64Url(segment) {
    var base64 = segment.replace(/-/g, "+").replace(/_/g, "/");
    while (base64.length % 4 !== 0) {
      base64 = base64 + "=";
    }
    var binary = atob(base64);
    var bytes = new Uint8Array(binary.length);
    for (var i = 0; i < binary.length; i = i + 1) {
      bytes[i] = binary.charCodeAt(i);
    }
    return bytes;
  }

  function bytesEqual(a, b) {
    if (a.length !== b.length) {
      return false;
    }
    for (var i = 0; i < a.length; i = i + 1) {
      if (a[i] !== b[i]) {
        return false;
      }
    }
    return true;
  }

  // RFC 8785 canonical JSON for the console's value domain
  // (objects, arrays, strings, integers, booleans, null), the same
  // serialization vendor-contracts' canonicalize performs server-side.
  function canonicalJson(value) {
    if (value === null) {
      return "null";
    }
    if (typeof value === "boolean") {
      return value ? "true" : "false";
    }
    if (typeof value === "number") {
      if (!isFinite(value)) {
        throw new Error("Invalid JSON number");
      }
      if (value === 0) {
        return "0";
      }
      return String(value);
    }
    if (typeof value === "string") {
      return JSON.stringify(value);
    }
    if (Array.isArray(value)) {
      var items = [];
      for (var i = 0; i < value.length; i = i + 1) {
        items.push(canonicalJson(value[i]));
      }
      return "[" + items.join(",") + "]";
    }
    if (typeof value === "object") {
      var keys = Object.keys(value).sort(function (a, b) {
        if (a < b) { return -1; }
        if (a > b) { return 1; }
        return 0;
      });
      var members = [];
      for (var j = 0; j < keys.length; j = j + 1) {
        members.push(JSON.stringify(keys[j]) + ":" + canonicalJson(value[keys[j]]));
      }
      return "{" + members.join(",") + "}";
    }
    throw new Error("Invalid JSON value");
  }

  function setParamPath(params, path, value) {
    var segments = path.split(".");
    var cursor = params;
    for (var i = 0; i < segments.length - 1; i = i + 1) {
      var segment = segments[i];
      if (typeof cursor[segment] !== "object" || cursor[segment] === null || Array.isArray(cursor[segment])) {
        cursor[segment] = {};
      }
      cursor = cursor[segment];
    }
    cursor[segments[segments.length - 1]] = value;
  }

  function paramsFromValues(fields, values) {
    var params = {};
    for (var i = 0; i < fields.length; i = i + 1) {
      var field = fields[i];
      var raw = values[field.name] || "";
      var text = raw.trim();
      if (text.length === 0) {
        return null;
      }
      if (field.kind === "integer") {
        var parsed = Number(text);
        if (!isFinite(parsed) || Math.floor(parsed) !== parsed || parsed <= 0) {
          return null;
        }
        setParamPath(params, field.paramPath, parsed);
      } else {
        setParamPath(params, field.paramPath, text);
      }
    }
    return params;
  }

  function showStatus(message, isError) {
    var status = byId("status");
    if (status) {
      status.textContent = message;
      status.className = isError ? "error" : "ok";
    }
  }

  function markReloadRequired() {
    reloadRequired = true;
    var banner = byId("reload");
    if (banner) {
      banner.hidden = false;
    }
    var container = byId("action-forms");
    if (container) {
      container.hidden = true;
    }
    var bootstrap = byId("bootstrap");
    if (bootstrap) {
      bootstrap.hidden = true;
    }
  }

  function parseResponse(response) {
    return response.json().then(function (body) {
      return { status: response.status, body: body };
    }).catch(function () {
      return { status: response.status, body: null };
    });
  }

  // A 400 refusal carries {code, message, contract_version, accepted_versions,
  // reload}. The console asks for a reload and never silently retries.
  function handleRefusal(outcome) {
    var body = outcome.body;
    if (
      outcome.status === 400 &&
      body !== null &&
      typeof body === "object" &&
      (body.reload === true || body.code === "contract_version_unsupported")
    ) {
      markReloadRequired();
      showStatus("This console is outdated. Reload the page before running another ceremony.", true);
      return true;
    }
    return false;
  }

  function jsonHeaders() {
    return {
      "Abo-Contract-Version": String(CONSOLE_VERSION),
      "content-type": "application/json"
    };
  }

  function renderActionForms() {
    var container = byId("action-forms");
    if (!container) {
      return;
    }
    ACTIONS.forEach(function (action) {
      var form = document.createElement("form");
      form.dataset.action = action.action;
      var heading = document.createElement("h3");
      heading.textContent = action.action;
      form.appendChild(heading);
      action.fields.forEach(function (field) {
        var label = document.createElement("label");
        label.textContent = field.label + ": ";
        var input;
        if (field.kind === "text") {
          input = document.createElement("textarea");
          input.rows = 8;
        } else {
          input = document.createElement("input");
          input.type = field.kind === "integer" ? "number" : "text";
        }
        input.name = field.name;
        input.required = true;
        label.appendChild(input);
        form.appendChild(label);
      });
      var submit = document.createElement("button");
      submit.type = "submit";
      submit.textContent = "Approve with passkey";
      form.appendChild(submit);
      form.addEventListener("submit", function (event) {
        event.preventDefault();
        var values = {};
        action.fields.forEach(function (field) {
          values[field.name] = form.elements[field.name].value;
        });
        runLocalCeremony(action, values);
      });
      container.appendChild(form);
    });
  }

  function renderBootstrap() {
    var section = byId("bootstrap");
    if (!section) {
      return;
    }
    if (context.credentials.length === 0) {
      section.hidden = false;
    } else {
      section.hidden = true;
    }
  }

  function loadContext() {
    return fetch(CONTEXT_PATH, { headers: jsonHeaders() }).then(function (response) {
      return parseResponse(response).then(function (outcome) {
        if (outcome.status === 401) {
          showStatus("Access session missing or expired. Reload behind Cloudflare Access.", true);
          return;
        }
        if (handleRefusal(outcome)) {
          return;
        }
        if (outcome.status !== 200 || outcome.body === null ||
            typeof outcome.body !== "object" || !Array.isArray(outcome.body.credentials)) {
          showStatus("Unable to load the ceremony context.", true);
          return;
        }
        context = outcome.body;
        var actor = byId("actor");
        if (actor) {
          actor.textContent = String(outcome.body.actor_email);
        }
        renderActionForms();
        renderBootstrap();
        showStatus("Console ready. " + context.credentials.length + " active credential(s).", false);
      });
    }).catch(function () {
      showStatus("Unable to load the ceremony context.", true);
    });
  }

  function runLocalCeremony(action, values) {
    if (reloadRequired || context === null) {
      showStatus("Reload the console before running a ceremony.", true);
      return;
    }
    var subject = String(values.subject || "").trim();
    if (subject.length === 0) {
      showStatus("Missing " + action.subjectKey + ".", true);
      return;
    }
    var params = paramsFromValues(action.fields, values);
    if (params === null) {
      showStatus("Invalid form values; no ceremony was started.", true);
      return;
    }
    // The operation is built once and preserved unchanged through submission.
    var operation = {
      op: action.action,
      params: params,
      actor_email: context.actor_email,
      issued_at: new Date().toISOString(),
      nonce: crypto.randomUUID(),
      contract_version: context.contract_version
    };
    var encoder = new TextEncoder();
    var canonicalBytes = encoder.encode(canonicalJson(operation));
    crypto.subtle.digest("SHA-256", canonicalBytes).then(function (digest) {
      var publicKey = {
        challenge: new Uint8Array(digest),
        rpId: context.rp_id,
        userVerification: "required",
        allowCredentials: context.credentials.map(function (credential) {
          return {
            id: bytesFromBase64Url(credential.credential_id),
            type: "public-key"
          };
        })
      };
      return navigator.credentials.get({ publicKey: publicKey });
    }).then(function (credential) {
      if (!credential || !credential.response) {
        throw new Error("No credential returned");
      }
      var rawId = new Uint8Array(credential.rawId);
      var matched = null;
      context.credentials.forEach(function (candidate) {
        if (bytesEqual(bytesFromBase64Url(candidate.credential_id), rawId)) {
          matched = candidate;
        }
      });
      if (matched === null) {
        // A credential outside the active registry can never be submitted.
        showStatus("The touched credential is not active. Nothing was submitted.", true);
        return;
      }
      var authentication = credential.response;
      var assertion = {
        alg: matched.alg,
        authenticator_data: base64UrlFromBytes(new Uint8Array(authentication.authenticatorData)),
        client_data_json: base64UrlFromBytes(new Uint8Array(authentication.clientDataJSON)),
        signature: base64UrlFromBytes(new Uint8Array(authentication.signature))
      };
      return fetch(action.route.replace("{subject}", encodeURIComponent(subject)), {
        method: "POST",
        headers: jsonHeaders(),
        body: JSON.stringify({ operation: operation, assertion: assertion })
      }).then(function (response) {
        return parseResponse(response);
      }).then(function (outcome) {
        if (handleRefusal(outcome)) {
          return;
        }
        var body = outcome.body;
        var code = "";
        if (body !== null && typeof body === "object" && typeof body.code === "string") {
          code = body.code;
        }
        if (outcome.status === 200) {
          var actionId = "";
          if (body !== null && typeof body === "object" && typeof body.action_id === "string") {
            actionId = body.action_id;
          }
          showStatus(action.action + " accepted. Action id: " + actionId, false);
        } else {
          showStatus(action.action + " refused" + (code.length > 0 ? " (" + code + ")" : "") + ".", true);
        }
      });
    }).catch(function (error) {
      // Cancelled prompt, refused user verification or transport failure:
      // nothing was submitted and nothing is retried automatically.
      showStatus("Ceremony cancelled or failed. Nothing was submitted.", true);
      if (console && console.debug) {
        console.debug(error);
      }
    });
  }

  // --- Minimal CBOR decoder for the WebAuthn registration attestation ---
  function cborReadHead(bytes, offset) {
    var first = bytes[offset];
    var major = first >> 5;
    var info = first & 31;
    var additional = info;
    var length = 0;
    if (info < 24) {
      additional = info;
      length = 0;
    } else if (info === 24) {
      additional = bytes[offset + 1];
      length = 1;
    } else if (info === 25) {
      additional = (bytes[offset + 1] << 8) | bytes[offset + 2];
      length = 2;
    } else if (info === 26) {
      additional = (bytes[offset + 1] << 24) | (bytes[offset + 2] << 16) |
        (bytes[offset + 3] << 8) | bytes[offset + 4];
      length = 4;
    } else if (info === 27) {
      // WebAuthn attestation objects never need > 2^32-byte items.
      additional = ((bytes[offset + 1] * 0x1000000) + (bytes[offset + 2] << 16) +
        (bytes[offset + 3] << 8) + bytes[offset + 4]) * 0x100000000 +
        ((bytes[offset + 5] * 0x1000000) + (bytes[offset + 6] << 16) +
        (bytes[offset + 7] << 8) + bytes[offset + 8]);
      length = 8;
    } else {
      return null;
    }
    return { major: major, value: additional, headLength: 1 + length };
  }

  function cborReadItem(bytes, offset) {
    var head = cborReadHead(bytes, offset);
    if (head === null) {
      return null;
    }
    var start = offset + head.headLength;
    if (head.major === 0) {
      return { type: "uint", value: head.value, end: start };
    }
    if (head.major === 1) {
      return { type: "uint", value: -1 - head.value, end: start };
    }
    if (head.major === 2) {
      return {
        type: "bytes",
        bytes: bytes.subarray(start, start + head.value),
        end: start + head.value
      };
    }
    if (head.major === 3) {
      return {
        type: "text",
        value: new TextDecoder("utf-8").decode(bytes.subarray(start, start + head.value)),
        end: start + head.value
      };
    }
    if (head.major === 4) {
      var array = [];
      var cursor = start;
      for (var i = 0; i < head.value; i = i + 1) {
        var item = cborReadItem(bytes, cursor);
        if (item === null) {
          return null;
        }
        array.push(item);
        cursor = item.end;
      }
      return { type: "array", value: array, end: cursor };
    }
    if (head.major === 5) {
      var map = {};
      var key = null;
      var cursor2 = start;
      for (var j = 0; j < head.value; j = j + 1) {
        var keyItem = cborReadItem(bytes, cursor2);
        if (keyItem === null) {
          return null;
        }
        var valueItem = cborReadItem(bytes, keyItem.end);
        if (valueItem === null) {
          return null;
        }
        map[String(keyItem.value)] = valueItem;
        cursor2 = valueItem.end;
      }
      return { type: "map", value: map, end: cursor2 };
    }
    return null;
  }
  // --- End of the CBOR decoder ---

  // Convert a navigator.credentials.create response into the platform
  // attestation form: {alg: "ES256"|"EdDSA", public_key: base64url}, where
  // ES256 is SPKI DER and EdDSA is the raw 32-byte key.
  function attestationFromCreateResponse(attestationObject) {
    var root = null;
    var item = cborReadItem(attestationObject, 0);
    if (item !== null && item.type === "map") {
      root = item.value;
    }
    if (root === null || root["fmt"] === undefined || root["authData"] === undefined) {
      return null;
    }
    var authData = root["authData"].bytes;
    if (authData.length < 37) {
      return null;
    }
    var flags = authData[32];
    if ((flags & 0x40) === 0) {
      return null;
    }
    var credentialIdLength = (authData[53] << 8) | authData[54];
    var coseOffset = 55 + credentialIdLength;
    if (coseOffset >= authData.length) {
      return null;
    }
    var coseItem = cborReadItem(authData, coseOffset);
    if (coseItem === null || coseItem.type !== "map") {
      return null;
    }
    var coseMap = coseItem.value;
    var kty = coseMap["1"] ? coseMap["1"].value : null;
    var coseAlg = coseMap["3"] ? coseMap["3"].value : null;
    if (coseAlg === -7) {
      var x = coseMap["-2"] ? coseMap["-2"].bytes : null;
      var y = coseMap["-3"] ? coseMap["-3"].bytes : null;
      if (x === null || y === null || x.length !== 32 || y.length !== 32) {
        return null;
      }
      // P-256 SPKI: fixed 26-byte header, then the 0x04-prefixed
      // uncompressed point (SEC1). crypto.subtle keys import this form.
      var spki = new Uint8Array(91);
      spki.set([0x30, 0x59, 0x30, 0x13, 0x06, 0x07, 0x2a, 0x86, 0x48, 0xce,
        0x3d, 0x02, 0x01, 0x06, 0x08, 0x2a, 0x86, 0x48, 0xce, 0x3d,
        0x03, 0x01, 0x07, 0x03, 0x42, 0x00], 0);
      spki[26] = 0x04;
      spki.set(x, 27);
      spki.set(y, 59);
      return { alg: "ES256", public_key: base64UrlFromBytes(spki) };
    }
    if (coseAlg === -8) {
      var rawX = coseMap["-2"] ? coseMap["-2"].bytes : null;
      if (rawX === null || rawX.length !== 32) {
        return null;
      }
      return { alg: "EdDSA", public_key: base64UrlFromBytes(rawX) };
    }
    return null;
  }

  function runBootstrap() {
    if (reloadRequired || context === null) {
      showStatus("Reload the console before running a ceremony.", true);
      return;
    }
    var challenge = new Uint8Array(32);
    crypto.getRandomValues(challenge);
    var userHandle = new Uint8Array(32);
    crypto.getRandomValues(userHandle);
    var createPromise;
    try {
      createPromise = navigator.credentials.create({
        publicKey: {
          challenge: challenge,
          rp: { name: "ABO operator console", id: context.rp_id },
          user: {
            id: userHandle,
            name: context.actor_email,
            displayName: context.actor_email
          },
          pubKeyCredParams: [
            { type: "public-key", alg: -7 },
            { type: "public-key", alg: -8 }
          ],
          timeout: 120000,
          attestation: "none"
        }
      });
    } catch (error) {
      showStatus("Credential creation unavailable. Nothing was submitted.", true);
      return;
    }
    createPromise.then(function (created) {
      if (!created || !created.response) {
        throw new Error("No credential returned");
      }
      // The exact attestation form consumed by the existing registration
      // relay and the platform's registration parser.
      var attestation = attestationFromCreateResponse(
        new Uint8Array(created.response.attestationObject)
      );
      if (attestation === null) {
        showStatus("Unreadable attestation. Nothing was submitted.", true);
        return;
      }
      return fetch(REGISTRATION_PATH, {
        method: "POST",
        headers: jsonHeaders(),
        body: JSON.stringify({
          action_id: crypto.randomUUID(),
          credential_id: base64UrlFromBytes(new Uint8Array(created.rawId)),
          attestation: attestation
        })
      }).then(function (response) {
        return parseResponse(response);
      }).then(function (outcome) {
        if (handleRefusal(outcome)) {
          return;
        }
        var body = outcome.body;
        var code = "";
        if (body !== null && typeof body === "object" && typeof body.code === "string") {
          code = body.code;
        }
        if (outcome.status === 200 && body !== null && body.result === "ok") {
          showStatus("First operator credential registered. It activates 24 hours from now; an alert confirms the bootstrap.", false);
          var section = byId("bootstrap");
          if (section) {
            section.hidden = true;
          }
        } else if (code === "assertion_required" || code === "approval_required") {
          showStatus("Bootstrap is closed: the registry already holds a credential; an existing credential must approve this registration.", true);
        } else {
          showStatus("Registration refused" + (code.length > 0 ? " (" + code + ")" : "") + ".", true);
        }
      });
    }).catch(function (error) {
      showStatus("Credential creation cancelled or failed. Nothing was submitted.", true);
      if (console && console.debug) {
        console.debug(error);
      }
    });
  }

  document.addEventListener("DOMContentLoaded", function () {
    var bootstrapButton = byId("bootstrap-run");
    if (bootstrapButton) {
      bootstrapButton.addEventListener("click", runBootstrap);
    }
    loadContext();
  });
})();
`;
}

/** The console shell HTML document (D-2: the one exact shell path). */
export function opsShellHtml(): string {
  const descriptors = JSON.stringify(
    LOCAL_HP_ACTIONS.map((descriptor) => ({
      action: descriptor.action,
      route: descriptor.routeTemplate,
      subjectKey: descriptor.subjectKey,
      fields: descriptor.fields.map((field) => ({
        name: field.name,
        kind: field.kind,
        label: field.label,
        paramPath: field.paramPath,
      })),
    })),
  );
  return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>ABO operator console</title>
<style>
body { font-family: system-ui, sans-serif; margin: 2rem auto; max-width: 46rem; padding: 0 1rem; color: #1a2333; }
h1 { font-size: 1.4rem; }
h2, h3 { font-size: 1.05rem; margin-bottom: 0.4rem; }
form { border: 1px solid #d5dbe5; border-radius: 6px; padding: 0.8rem; margin: 0 0 1rem; }
label { display: block; margin: 0.4rem 0; }
input, textarea { display: block; width: 100%; box-sizing: border-box; margin-top: 0.2rem; }
button { margin-top: 0.6rem; }
#status { margin-top: 1rem; font-weight: 600; }
#status.error { color: #a31300; }
#status.ok { color: #0f6413; }
#reload { border: 1px solid #a31300; padding: 0.6rem; border-radius: 6px; background: #fdeceb; }
#bootstrap { border: 1px solid #d5dbe5; border-radius: 6px; padding: 0.8rem; margin: 0 0 1rem; }
hr { border: 0; border-top: 1px solid #d5dbe5; margin: 1.2rem 0; }
</style>
</head>
<body>
<h1>ABO operator console</h1>
<p id="reload" hidden>This console is outdated. Reload the page before running another ceremony.</p>
<p>Operator: <strong id="actor">&hellip;</strong></p>
<section id="bootstrap" hidden>
<h2>First operator credential (bootstrap)</h2>
<p>This page registers this browser&rsquo;s passkey as the first operator credential. It is accepted only while the credential registry has never held a row; after that an existing credential must approve every new one.</p>
<button id="bootstrap-run" type="button">Create first operator credential</button>
</section>
<section id="hp-actions">
<h2>Local approvals</h2>
<div id="action-forms"><noscript>The console ceremony requires JavaScript.</noscript></div>
</section>
<p id="status" role="status"></p>
<script>
${consoleScriptSource(descriptors)}
</script>
</body>
</html>
`;
}