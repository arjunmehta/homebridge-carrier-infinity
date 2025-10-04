#!/usr/bin/env bash
set -euo pipefail

# Defaults
HOST="www.app-api.ing.carrier.com"
OUT_DIR="certs"
BUNDLE_NAME="app-api-ing-carrier-ca-bundle.pem"
EXPORT_LEAF=false
WRITE_PIN=false

usage() {
  cat <<EOF
Usage: $(basename "$0") [-h host] [-o out_dir] [-l] [-p]
  -h host     Hostname to fetch (default: ${HOST})
  -o out_dir  Output directory (default: ${OUT_DIR})
  -l          Also export leaf certificate to leaf.pem
  -p          Also compute and save leaf SPKI pin (pin.txt)
Examples:
  $(basename "$0")
  $(basename "$0") -h www.app-api.ing.carrier.com -o certs -l -p
EOF
}

while getopts ":h:o:lp" opt; do
  case $opt in
    h) HOST="$OPTARG" ;;
    o) OUT_DIR="$OPTARG" ;;
    l) EXPORT_LEAF=true ;;
    p) WRITE_PIN=true ;;
    \?) echo "Invalid option: -$OPTARG" >&2; usage; exit 2 ;;
  esac
done

# -- Resolve output paths relative to this script's directory --
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
OUT_PATH="${PROJECT_ROOT}/${OUT_DIR}"
TMP_DIR="$(mktemp -d)"

mkdir -p "${OUT_PATH}"

BUNDLE_PATH="${OUT_PATH}/${BUNDLE_NAME}"
LEAF_PATH="${OUT_PATH}/leaf.pem"
PIN_PATH="${OUT_PATH}/pin.txt"

echo "🔍 Fetching certificate chain from ${HOST}:443 …"
CHAIN_RAW="${TMP_DIR}/chain_all.pem"

# Grab the presented chain
# - Suppress stderr noise from OpenSSL negotiation
openssl s_client -showcerts -connect "${HOST}:443" -servername "${HOST}" </dev/null 2>/dev/null \
  | awk '/BEGIN CERTIFICATE/,/END CERTIFICATE/ {print}' > "${CHAIN_RAW}"

if ! grep -q "BEGIN CERTIFICATE" "${CHAIN_RAW}"; then
  echo "❌ No certificates retrieved. Check DNS/VPN/connectivity or the hostname (${HOST})."
  exit 1
fi

# Split into cert_XX.pem
awk 'BEGIN{c=0} /BEGIN CERTIFICATE/{f=sprintf("cert_%02d.pem",c++);} {print > f} /END CERTIFICATE/{close(f)}' "${CHAIN_RAW}"

shopt -s nullglob
CERT_FILES=(cert_*.pem)
if [ ${#CERT_FILES[@]} -eq 0 ]; then
  echo "❌ Could not split certificates."
  exit 1
fi

echo
echo "================ Certificate Preview ================"
idx=0
LEAF_GUESSED=""
CA_FILES=()
ROOT_FILE=""

for f in "${CERT_FILES[@]}"; do
  echo "------------------------------------------------------"
  echo "📄 ${f}"
  openssl x509 -in "$f" -noout -subject -issuer -dates -fingerprint -sha256

  # Identify CA or leaf
  if openssl x509 -in "$f" -noout -text | grep -q "CA:TRUE"; then
    # Check if self-signed (likely a root): subject == issuer
    SUBJ="$(openssl x509 -in "$f" -noout -subject | sed 's/subject= //')"
    ISSR="$(openssl x509 -in "$f" -noout -issuer  | sed 's/issuer= //')"
    if [ "$SUBJ" = "$ISSR" ]; then
      echo "🔗 Type: ROOT CA (self-signed)"
      ROOT_FILE="$f"
    else
      echo "🔗 Type: INTERMEDIATE CA"
      CA_FILES+=("$f")
    fi
  else
    echo "🔗 Type: LEAF (end-entity)"
    # The first non-CA is almost always the leaf as sent by the server
    if [ -z "${LEAF_GUESSED}" ]; then
      LEAF_GUESSED="$f"
    fi
  fi
  ((idx++))
done

echo "======================================================"
echo

# Build bundle: intermediates (in received order) + root (if present)
: > "${BUNDLE_PATH}"
if [ ${#CA_FILES[@]} -eq 0 ] && [ -z "${ROOT_FILE}" ]; then
  echo "⚠️  No CA certs detected. The server may be sending only the leaf. Bundle would be empty."
  echo "    You likely need the issuing intermediate(s) from the provider."
  # Still write (empty) so the script exits cleanly with a clear message.
fi

for f in "${CA_FILES[@]}"; do
  cat "$f" >> "${BUNDLE_PATH}"
  echo >> "${BUNDLE_PATH}"
done
if [ -n "${ROOT_FILE}" ]; then
  cat "${ROOT_FILE}" >> "${BUNDLE_PATH}"
  echo >> "${BUNDLE_PATH}"
fi

echo "📦 Wrote CA bundle: ${BUNDLE_PATH}"

# Optionally export the leaf and compute SPKI pin
if $EXPORT_LEAF || $WRITE_PIN; then
  if [ -z "${LEAF_GUESSED}" ]; then
    echo "⚠️  Could not identify a leaf certificate in the chain; skipping leaf export/pin."
  else
    if $EXPORT_LEAF; then
      cp "${LEAF_GUESSED}" "${LEAF_PATH}"
      echo "🌿 Wrote leaf certificate: ${LEAF_PATH}"
    fi
    if $WRITE_PIN; then
      # Compute SPKI (public key) SHA-256 pin in base64
      openssl x509 -in "${LEAF_GUESSED}" -pubkey -noout \
        | openssl pkey -pubin -outform DER \
        | openssl dgst -sha256 -binary \
        | openssl base64 > "${PIN_PATH}"
      echo "🔒 Wrote SPKI pin: ${PIN_PATH}"
      echo "    (Use this value to pin the server key in your Node client.)"
    fi
  fi
fi

# Cleanup
rm -rf "${TMP_DIR}"
rm -f cert_*.pem

echo "✅ Done."
