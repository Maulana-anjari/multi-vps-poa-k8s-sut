#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
GLOBAL_ENV="${ROOT_DIR}/global.env"
MANIFEST_DIST="${ROOT_DIR}/manifests/dist"
SHARED_DIST="${MANIFEST_DIST}/shared"
SIGNER_DIST="${MANIFEST_DIST}/signer"
NONSIGNER_DIST="${MANIFEST_DIST}/nonsigner"
SECRET_MANIFEST="${ROOT_DIR}/manifests/shared/secrets.generated.yaml"

KEEP_NAMESPACE=false

usage() {
  cat <<'EOF'
Pemakaian: scripts/destroy.sh [opsi]

Opsional:
  --keep-namespace   Jangan hapus namespace Kubernetes setelah menghapus resource
  -h, --help         Tampilkan bantuan ini
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --keep-namespace) KEEP_NAMESPACE=true ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Opsi tidak dikenali: $1" >&2; usage; exit 1 ;;
  esac
  shift
done

if [[ ! -f "${GLOBAL_ENV}" ]]; then
  echo "File global.env tidak ditemukan; tidak dapat menentukan namespace." >&2
  exit 1
fi

set -a
# shellcheck source=/dev/null
source "${GLOBAL_ENV}"
set +a

K8S_NAMESPACE="${K8S_NAMESPACE:-poa-mainnet}"

delete_if_exists() {
  local path="$1"
  if [[ -d "${path}" ]]; then
    shopt -s nullglob
    local files=("${path}"/*.yaml)
    shopt -u nullglob
    [[ ${#files[@]} -gt 0 ]] || return 0
    kubectl delete -f "${path}" --ignore-not-found
  elif [[ -f "${path}" ]]; then
    kubectl delete -f "${path}" --ignore-not-found
  fi
}

delete_if_exists "${SIGNER_DIST}"
delete_if_exists "${NONSIGNER_DIST}"

if [[ -d "${SHARED_DIST}" ]]; then
  for file in "${SHARED_DIST}"/*.yaml; do
    [[ -f "${file}" ]] || continue
    kubectl delete -f "${file}" --ignore-not-found
  done
fi

if [[ -f "${SECRET_MANIFEST}" ]]; then
  kubectl delete -f "${SECRET_MANIFEST}" --ignore-not-found
fi

if ! ${KEEP_NAMESPACE}; then
  kubectl delete namespace "${K8S_NAMESPACE}" --ignore-not-found
fi

echo "Seluruh resource PoA telah dihapus."
