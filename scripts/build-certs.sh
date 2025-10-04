#!/usr/bin/env bash
set -euo pipefail

# Always default to the www host unless explicitly passed as arg
HOST="${1:-www.app-api.ing.carrier.com}"
OUT="certs/app-api-ing-carrier-ca-bundle.pem"
TMP="$(mktemp)"

mkdir -p certs

echo "🔍 Fetching certificate chain from $HOST …"

# 1) Fetch the full chain
openssl s_client -showcerts -connect "$HOST:443" -servername "$HOST" </dev/null 2>/dev/null \
  | awk '/BEGIN CERTIFICATE/,/END CERTIFICATE/ {print}' > "$TMP"

# 2) Split into cert_N.pem files
i=0
awk 'BEGIN{c=0} /BEGIN CERTIFICATE/{f=sprintf("cert_%02d.pem",c++);} {print > f} /END CERTIFICATE/{close(f)}' "$TMP"

# 3) Inspect and filter CA certs
: > "$OUT"
for f in cert_*.pem; do
  echo "------------------------------------------------------"
  echo "📄 Preview of $f:"
  openssl x509 -in "$f" -noout -subject -issuer -dates -fingerprint -sha256
  
  # keep only CA certificates
  if openssl x509 -in "$f" -noout -text | grep -q "CA:TRUE"; then
    echo "✅ Adding $f to CA bundle"
    cat "$f" >> "$OUT"
    echo >> "$OUT"
  else
    echo "❌ Skipping $f (not a CA cert)"
  fi
done

# 4) Clean up temp files
rm -f cert_*.pem "$TMP"

echo "------------------------------------------------------"
echo "📦 Wrote CA bundle to $OUT"
