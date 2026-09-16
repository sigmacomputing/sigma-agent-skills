---
name: sigma-api
description: >-
  Authenticate against the Sigma Computing REST API and obtain a bearer token.
  Use whenever the user wants to call the Sigma API directly with curl/HTTP,
  exchange OAuth client credentials for an access token, sign in interactively
  via a browser OAuth login (authorization-code + PKCE), configure
  SIGMA_BASE_URL / SIGMA_CLIENT_ID / SIGMA_CLIENT_SECRET, troubleshoot 401/403
  responses, or pick the right Sigma API hostname for their cloud. Use as a
  prerequisite when another Sigma skill needs an
  SIGMA_API_TOKEN.
---

# Sigma REST API Authentication

Authenticate against the Sigma Computing REST API and obtain a bearer token. This skill is a prerequisite for any skill that calls the Sigma API directly with `curl`.

`curl`, `jq`, and `base64` must be available. `curl` and `base64` ship with macOS and most Linux distros; `jq` usually does not — install with `brew install jq` (macOS) or `apt install jq` (Debian/Ubuntu).

## Reference Index

| File                                                                 | When to load                                                                                                                                                                                   |
| -------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| [reference/browser-oauth-login.md](reference/browser-oauth-login.md) | The user wants an interactive browser sign-in (OAuth authorization-code + PKCE) instead of a client ID/secret — the discovery-driven flow, code exchange, and encrypted refresh-token storage. |

## Base URL Selection

The host depends on the user's Sigma cloud and region. Confirm with the user before exporting. The user can also look up their base URL in **Administration → Developer Access** in the Sigma app.

The authoritative list lives in the Sigma help docs: [Supported regions, data platforms, and features](https://help.sigmacomputing.com/docs/region-warehouse-and-feature-support). Mirror below:

| Cloud | Region                | Base URL                                  |
| ----- | --------------------- | ----------------------------------------- |
| AWS   | US West (Oregon)      | `https://aws-api.sigmacomputing.com`      |
| AWS   | US East (N. Virginia) | `https://api.us-a.aws.sigmacomputing.com` |
| AWS   | Canada (Central)      | `https://api.ca.aws.sigmacomputing.com`   |
| AWS   | Europe (Frankfurt)    | `https://api.eu.aws.sigmacomputing.com`   |
| AWS   | Asia Pacific (Sydney) | `https://api.au.aws.sigmacomputing.com`   |
| AWS   | UK (London)           | `https://api.uk.aws.sigmacomputing.com`   |
| Azure | US (Virginia)         | `https://api.us.azure.sigmacomputing.com` |
| Azure | Europe (Netherlands)  | `https://api.eu.azure.sigmacomputing.com` |
| Azure | Canada (Toronto)      | `https://api.ca.azure.sigmacomputing.com` |
| Azure | UK (London)           | `https://api.uk.azure.sigmacomputing.com` |
| Azure | Australia             | `https://api.au.azure.sigmacomputing.com` |
| GCP   | US (Iowa)             | `https://api.sigmacomputing.com`          |
| GCP   | Saudi Arabia (Dammam) | `https://api.sa.gcp.sigmacomputing.com`   |

> `SIGMA_BASE_URL` is the **API host**, not the app URL — `https://aws-api.sigmacomputing.com`, not `https://app.sigmacomputing.com`.

## Step 1 — Set Credentials

Where to find credentials: Sigma admin settings → Administration → APIs and Tokens (also surfaced as Developer Access → API credentials).

```sh
export SIGMA_BASE_URL="https://aws-api.sigmacomputing.com"  # adjust per cloud
export SIGMA_CLIENT_ID="your-client-id"
export SIGMA_CLIENT_SECRET="your-client-secret"
```

## Step 2 — Exchange Credentials for a Bearer Token

There are **two independent ways** to obtain a token — use whichever suits you, and switch between them freely:

- **Client credentials** (this section) — an admin provisions a client ID/secret up front; the right fit for headless or automated use.
- **[Interactive browser login](#alternative-interactive-browser-login)** — sign in through the browser with no pre-issued credentials; the right fit when a human is at the keyboard.

Either way the token is short-lived (~1 hour TTL). The client-credentials grant (this section) uses OAuth 2.0 with HTTP Basic auth on the token endpoint.

### Client credentials: bundled helper script

`scripts/get-token.sh` reads the three env vars, fails loudly on missing inputs or non-2xx responses, and prints a single `export SIGMA_API_TOKEN=...` line. `eval` it to load the token into the current shell:

- **Claude Code:** `eval "$(${CLAUDE_PLUGIN_ROOT}/skills/sigma-api/scripts/get-token.sh)"`
- **Cursor / Codex / generic:** `eval "$(bash <repo-root>/skills/sigma-api/scripts/get-token.sh)"`

The script's interface:

| In (env)                                                   | Out (stdout)                                |
| ---------------------------------------------------------- | ------------------------------------------- |
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

### Alternative: interactive browser login

Prefer signing in through a browser over provisioning a client ID/secret? Sigma also supports an interactive **OAuth 2.1 authorization-code + PKCE** login — no pre-issued credentials, the client registers itself. It's the right fit when a human is at the keyboard; keep the client-credentials flow above for headless automation.

`scripts/browser-login.sh` packages the whole flow: it reads `SIGMA_BASE_URL`, discovers the OAuth endpoints, opens your browser, reads back the pasted callback URL, exchanges the code, stores the refresh token in the OS keychain, and prints an `export SIGMA_API_TOKEN=…` line to `eval` — just like `get-token.sh`.

- **Claude Code:** `eval "$(${CLAUDE_PLUGIN_ROOT}/skills/sigma-api/scripts/browser-login.sh)"`
- **Cursor / Codex / generic:** `eval "$(bash <repo-root>/skills/sigma-api/scripts/browser-login.sh)"`

The script picks a random high loopback port that nothing is currently listening on for its redirect URI, so the one-time authorization code is never delivered to another local process. Prompts go to stderr; only the `export` line reaches stdout.

Full discovery-driven walkthrough (including the refresh-token storage the script performs) in **[reference/browser-oauth-login.md](reference/browser-oauth-login.md)** — read it to understand or customize what the script does.

#### Reusing a browser login headlessly

After `browser-login.sh` has run once, `scripts/refresh-token.sh` mints a valid access token with no further browser interaction — the headless counterpart to `get-token.sh` for the browser flow. It serves a cached access token while it is still valid (~1h) and only redeems the stored refresh token when the cache is stale, rotating the stored refresh token when the server issues a new one.

- **Claude Code:** `eval "$(${CLAUDE_PLUGIN_ROOT}/skills/sigma-api/scripts/refresh-token.sh)"`
- **Cursor / Codex / generic:** `eval "$(bash <repo-root>/skills/sigma-api/scripts/refresh-token.sh)"`

Run it once per shell (or per phase of work) and reuse the exported `SIGMA_API_TOKEN` across calls; it is cheap to call repeatedly since a valid cache is served without a network round-trip. If it reports the refresh token is expired or revoked, run `browser-login.sh` again.

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
