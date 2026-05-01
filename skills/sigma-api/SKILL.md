---
name: sigma-api
description: >-
  Authenticate against the Sigma Computing REST API and obtain a bearer token.
  Use whenever the user wants to call the Sigma API directly with curl/HTTP,
  exchange OAuth client credentials for an access token, configure
  SIGMA_BASE_URL / SIGMA_CLIENT_ID / SIGMA_CLIENT_SECRET, troubleshoot 401/403
  responses, or pick the right Sigma API hostname for their cloud. Use as a
  prerequisite when another Sigma skill needs an
  SIGMA_API_TOKEN.
---

# Sigma REST API Authentication

Authenticate against the Sigma Computing REST API and obtain a bearer token. This skill is a prerequisite for any skill that calls the Sigma API directly with `curl`.

`curl`, `jq`, and `base64` must be available. `curl` and `base64` ship with macOS and most Linux distros; `jq` usually does not — install with `brew install jq` (macOS) or `apt install jq` (Debian/Ubuntu).

## Base URL Selection

The host depends on where the Sigma organization is hosted. Confirm with the user before exporting. The user can also look up their base URL in **Administration > Developer Access** in Sigma.

The authoritative list lives in the Sigma help docs: [Supported regions, data platforms, and features](https://help.sigmacomputing.com/docs/region-warehouse-and-feature-support). Mirror below:

| Cloud | Region | Base URL |
|-------|--------|----------|
| AWS | US West (Oregon) | `https://aws-api.sigmacomputing.com` |
| AWS | US East (N. Virginia) | `https://api.us-a.aws.sigmacomputing.com` |
| AWS | Canada (Central) | `https://api.ca.aws.sigmacomputing.com` |
| AWS | Europe (Frankfurt) | `https://api.eu.aws.sigmacomputing.com` |
| AWS | Asia Pacific (Sydney) | `https://api.au.aws.sigmacomputing.com` |
| AWS | UK (London) | `https://api.uk.aws.sigmacomputing.com` |
| Azure | US (Virginia) | `https://api.us.azure.sigmacomputing.com` |
| Azure | Europe (Netherlands) | `https://api.eu.azure.sigmacomputing.com` |
| Azure | Canada (Toronto) | `https://api.ca.azure.sigmacomputing.com` |
| Azure | UK (London) | `https://api.uk.azure.sigmacomputing.com` |
| GCP | US (Iowa) | `https://api.sigmacomputing.com` |
| GCP | Saudi Arabia (Dammam) | `https://api.sa.gcp.sigmacomputing.com` |

> `SIGMA_BASE_URL` is the **API host**, not the app URL — `https://aws-api.sigmacomputing.com`, not `https://app.sigmacomputing.com`.

## Step 1 — Set Credentials

Where to find credentials: Sigma admin settings → Administration → APIs and Tokens (also surfaced as Developer Access → API credentials).

```sh
export SIGMA_BASE_URL="https://aws-api.sigmacomputing.com"  # adjust per cloud
export SIGMA_CLIENT_ID="your-client-id"
export SIGMA_CLIENT_SECRET="your-client-secret"
```

## Step 2 — Exchange Credentials for a Bearer Token

Sigma uses the OAuth 2.0 **client credentials** grant with HTTP Basic auth on the token endpoint. Tokens are short-lived (~1 hour TTL).

### Preferred: bundled helper script

`scripts/get-token.sh` reads the three env vars, fails loudly on missing inputs or non-2xx responses, and prints a single `export SIGMA_API_TOKEN=...` line. `eval` it to load the token into the current shell:

- **Claude Code:** `eval "$(${CLAUDE_PLUGIN_ROOT}/skills/sigma-api/scripts/get-token.sh)"`
- **Cursor / Codex / generic:** `eval "$(bash <repo-root>/skills/sigma-api/scripts/get-token.sh)"`

The script's interface:

| In (env) | Out (stdout) |
|----------|--------------|
| `SIGMA_BASE_URL`, `SIGMA_CLIENT_ID`, `SIGMA_CLIENT_SECRET` | A single line: `export SIGMA_API_TOKEN=...` |

Non-zero exit on missing env vars or token-exchange failure; error message goes to stderr.

### Manual token exchange (inline fallback)

```sh
CREDENTIALS=$(printf '%s:%s' "$SIGMA_CLIENT_ID" "$SIGMA_CLIENT_SECRET" | base64)

export SIGMA_API_TOKEN=$(curl -sf -X POST \
  -H "Authorization: Basic ${CREDENTIALS}" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=client_credentials" \
  "$SIGMA_BASE_URL/v2/auth/token" \
  | jq -r '.access_token')

[ -z "$SIGMA_API_TOKEN" ] || [ "$SIGMA_API_TOKEN" = "null" ] && { echo "Token exchange failed" >&2; exit 1; }
```

## Step 3 — Verify the Token

`GET /v2/whoami` is the canonical sanity check that the token is valid and the base URL is correct — use it after each token exchange and any time a later call's response is suspect.

```sh
curl -sf -H "Authorization: Bearer $SIGMA_API_TOKEN" \
  "$SIGMA_BASE_URL/v2/whoami" | jq .
```

The response includes `userId`, `organizationId`, and `accountType`.

## Token Expiry

Tokens last about an hour. Re-`eval` the helper (or repeat the manual exchange) to refresh. For long-running sessions, it's fine to refresh at the top of each phase of work.

## Interpreting HTTP Status Codes

- **2xx.** Success.
- **401 Unauthorized.** The token is missing, expired, or otherwise not accepted. Re-run the token exchange.
- **403 Forbidden.** The credentials authenticated, but the caller isn't permitted to make this request.
- **404 Not Found.** Wrong path, wrong `SIGMA_BASE_URL` for the user's cloud, or the resource doesn't exist.
- **5xx.** Server-side error. Retry with backoff.

## Security Notes

- Never echo `$SIGMA_API_TOKEN`, `$SIGMA_CLIENT_SECRET`, or any other secret to logs the user can share.
- Don't write secrets to files inside the workspace.
- Treat the bearer token like a password — only pass it via the `Authorization` header, never on a query string.
