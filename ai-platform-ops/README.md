# AI Platform Ops

Local webservice console for invoking AI platform clinic, control, debug, and E2E surfaces without editing `ai-platform/src`.

## Run

```bash
# once: install deps for ops UI and for E2E gate subprocesses
cd ai-platform && npm install
cd ../ai-platform-ops && npm install

# start the console (API middleware on the same port)
cd ai-platform-ops
npm run dev
```

Open http://127.0.0.1:5174

1. Set **Platform URL** to your Worker (e.g. `http://127.0.0.1:8787`)
2. Click **Bootstrap dev credentials** (local admin/admin) or set **Operator bearer** / **AAT** manually
3. Pick a category tab → entity → fill fields → **Run**

Raw HTTP / handler output appears in the response panel. No expected-verdict chrome.

Optional standalone API only: `npm run server` (port 8790; override with `OPS_PORT`).

See `IMPLEMENTATION.md` for locked design and catalog rules.
