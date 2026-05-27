# Local configuration

Runtime files for desktop development live in `config/local/` (gitignored).

## Setup

```bash
cp config/examples/deployment-profile.example.json config/local/deployment-profile.json
# Paste SUPABASE_ANON_KEY from backend/local/.env
```

For boundary integration tests, use the same `config/local/deployment-profile.json` (see `config/examples/deployment-profile.boundary.json.example` for field notes).

Web builds still use `web/deployment-profile.json` (see `web/deployment-profile.example.json`).

## Override

Set `AICLINIC_DEPLOYMENT_PROFILE_PATH` to an absolute path when the profile lives outside this package.
