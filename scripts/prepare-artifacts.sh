#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
SRC_DIR="$(cd "${ROOT_DIR}/../blockchain-poa-geth" && pwd)"
CONFIG_DIR="${ROOT_DIR}/config"
ARTIFACTS_DIR="${ROOT_DIR}/artifacts"
IPS_FILE="${CONFIG_DIR}/ips.env"
GLOBAL_ENV="${ROOT_DIR}/global.env"

if [[ ! -d "${SRC_DIR}" ]]; then
  echo "Sumber artefak tidak ditemukan di ${SRC_DIR}. Jalankan skrip ini dari dalam repo skripsi." >&2
  exit 1
fi

mkdir -p "${CONFIG_DIR}/addresses" "${CONFIG_DIR}/passwords"

cp "${SRC_DIR}/config/genesis.json" "${CONFIG_DIR}/genesis.json"
cp "${SRC_DIR}/config/rules.js" "${CONFIG_DIR}/rules.js"

if [[ -f "${SRC_DIR}/config/static-nodes.json" ]]; then
  cp "${SRC_DIR}/config/static-nodes.json" "${CONFIG_DIR}/static-nodes.json"
fi

if [[ -f "${IPS_FILE}" ]]; then
  set -a
  # shellcheck source=/dev/null
  source "${IPS_FILE}"
  set +a
fi

bootnode_template=""
if [[ -f "${SRC_DIR}/.env" ]]; then
  bootnode_template="$(grep '^BOOTNODE_ENODE=' "${SRC_DIR}/.env" | cut -d'=' -f2-)"
fi

update_global_env_bootnode() {
  local bootnode_value="$1"
  if [[ -z "${bootnode_value}" ]]; then
    return
  fi
  if [[ -f "${GLOBAL_ENV}" ]]; then
    if grep -q '^BOOTNODE_ENODE=' "${GLOBAL_ENV}"; then
      sed -i -E "s|^BOOTNODE_ENODE=.*|BOOTNODE_ENODE=${bootnode_value}|" "${GLOBAL_ENV}"
    else
      printf 'BOOTNODE_ENODE=%s\n' "${bootnode_value}" >> "${GLOBAL_ENV}"
    fi
  else
    printf 'BOOTNODE_ENODE=%s\n' "${bootnode_value}" > "${GLOBAL_ENV}"
  fi
}

if [[ -n "${bootnode_template}" ]]; then
  bootnode_ip="${PUBLIC_IP_UT:-}"
  bootnode_value="${bootnode_template}"
  if [[ -n "${bootnode_ip}" ]]; then
    bootnode_value="${bootnode_value//nonsigner1/$bootnode_ip}"
    bootnode_value="${bootnode_value//UNIMED/$bootnode_ip}"
  fi
  update_global_env_bootnode "${bootnode_value}"
fi

declare -a SIGNER_NAMES=(UGM ITB UI UB ITS)
declare -a NONSIGNER_NAMES=(UT UNIMED UNUD Gundar UNDIP)

for idx in "${!SIGNER_NAMES[@]}"; do
  num=$((idx + 1))
  name="${SIGNER_NAMES[$idx]}"
  lower_name="$(echo "${name}" | tr '[:upper:]' '[:lower:]')"
  src_geth="${SRC_DIR}/data/signer${num}"
  src_clef="${SRC_DIR}/data/clef${num}"
  dest_geth="${ARTIFACTS_DIR}/signer/${name}/volumes/geth"
  dest_clef="${ARTIFACTS_DIR}/signer/${name}/volumes/clef"
  mkdir -p "${dest_geth}" "${dest_clef}"
  rm -rf "${dest_geth:?}/"* "${dest_clef:?}/"* 2>/dev/null || true

  if [[ -d "${src_geth}" ]]; then
    cp -a "${src_geth}/." "${dest_geth}/"
  fi
  if [[ -d "${src_clef}" ]]; then
    cp -a "${src_clef}/." "${dest_clef}/"
  fi

  node_env_dir="${ROOT_DIR}/signer/${name}"
  node_env_file="${node_env_dir}/node.env"
  example_file="${node_env_dir}/node.env.example"
  mkdir -p "${node_env_dir}"
  if [[ ! -f "${node_env_file}" ]]; then
    if [[ -f "${example_file}" ]]; then
      cp "${example_file}" "${node_env_file}"
    else
      touch "${node_env_file}"
    fi
  fi

  password_src="${SRC_DIR}/config/passwords/signer${num}.pass"
  if [[ -f "${password_src}" ]]; then
    cp "${password_src}" "${CONFIG_DIR}/passwords/${name}.pass"
    signer_pass="$(tr -d '\n' < "${password_src}")"
    if grep -q '^SIGNER_PASSWORD=' "${node_env_file}" 2>/dev/null; then
      sed -i -E "s/^SIGNER_PASSWORD=.*/SIGNER_PASSWORD=${signer_pass}/" "${node_env_file}"
    else
      printf 'SIGNER_PASSWORD=%s\n' "${signer_pass}" >> "${node_env_file}"
    fi
  fi

  address_src="${SRC_DIR}/config/addresses/signer${num}.addr"
  if [[ -f "${address_src}" ]]; then
    cp "${address_src}" "${CONFIG_DIR}/addresses/${name}.addr"
  fi

  if [[ -f "${address_src}" ]]; then
    signer_addr="$(<"${address_src}")"
    if grep -q '^SIGNER_ADDRESS=' "${node_env_file}"; then
      sed -i -E "s/^SIGNER_ADDRESS=.*/SIGNER_ADDRESS=${signer_addr}/" "${node_env_file}"
    else
      printf 'SIGNER_ADDRESS=%s\n' "${signer_addr}" >> "${node_env_file}"
    fi
  fi

  if grep -q '^SIGNER_PASSWORD_FILE=' "${node_env_file}" 2>/dev/null; then
    sed -i -E "s|^SIGNER_PASSWORD_FILE=.*|SIGNER_PASSWORD_FILE=config/passwords/${name}.pass|" "${node_env_file}"
  else
    printf 'SIGNER_PASSWORD_FILE=%s\n' "config/passwords/${name}.pass" >> "${node_env_file}"
  fi

  if grep -q '^SIGNER_KEYSTORE_PATH=' "${node_env_file}" 2>/dev/null; then
    sed -i -E "s|^SIGNER_KEYSTORE_PATH=.*|SIGNER_KEYSTORE_PATH=artifacts/signer/${name}/volumes/geth/keystore|" "${node_env_file}"
  else
    printf 'SIGNER_KEYSTORE_PATH=%s\n' "artifacts/signer/${name}/volumes/geth/keystore" >> "${node_env_file}"
  fi

  if grep -q '^CLEF_MASTERSEED_PATH=' "${node_env_file}" 2>/dev/null; then
    sed -i -E "s|^CLEF_MASTERSEED_PATH=.*|CLEF_MASTERSEED_PATH=artifacts/signer/${name}/volumes/clef/masterseed.json|" "${node_env_file}"
  else
    printf 'CLEF_MASTERSEED_PATH=%s\n' "artifacts/signer/${name}/volumes/clef/masterseed.json" >> "${node_env_file}"
  fi

  public_ip_var="PUBLIC_IP_${name}"
  public_ip="${!public_ip_var:-0.0.0.0}"
  if grep -q '^PUBLIC_IP=' "${node_env_file}"; then
    sed -i -E "s/^PUBLIC_IP=.*/PUBLIC_IP=${public_ip}/" "${node_env_file}"
  else
    printf 'PUBLIC_IP=%s\n' "${public_ip}" >> "${node_env_file}"
  fi

  host_path_default="/var/lib/poa/${lower_name}"
  if ! grep -q '^HOST_DATA_PATH=' "${node_env_file}" 2>/dev/null; then
    printf 'HOST_DATA_PATH=%s\n' "${host_path_default}" >> "${node_env_file}"
  fi

  masterseed="${dest_clef}/masterseed.json"
  if [[ -f "${masterseed}" ]]; then
    chmod 400 "${masterseed}"
  fi
done

for idx in "${!NONSIGNER_NAMES[@]}"; do
  num=$((idx + 1))
  name="${NONSIGNER_NAMES[$idx]}"
  lower_name="$(echo "${name}" | tr '[:upper:]' '[:lower:]')"
  src_geth="${SRC_DIR}/data/nonsigner${num}"
  dest_geth="${ARTIFACTS_DIR}/nonsigner/${name}/volumes/geth"
  mkdir -p "${dest_geth}"
  rm -rf "${dest_geth:?}/"* 2>/dev/null || true

  if [[ -d "${src_geth}" ]]; then
    cp -a "${src_geth}/." "${dest_geth}/"
  fi

  password_src="${SRC_DIR}/config/passwords/nonsigner${num}.pass"
  if [[ -f "${password_src}" ]]; then
    cp "${password_src}" "${CONFIG_DIR}/passwords/${name}.pass"
  fi

  address_src="${SRC_DIR}/config/addresses/nonsigner${num}.addr"
  if [[ -f "${address_src}" ]]; then
    cp "${address_src}" "${CONFIG_DIR}/addresses/${name}.addr"
  fi

  node_env_dir="${ROOT_DIR}/nonsigner/${name}"
  node_env_file="${node_env_dir}/node.env"
  example_file="${node_env_dir}/node.env.example"
  mkdir -p "${node_env_dir}"
  if [[ ! -f "${node_env_file}" ]]; then
    if [[ -f "${example_file}" ]]; then
      cp "${example_file}" "${node_env_file}"
    else
      touch "${node_env_file}"
    fi
  fi

  public_ip_var="PUBLIC_IP_${name}"
  public_ip="${!public_ip_var:-0.0.0.0}"
  if grep -q '^PUBLIC_IP=' "${node_env_file}"; then
    sed -i -E "s/^PUBLIC_IP=.*/PUBLIC_IP=${public_ip}/" "${node_env_file}"
  else
    printf 'PUBLIC_IP=%s\n' "${public_ip}" >> "${node_env_file}"
  fi

  host_path_default="/var/lib/poa/${lower_name}"
  if ! grep -q '^HOST_DATA_PATH=' "${node_env_file}" 2>/dev/null; then
    printf 'HOST_DATA_PATH=%s\n' "${host_path_default}" >> "${node_env_file}"
  fi
done

echo "Artefak PoA berhasil disalin ke ${ROOT_DIR}."
