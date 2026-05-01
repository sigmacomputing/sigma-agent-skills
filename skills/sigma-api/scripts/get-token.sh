#!/usr/bin/env bash
# Exchange a Sigma OAuth client_id/client_secret for a bearer token.
#
# Reads credentials from environment variables:
#   SIGMA_BASE_URL      e.g. https://aws-api.sigmacomputing.com
#   SIGMA_CLIENT_ID     OAuth client ID from Sigma admin settings
#   SIGMA_CLIENT_SECRET OAuth client secret
#
# Prints:
#   export SIGMA_API_TOKEN=<token>
#
# Usage:
#   eval "$(./get-token.sh)"
#
# or:
#   ./get-token.sh > /tmp/sigma-token.env && source /tmp/sigma-token.env

set -euo pipefail

: "${SIGMA_BASE_URL:?SIGMA_BASE_URL is not set}"
: "${SIGMA_CLIENT_ID:?SIGMA_CLIENT_ID is not set}"
: "${SIGMA_CLIENT_SECRET:?SIGMA_CLIENT_SECRET is not set}"

for bin in curl jq base64; do
  command -v "$bin" >/dev/null 2>&1 || { echo "Error: $bin is required" >&2; exit 1; }
done

# Pin to known Sigma cloud hosts. The script's stdout is intended to be eval'd,
# so a hostile token-endpoint response could otherwise become RCE on the caller.
case "$SIGMA_BASE_URL" in
  https://aws-api.sigmacomputing.com|\
  https://api.ca.sigmacomputing.com|\
  https://api.eu.sigmacomputing.com|\
  https://api.uk.sigmacomputing.com|\
  https://api.sigmacomputing.com|\
  https://api.az.sigmacomputing.com) ;;
  *) echo "Error: SIGMA_BASE_URL must be one of the published Sigma API hosts (see SKILL.md)." >&2; exit 1 ;;
esac

# `printf` (not `echo`) so no trailing newline is encoded into the credentials.
# `tr -d '\n'` strips the wrap base64 inserts at 76 columns by default on both
# BSD and GNU — without it, long id:secret pairs would inject a newline into
# the Authorization header.
CREDENTIALS=$(printf '%s:%s' "$SIGMA_CLIENT_ID" "$SIGMA_CLIENT_SECRET" | base64 | tr -d '\n')

RESPONSE=$(curl -sf -X POST "${SIGMA_BASE_URL}/v2/auth/token" \
  -H "Authorization: Basic ${CREDENTIALS}" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=client_credentials")

TOKEN=$(echo "$RESPONSE" | jq -r '.access_token')

if [[ -z "$TOKEN" || "$TOKEN" == "null" ]]; then
  echo "Error: failed to extract access_token from response:" >&2
  echo "$RESPONSE" >&2
  exit 1
fi

# The token will be eval'd by the caller. Reject any character outside the
# OAuth-2 bearer-token alphabet (RFC 6750 §2.1) so a compromised or spoofed
# token endpoint cannot smuggle shell metacharacters into `eval`.
if ! [[ "$TOKEN" =~ ^[A-Za-z0-9._~+/=-]+$ ]]; then
  echo "Error: token contains unexpected characters; refusing to emit." >&2
  exit 1
fi

printf 'export SIGMA_API_TOKEN=%q\n' "$TOKEN"
