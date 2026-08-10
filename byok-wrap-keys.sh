#!/usr/bin/env bash
# Cortex BYOK wrap — default import method RSA_OAEP_*_SHA256_AES_256
#
# Per Cortex docs: tenant needs TWO encryption keys (Data lake + Services).
# Customer generates one 32-byte target key for both, OR two separate target keys.
#
# CUSTOMER (target encryption key):
#   targetkey — 32-byte symmetric key (openssl rand 32). Never upload unwrapped.
#
# GATEWAY (wrapping keys — download on Wrap & Upload, valid ≤ 3 days):
#   datalake_wrapping_key.pem / services_wrapping_key.pem
#
# UPLOAD (wrapped target keys):
#   datalakewrappedkey / serviceswrappedkey
#
# Docs: https://cortex-docs.paloaltonetworks.com/cortex-xsiam/onboard-cortex-xsiam/deployment-steps/activate-cortex-xsiam/bring-your-own-keys
# OpenSSL patch: https://docs.cloud.google.com/kms/docs/configuring-openssl-for-manual-key-wrapping

set -euo pipefail

OPENSSL_SH="${OPENSSL_SH:-${HOME}/local/bin/openssl.sh}"
IV="A65959A6"

usage() {
  cat <<'EOF'
Cortex BYOK — wrap the CUSTOMER key (targetkey) for Gateway import.

Who owns what:
  CUSTOMER  targetkey                     32-byte KEK you generate (BYOK)
  GATEWAY   *_wrapping_key.pem            public PEMs you download
  UPLOAD    *wrappedkey                   wrapped customer key → Gateway

Usage:
  ./byok-wrap-keys.sh generate [targetkey]
  ./byok-wrap-keys.sh wrap <gateway_wrapping.pem> <customer_targetkey> <wrapped_out>
  ./byok-wrap-keys.sh wrap-both <datalake.pem> <services.pem> <customer_targetkey> [out_dir]

Import method in Gateway: RSA_OAEP_3072_SHA256_AES_256 (default) or *_4096_*
Requires patched OpenSSL: $HOME/local/bin/openssl.sh  (or OPENSSL_SH)

Example:
  ./byok-wrap-keys.sh generate targetkey
  ./byok-wrap-keys.sh wrap-both datalake_wrapping_key.pem services_wrapping_key.pem targetkey ./out
EOF
}

die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

require_cmd() { command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"; }

require_file() {
  [[ -f "$1" ]] || die "File not found: $1"
  [[ -s "$1" ]] || die "File is empty: $1"
}

require_pem() {
  require_file "$1"
  grep -q 'BEGIN PUBLIC KEY\|BEGIN RSA PUBLIC KEY' "$1" \
    || die "Not a Gateway public wrapping PEM: $1"
}

bytes_of() { wc -c < "$1" | tr -d ' '; }

generate_target() {
  local out="${1:-targetkey}"
  require_cmd openssl
  [[ ! -e "$out" ]] || die "Refusing to overwrite customer key: $out"
  openssl rand 32 > "$out"
  chmod 600 "$out"
  [[ "$(bytes_of "$out")" -eq 32 ]] || die "Failed to create 32-byte customer key"
  printf 'CUSTOMER key created (keep secret, never upload unwrapped): %s\n' "$out"
}

# Wrap CUSTOMER targetkey with a GATEWAY wrapping PEM (RSA-OAEP + AES-WRAP-PAD)
wrap_one() {
  local wrapping_pem="$1" target="$2" out="$3"
  local temp partial rsa_bits expected size

  require_cmd openssl
  require_cmd hexdump
  require_pem "$wrapping_pem"
  require_file "$target"
  [[ "$(bytes_of "$target")" -eq 32 ]] || die "Customer key must be exactly 32 bytes: $target"
  [[ -x "$OPENSSL_SH" ]] || die "Patched OpenSSL required: $OPENSSL_SH
See https://docs.cloud.google.com/kms/docs/configuring-openssl-for-manual-key-wrapping"
  [[ ! -e "$out" ]] || die "Refusing to overwrite: $out"

  rsa_bits="$(openssl rsa -pubin -in "$wrapping_pem" -text -noout 2>/dev/null \
    | awk '/Public-Key:/ { gsub(/[^0-9]/,"",$2); print $2; exit }')"
  case "${rsa_bits:-}" in
    3072) expected=$((3072 / 8 + 40)) ;; # RSA-OAEP block + AES-KW-PAD(32)
    4096) expected=$((4096 / 8 + 40)) ;;
    *) die "Gateway wrapping PEM must be 3072- or 4096-bit (got: ${rsa_bits:-unknown}): $wrapping_pem" ;;
  esac

  temp="$(mktemp "${TMPDIR:-/tmp}/byok-temp-aes.XXXXXX")"
  partial="$(mktemp "${TMPDIR:-/tmp}/byok-partial.XXXXXX")"
  # shellcheck disable=SC2064
  trap "rm -f '$temp' '$partial'" EXIT

  # Ephemeral AES key (not the customer KEK) — discarded after wrap
  openssl rand 32 > "$temp"

  openssl pkeyutl \
    -encrypt \
    -pubin \
    -inkey "$wrapping_pem" \
    -in "$temp" \
    -out "$partial" \
    -pkeyopt rsa_padding_mode:oaep \
    -pkeyopt rsa_oaep_md:sha256 \
    -pkeyopt rsa_mgf1_md:sha256

  "$OPENSSL_SH" enc \
    -id-aes256-wrap-pad \
    -iv "$IV" \
    -K "$(hexdump -v -e '/1 "%02x"' < "$temp")" \
    -in "$target" >> "$partial"

  size="$(bytes_of "$partial")"
  [[ "$size" -eq "$expected" ]] \
    || die "Wrapped size $size != expected $expected for RSA-${rsa_bits} (check OPENSSL_SH / import method)"

  mv "$partial" "$out"
  chmod 600 "$out"
  rm -f "$temp"
  trap - EXIT
  printf 'UPLOAD: %s (%s bytes) — customer key wrapped with Gateway PEM\n' "$out" "$size"
}

wrap_both() {
  local dl_pem="$1" sv_pem="$2" target="$3" out_dir="${4:-.}"
  mkdir -p "$out_dir"
  wrap_one "$dl_pem" "$target" "${out_dir%/}/datalakewrappedkey"
  wrap_one "$sv_pem" "$target" "${out_dir%/}/serviceswrappedkey"
  printf '\nUpload BOTH wrapped files in Cortex Gateway → Wrap & Upload → Complete Activation.\n'
  printf '  Data lake : %s/datalakewrappedkey\n' "${out_dir%/}"
  printf '  Services  : %s/serviceswrappedkey\n' "${out_dir%/}"
  printf 'Customer key stays local: %s\n' "$target"
}

cmd="${1:-}"
case "$cmd" in
  generate)
    generate_target "${2:-targetkey}"
    ;;
  wrap)
    [[ $# -eq 4 ]] || { usage; exit 1; }
    wrap_one "$2" "$3" "$4"
    ;;
  wrap-both)
    [[ $# -ge 4 && $# -le 5 ]] || { usage; exit 1; }
    wrap_both "$2" "$3" "$4" "${5:-.}"
    ;;
  -h|--help|help|"")
    usage
    ;;
  *)
    die "Unknown command: $cmd"
    ;;
esac
