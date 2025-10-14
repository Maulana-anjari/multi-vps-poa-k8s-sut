#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

REMOTE_USER="${REMOTE_USER:-maul}"
SUDO_PASSWORD="${SUDO_PASSWORD:-}"

if [[ -z "${SUDO_PASSWORD}" ]]; then
  read -rsp "Masukkan password sudo remote: " SUDO_PASSWORD
  echo
fi

declare -A SIGNER_HOSTS=(
  [UGM]=89.117.50.181
  [ITB]=185.194.216.132
  [UI]=155.133.23.145
  [UB]=109.199.99.164
  [ITS]=109.199.118.220
)

declare -A NONSIGNER_HOSTS=(
  [UNIMED]=89.117.50.181
  [UNUD]=185.194.216.132
  [Gundar]=155.133.23.145
  [UT]=109.199.99.164
  [UNDIP]=109.199.118.220
)

log() {
  printf '[%s] %s\n' "$(date '+%H:%M:%S')" "$*"
}

remote_sudo() {
  local host="$1"
  shift
  local body="$*"
  ssh "${REMOTE_USER}@${host}" "sudo -S bash -s" <<EOF
$SUDO_PASSWORD
set -euo pipefail
$body
EOF
}

rsync_dir() {
  local source="$1"
  local host="$2"
  local dest="$3"
  if [[ ! -d "${source}" ]]; then
    log "Skip ${source} (tidak ditemukan)"
    return 1
  fi
  rsync -avz "${source}" "${REMOTE_USER}@${host}:${dest}"
}

sync_signer() {
  local name="$1"
  local host="$2"
  local name_lower
  name_lower="$(tr '[:upper:]' '[:lower:]' <<<"${name}")"

  log ">>> Sinkron signer ${name} (${host})"

  remote_sudo "${host}" "
rm -rf /var/lib/poa/${name_lower}/clef /var/lib/poa/${name_lower}/geth
mkdir -p /var/lib/poa/${name_lower}/clef /var/lib/poa/${name_lower}/geth
chown -R ${REMOTE_USER}:${REMOTE_USER} /var/lib/poa/${name_lower}/clef /var/lib/poa/${name_lower}/geth
"

  rsync_dir "${ROOT_DIR}/artifacts/signer/${name}/volumes/clef/" "${host}" "/var/lib/poa/${name_lower}/clef/"
  rsync_dir "${ROOT_DIR}/artifacts/signer/${name}/volumes/geth/" "${host}" "/var/lib/poa/${name_lower}/geth/"

  remote_sudo "${host}" "
chown -R root:root /var/lib/poa/${name_lower}/clef /var/lib/poa/${name_lower}/geth
if [[ -f /var/lib/poa/${name_lower}/clef/masterseed.json ]]; then
  chmod 400 /var/lib/poa/${name_lower}/clef/masterseed.json
fi
"
}

sync_nonsigner() {
  local name="$1"
  local host="$2"
  local name_lower
  name_lower="$(tr '[:upper:]' '[:lower:]' <<<"${name}")"

  log ">>> Sinkron nonsigner ${name} (${host})"

  remote_sudo "${host}" "
rm -rf /var/lib/poa/${name_lower}/geth
mkdir -p /var/lib/poa/${name_lower}/geth
chown -R ${REMOTE_USER}:${REMOTE_USER} /var/lib/poa/${name_lower}/geth
"

  rsync_dir "${ROOT_DIR}/artifacts/nonsigner/${name}/volumes/geth/" "${host}" "/var/lib/poa/${name_lower}/geth/"

  remote_sudo "${host}" "
chown -R root:root /var/lib/poa/${name_lower}/geth
"
}

usage() {
  cat <<'EOF'
Usage: scripts/sync-host-artifacts.sh [TARGET ...]

TARGET dapat berupa nama signer (UGM, ITB, UI, UB, ITS) atau nonsigner (UNIMED, UNUD, Gundar, UT, UNDIP).
Tanpa argumen script akan menyinkronkan semua node.

Variabel lingkungan:
  REMOTE_USER    user SSH (default: maul)
  SUDO_PASSWORD  password sudo remote; jika kosong script akan meminta interaktif
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

targets=("$@")
if [[ ${#targets[@]} -eq 0 ]]; then
  targets=("${!SIGNER_HOSTS[@]}" "${!NONSIGNER_HOSTS[@]}")
fi

for target in "${targets[@]}"; do
  if [[ -n "${SIGNER_HOSTS[$target]:-}" ]]; then
    sync_signer "${target}" "${SIGNER_HOSTS[$target]}"
  elif [[ -n "${NONSIGNER_HOSTS[$target]:-}" ]]; then
    sync_nonsigner "${target}" "${NONSIGNER_HOSTS[$target]}"
  else
    log "Target ${target} tidak dikenal, lewati."
  fi
done

log "Selesai."
