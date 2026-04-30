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

CREDENTIALS=$(printf '%s:%s' "$SIGMA_CLIENT_ID" "$SIGMA_CLIENT_SECRET" | base64)

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

echo "export SIGMA_API_TOKEN=${TOKEN}"
