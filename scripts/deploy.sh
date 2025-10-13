#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
MANIFEST_DIST="${ROOT_DIR}/manifests/dist"
SHARED_DIST="${MANIFEST_DIST}/shared"
SIGNER_DIST="${MANIFEST_DIST}/signer"
NONSIGNER_DIST="${MANIFEST_DIST}/nonsigner"
GLOBAL_ENV="${ROOT_DIR}/global.env"

RUN_PREPARE=true
RUN_SECRETS=true

usage() {
  cat <<'EOF'
Pemakaian: scripts/deploy.sh [opsi]

Opsional:
  --skip-artifacts   Lewati eksekusi scripts/prepare-artifacts.sh
  --skip-secrets     Lewati eksekusi scripts/render-secrets.sh
  -h, --help         Tampilkan bantuan ini
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-artifacts) RUN_PREPARE=false ;;
    --skip-secrets) RUN_SECRETS=false ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Opsi tidak dikenali: $1" >&2; usage; exit 1 ;;
  esac
  shift
done

if [[ ! -f "${GLOBAL_ENV}" ]]; then
  echo "File global.env tidak ditemukan. Salin dari global.env.example dan isi nilainya." >&2
  exit 1
fi

set -a
# shellcheck source=/dev/null
source "${GLOBAL_ENV}"
set +a

K8S_NAMESPACE="${K8S_NAMESPACE:-poa-mainnet}"

if ${RUN_PREPARE}; then
  "${SCRIPT_DIR}/prepare-artifacts.sh"
fi

if ${RUN_SECRETS}; then
  "${SCRIPT_DIR}/render-secrets.sh"
fi

"${SCRIPT_DIR}/render-manifests.sh"

if ! kubectl get namespace "${K8S_NAMESPACE}" >/dev/null 2>&1; then
  kubectl create namespace "${K8S_NAMESPACE}"
fi

if [[ -d "${SHARED_DIST}" ]]; then
  for file in "${SHARED_DIST}"/*.yaml; do
    [[ -f "${file}" ]] || continue
    kubectl apply -f "${file}"
  done
fi

secret_manifest="${ROOT_DIR}/manifests/shared/secrets.generated.yaml"
if [[ -f "${secret_manifest}" ]]; then
  kubectl apply -f "${secret_manifest}"
fi

if [[ -d "${SIGNER_DIST}" ]]; then
  for file in "${SIGNER_DIST}"/*.yaml; do
    [[ -f "${file}" ]] || continue
    kubectl apply -f "${file}"
  done
fi

if [[ -d "${NONSIGNER_DIST}" ]]; then
  for file in "${NONSIGNER_DIST}"/*.yaml; do
    [[ -f "${file}" ]] || continue
    kubectl apply -f "${file}"
  done
fi

echo "Seluruh manifest PoA telah diajukan ke namespace ${K8S_NAMESPACE}."
