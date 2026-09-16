#!/usr/bin/env bash
# Interactive browser login for the Sigma API (OAuth 2.1 authorization-code + PKCE).
#
# Unlike get-token.sh (headless client-credentials), this signs a *human* in
# through the browser — no pre-provisioned client_id/secret. It:
#   1. discovers the OAuth endpoints from an unauthenticated /v2/whoami 401,
#   2. registers a public client (RFC 7591),
#   3. runs the PKCE authorization-code flow, opening the system browser,
#   4. captures the redirect on a one-shot local loopback listener (falls back
#      to pasting the callback URL back if ruby isn't available, or the
#      listener times out), verifying the CSRF state,
#   5. exchanges the code, stores the refresh token in the OS keychain,
#   6. prints `export SIGMA_API_TOKEN=<token>` on stdout.
#
# Reads (env):
#   SIGMA_BASE_URL   e.g. https://api.sigmacomputing.com   (required)
#
# Prints (stdout, meant to be eval'd):
#   export SIGMA_API_TOKEN=<token>
# All prompts/progress go to stderr, so `eval "$(browser-login.sh)"` works.
#
# Usage:
#   eval "$(./browser-login.sh)"

set -euo pipefail

: "${SIGMA_BASE_URL:?SIGMA_BASE_URL is not set (see SKILL.md for the per-cloud host)}"

for bin in curl jq openssl; do
  command -v "$bin" >/dev/null 2>&1 || { echo "Error: $bin is required" >&2; exit 1; }
done

log() { printf '%s\n' "$*" >&2; }

# Pin SIGMA_BASE_URL to a known Sigma cloud host. The script's stdout is eval'd,
# so a hostile discovery/token response could otherwise become RCE on the caller.
case "$SIGMA_BASE_URL" in
  https://aws-api.sigmacomputing.com|\
  https://api.us-a.aws.sigmacomputing.com|\
  https://api.ca.aws.sigmacomputing.com|\
  https://api.eu.aws.sigmacomputing.com|\
  https://api.au.aws.sigmacomputing.com|\
  https://api.uk.aws.sigmacomputing.com|\
  https://api.us.azure.sigmacomputing.com|\
  https://api.eu.azure.sigmacomputing.com|\
  https://api.ca.azure.sigmacomputing.com|\
  https://api.uk.azure.sigmacomputing.com|\
  https://api.au.azure.sigmacomputing.com|\
  https://api.sigmacomputing.com|\
  https://api.sa.gcp.sigmacomputing.com) ;;
  *) echo "Error: SIGMA_BASE_URL must be one of the published Sigma API hosts (see SKILL.md)." >&2; exit 1 ;;
esac

# Every endpoint we discover must live on a Sigma host — never open a browser at,
# or POST credentials to, an authorization server a spoofed discovery doc names.
assert_sigma_host() {
  local url="$1" host
  # The authority ends at the first '/', '?', or '#'; strip any userinfo and port
  # so the check sees exactly the host curl will connect to. A naive "everything
  # up to the first /" parse would let https://evil.com#.sigmacomputing.com (curl
  # connects to evil.com) slip past the *.sigmacomputing.com glob.
  host=$(printf '%s' "$url" | sed -E 's#^https?://##; s#[/?#].*##; s#^[^@]*@##; s#:[0-9]+$##')
  case "$host" in
    *.sigmacomputing.com|sigmacomputing.com) ;;
    *) echo "Error: refusing OAuth endpoint on non-Sigma host: ${host:-<none>}" >&2; exit 1 ;;
  esac
}

urlenc() { jq -rn --arg v "$1" '$v|@uri'; }

# --- A. Discover the OAuth endpoints from an unauthenticated /v2/whoami 401. ---
WWW_AUTH=$(curl -sS -D - -o /dev/null "$SIGMA_BASE_URL/v2/whoami" | tr -d '\r' | grep -i '^www-authenticate:' || true)
[ -n "$WWW_AUTH" ] || { echo "Error: $SIGMA_BASE_URL/v2/whoami returned no WWW-Authenticate header; this host does not offer browser login. Use get-token.sh (client credentials)." >&2; exit 1; }

RESOURCE_META=$(printf '%s' "$WWW_AUTH" | grep -oE 'resource_metadata="[^"]+"' | cut -d'"' -f2 || true)
SCOPE=$(printf '%s' "$WWW_AUTH" | grep -oE 'scope="[^"]+"' | cut -d'"' -f2 || true)
[ -n "$RESOURCE_META" ] || { echo "Error: could not parse resource_metadata from WWW-Authenticate header." >&2; exit 1; }
[ -n "$SCOPE" ] || { echo "Error: could not parse scope from WWW-Authenticate header." >&2; exit 1; }
assert_sigma_host "$RESOURCE_META"

AUTH_SERVER=$(curl -sS "$RESOURCE_META" | jq -r '.authorization_servers[0] // empty')
[ -n "$AUTH_SERVER" ] || { echo "Error: no authorization server listed in protected-resource metadata." >&2; exit 1; }
AUTH_SERVER=${AUTH_SERVER%/}
assert_sigma_host "$AUTH_SERVER"

META=$(curl -sS "$AUTH_SERVER/.well-known/oauth-authorization-server")
AUTHORIZE_URL=$(printf '%s' "$META" | jq -r '.authorization_endpoint // empty')
TOKEN_URL=$(printf '%s' "$META" | jq -r '.token_endpoint // empty')
REGISTER_URL=$(printf '%s' "$META" | jq -r '.registration_endpoint // empty')
for u in "$AUTHORIZE_URL" "$TOKEN_URL" "$REGISTER_URL"; do
  [ -n "$u" ] || { echo "Error: authorization-server metadata is missing an endpoint URL." >&2; exit 1; }
  assert_sigma_host "$u"
done

# --- Pick a loopback port that NOTHING is currently listening on, so the auth
# --- code is only ever delivered to the address bar — never to a foreign local
# --- process that happens to hold the port. ---
port_is_free() {
  # Succeeds (returns 0) only when NOTHING is listening on 127.0.0.1:$1.
  # Prefer lsof (shell-independent, present on macOS/Linux); fall back to bash's
  # /dev/tcp connect. Both are used only to SKIP busy ports — the random high
  # port below is the real guard against handing the code to a foreign process.
  if command -v lsof >/dev/null 2>&1; then
    ! lsof -nP -iTCP:"$1" -sTCP:LISTEN >/dev/null 2>&1
  else
    ! (exec 3<>"/dev/tcp/127.0.0.1/$1") 2>/dev/null
  fi
}
REDIRECT_PORT=""
for ((i = 0; i < 50; i++)); do
  cand=$(( 20000 + (RANDOM % 20000) ))
  if port_is_free "$cand"; then REDIRECT_PORT="$cand"; break; fi
done
[ -n "$REDIRECT_PORT" ] || { echo "Error: could not find a free loopback port after 50 tries." >&2; exit 1; }
REDIRECT_URI="http://127.0.0.1:${REDIRECT_PORT}/oauth/callback"

# --- B. Register a public client (RFC 7591). ---
REG=$(curl -sS -X POST "$REGISTER_URL" \
  -H "Content-Type: application/json" \
  -d "$(jq -n --arg r "$REDIRECT_URI" --arg s "$SCOPE" '{
    redirect_uris: [$r], client_name: "sigma-api skill", scope: $s,
    token_endpoint_auth_method: "none"
  }')")
CLIENT_ID=$(printf '%s' "$REG" | jq -r '.client_id // empty')
[ -n "$CLIENT_ID" ] || { echo "Error: client registration failed:" >&2; printf '%s\n' "$REG" >&2; exit 1; }

# --- C. PKCE verifier/challenge + a CSRF state. ---
VERIFIER=$(openssl rand -base64 96 | tr -d '\n=+/' | cut -c1-64)
CHALLENGE=$(printf '%s' "$VERIFIER" | openssl dgst -binary -sha256 | openssl base64 | tr '+/' '-_' | tr -d '=\n')
STATE=$(openssl rand -base64 24 | tr '+/' '-_' | tr -d '=\n')

# --- D. Authorize in the browser, capturing the redirect automatically. ---
AUTH_REQ="${AUTHORIZE_URL}?response_type=code&client_id=$(urlenc "$CLIENT_ID")&redirect_uri=$(urlenc "$REDIRECT_URI")&state=$(urlenc "$STATE")&code_challenge=${CHALLENGE}&code_challenge_method=S256&scope=$(urlenc "$SCOPE")"

# Pull code + state out of a callback URL (belt-and-suspenders for the fallback
# path below; the listener does its own parsing to build a same-origin
# response, but this is what actually feeds the token exchange). Stop at '&'
# AND '#' so a trailing fragment isn't swallowed into the value, then
# percent-decode — the address-bar/query value is URL-encoded and curl
# --data-urlencode re-encodes on the way out, so without this a code carrying
# a %XX escape would be double-encoded and rejected.
# The pattern must be quoted — bash parses the unquoted form `${1//%/...}` as
# the anchored-suffix substitution `${1/%.../...}` (empty pattern anchored at
# the end), which unconditionally appends the replacement instead of
# replacing every literal `%`. Verified live: unquoted, this silently
# corrupts every decoded value with a trailing NUL byte and never actually
# decodes a real %XX escape.
urldec() { printf '%b' "${1//'%'/\\x}"; }
qs_param() { printf '%s' "$1" | sed -n "s/.*[?&]$2=\([^&#]*\).*/\1/p"; }

CODE=""
RET_STATE=""
LISTENER_PID=""
LISTENER_OUT=""

open_browser() {
  log ""
  log "Opening your browser to sign in to Sigma…"
  log "If it does not open, paste this URL into a browser yourself:"
  log ""
  log "  $AUTH_REQ"
  log ""
  if command -v open >/dev/null 2>&1; then
    open "$AUTH_REQ" >/dev/null 2>&1 || true
  elif command -v xdg-open >/dev/null 2>&1; then
    xdg-open "$AUTH_REQ" >/dev/null 2>&1 || true
  fi
}

# Start a one-shot local listener BEFORE opening the browser, so the redirect
# lands on it directly and the code never has to be read back from the address
# bar. Bind failure or no ruby → CODE stays empty and we fall back below.
if command -v ruby >/dev/null 2>&1; then
  LISTENER_OUT=$(mktemp)
  ruby - "$REDIRECT_PORT" >"$LISTENER_OUT" 2>/dev/null <<'RBEOF' &
require 'socket'

port = ARGV[0].to_i
srv = Socket.new(Socket::AF_INET, Socket::SOCK_STREAM, 0)
srv.setsockopt(Socket::SOL_SOCKET, Socket::SO_REUSEADDR, true)
begin
  srv.bind(Socket.pack_sockaddr_in(port, '127.0.0.1'))
  srv.listen(5)
rescue SystemCallError
  exit 1
end

body = "<html><body>Signed in to Sigma &mdash; you can close this tab and return to the terminal.</body></html>"
resp = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: #{body.bytesize}\r\nConnection: close\r\n\r\n#{body}"

deadline = Time.now + 120
found = nil

loop do
  remaining = deadline - Time.now
  break if remaining <= 0
  ready, = IO.select([srv], nil, nil, remaining)
  break unless ready

  conn, = srv.accept
  data = ''
  begin
    r, = IO.select([conn], nil, nil, 5)
    data = conn.recv(65536) if r
  rescue StandardError
    data = ''
  end
  request_line = data.split("\r\n", 2).first.to_s
  req_path = request_line.split(' ')[1].to_s
  begin
    conn.write(resp)
  rescue StandardError
  end
  conn.close

  # Ignore stray requests (e.g. a browser's speculative /favicon.ico) —
  # keep accepting on the same listener until the real callback arrives
  # or the deadline above is hit.
  if req_path.start_with?('/oauth/callback')
    found = req_path
    break
  end
end

srv.close
puts found if found
RBEOF
  LISTENER_PID=$!

  open_browser
  log "Waiting for you to approve in the browser (up to 2 minutes)…"

  wait "$LISTENER_PID" 2>/dev/null || true
  CALLBACK_PATH=$(cat "$LISTENER_OUT" 2>/dev/null || true)
  rm -f "$LISTENER_OUT"

  if [ -n "$CALLBACK_PATH" ]; then
    CODE=$(urldec "$(qs_param "$CALLBACK_PATH" code)")
    RET_STATE=$(urldec "$(qs_param "$CALLBACK_PATH" state)")
    [ -n "$CODE" ] || log "Warning: listener caught a callback with no ?code= — falling back to manual paste."
  else
    log "No callback arrived within 2 minutes — falling back to manual paste."
  fi
fi

# Fallback: no ruby, the listener couldn't bind, or it timed out/came back
# empty. This is the same zero-dependency path the flow always used. Only
# open the browser here if the listener path above never got a chance to
# (no ruby) — if it already opened once and just timed out waiting for
# approval, opening a second tab on the same request would just be noise.
if [ -z "$CODE" ]; then
  if [ -z "$LISTENER_PID" ]; then
    open_browser
  fi
  log "After you approve, the browser will try to load a"
  log "  http://127.0.0.1:${REDIRECT_PORT}/oauth/callback?code=…&state=…"
  log "page that fails to connect — that is expected (nothing is listening there)."
  log "Copy the FULL address-bar URL, paste it here, and press Enter:"
  # Prefer the controlling terminal (works even under `eval "$(...)"`, where
  # stdout is captured). If there is no usable tty — the open/read fails, e.g.
  # macOS "Device not configured" — fall back to stdin (piped/automated callers).
  CALLBACK=""
  if ! { read -r CALLBACK < /dev/tty; } 2>/dev/null; then
    read -r CALLBACK || true
  fi
  [ -n "$CALLBACK" ] || { echo "Error: no callback URL provided." >&2; exit 1; }
  CODE=$(urldec "$(qs_param "$CALLBACK" code)")
  RET_STATE=$(urldec "$(qs_param "$CALLBACK" state)")
  [ -n "$CODE" ] || { echo "Error: no ?code= found in the pasted URL." >&2; exit 1; }
fi

[ "$RET_STATE" = "$STATE" ] || { echo "Error: state mismatch (possible CSRF) — aborting." >&2; exit 1; }

# --- E. Exchange the authorization code for tokens. ---
TOKENS=$(curl -sS -X POST "$TOKEN_URL" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  --data-urlencode "grant_type=authorization_code" \
  --data-urlencode "code=$CODE" \
  --data-urlencode "redirect_uri=$REDIRECT_URI" \
  --data-urlencode "code_verifier=$VERIFIER" \
  --data-urlencode "client_id=$CLIENT_ID")
ACCESS=$(printf '%s' "$TOKENS" | jq -r '.access_token // empty')
REFRESH=$(printf '%s' "$TOKENS" | jq -r '.refresh_token // empty')
if [ -z "$ACCESS" ]; then
  echo "Error: token exchange failed:" >&2
  printf '%s\n' "$TOKENS" | jq . >&2 2>/dev/null || printf '%s\n' "$TOKENS" >&2
  exit 1
fi

# The token will be eval'd by the caller. Reject anything outside the RFC 6750
# bearer-token alphabet so a spoofed token endpoint cannot smuggle shell into eval.
if ! [[ "$ACCESS" =~ ^[A-Za-z0-9._~+/=-]+$ ]]; then
  echo "Error: token contains unexpected characters; refusing to emit." >&2
  exit 1
fi

# --- F. Persist the refresh token (never to a workspace file) so a later
# --- refresh needs no browser round-trip. client_id + token_url ride along so
# --- the refresh is self-contained (see reference/browser-oauth-login.md, §F). ---
if [ -n "$REFRESH" ]; then
  if command -v security >/dev/null 2>&1; then
    if security add-generic-password -U -a "$USER" -s "sigma-api:refresh-token" -w "$REFRESH" 2>/dev/null; then
      security add-generic-password -U -a "$USER" -s "sigma-api:client-id" -w "$CLIENT_ID" >/dev/null 2>&1 || true
      security add-generic-password -U -a "$USER" -s "sigma-api:token-url" -w "$TOKEN_URL" >/dev/null 2>&1 || true
      log "Stored refresh token in the macOS keychain (service 'sigma-api:refresh-token')."
    else
      log "Warning: could not write to the macOS keychain; refresh token NOT persisted."
    fi
  elif command -v secret-tool >/dev/null 2>&1; then
    if printf '%s' "$REFRESH" | secret-tool store --label="sigma-api refresh token" service sigma-api key refresh-token; then
      log "Stored refresh token via libsecret (service 'sigma-api', key 'refresh-token')."
    else
      log "Warning: could not write to libsecret; refresh token NOT persisted."
    fi
  else
    log "Note: no OS keychain tool (security/secret-tool) found; refresh token NOT persisted."
  fi
else
  log "Note: no refresh_token returned; sign in again when the access token expires (~1h)."
fi

printf 'export SIGMA_API_TOKEN=%q\n' "$ACCESS"
