#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
CONFIG_DIR="${ROOT_DIR}/config"
MANIFEST_DIR="${ROOT_DIR}/manifests"
DIST_DIR="${MANIFEST_DIR}/dist"
SHARED_DIST="${DIST_DIR}/shared"
SIGNER_DIST="${DIST_DIR}/signer"
NONSIGNER_DIST="${DIST_DIR}/nonsigner"

GLOBAL_ENV="${ROOT_DIR}/global.env"

if [[ ! -f "${GLOBAL_ENV}" ]]; then
  echo "File global.env tidak ditemukan di ${ROOT_DIR}. Salin dari global.env.example dan isi nilainya." >&2
  exit 1
fi

mkdir -p "${SHARED_DIST}" "${SIGNER_DIST}" "${NONSIGNER_DIST}"

rm -f "${SHARED_DIST}"/*.yaml "${SIGNER_DIST}"/*.yaml "${NONSIGNER_DIST}"/*.yaml

set -a
# shellcheck source=/dev/null
source "${GLOBAL_ENV}"
set +a

K8S_NAMESPACE="${K8S_NAMESPACE:-poa-mainnet}"
K8S_PULL_POLICY="${K8S_PULL_POLICY:-IfNotPresent}"
K8S_SERVICE_ACCOUNT="${K8S_SERVICE_ACCOUNT:-default}"
GETH_IMAGE="${GETH_IMAGE:-ethereum/client-go:v1.13.15}"
CLEF_IMAGE="${CLEF_IMAGE:-ethereum/client-go:alltools-v1.13.15}"

indent_file() {
  sed 's/^/    /'
}

generate_shared_configmap() {
  local output="${SHARED_DIST}/configmap.yaml"
  {
    echo "apiVersion: v1"
    echo "kind: ConfigMap"
    echo "metadata:"
    echo "  name: poa-shared-config"
    echo "  namespace: ${K8S_NAMESPACE}"
    echo "data:"
    if [[ -f "${CONFIG_DIR}/genesis.json" ]]; then
      echo "  genesis.json: |"
      indent_file < "${CONFIG_DIR}/genesis.json"
    fi
    if [[ -f "${CONFIG_DIR}/rules.js" ]]; then
      echo "  rules.js: |"
      indent_file < "${CONFIG_DIR}/rules.js"
    fi
    if [[ -f "${CONFIG_DIR}/static-nodes.json" ]]; then
      echo "  static-nodes.json: |"
      indent_file < "${CONFIG_DIR}/static-nodes.json"
    fi
  } > "${output}"
  echo "ConfigMap ditulis ke ${output}"
}

render_signer_manifest() {
  local name="$1"
  local node_dir="${ROOT_DIR}/signer/${name}"
  local env_file="${node_dir}/node.env"
  [[ -f "${env_file}" ]] || return 0

  (
    set -a
    # shellcheck source=/dev/null
    source "${GLOBAL_ENV}"
    # shellcheck source=/dev/null
    source "${env_file}"
    set +a

    local selector_key=""
    local selector_value=""
    if [[ -n "${K8S_NODE_SELECTOR:-}" ]] && [[ "${K8S_NODE_SELECTOR}" == *"="* ]]; then
      selector_key="${K8S_NODE_SELECTOR%%=*}"
      selector_value="${K8S_NODE_SELECTOR#*=}"
    fi

    local host_base="${HOST_DATA_PATH:-/var/lib/poa/${NODE_NAME}}"
    local geth_host="${host_base}/geth"
    local clef_host="${host_base}/clef"
    local secrets_name="poa-geth-passwords"
    local static_nodes_exists="false"
    if [[ -f "${CONFIG_DIR}/static-nodes.json" ]]; then
      static_nodes_exists="true"
    fi

    local service_type="${K8S_SERVICE_TYPE:-ClusterIP}"

    local output="${SIGNER_DIST}/${NODE_NAME}.yaml"
    {
      cat <<EOF
apiVersion: v1
kind: Service
metadata:
  name: poa-signer-${NODE_NAME}
  namespace: ${K8S_NAMESPACE}
spec:
  selector:
    app: poa-signer
    node: ${NODE_NAME}
  ports:
    - name: http
      protocol: TCP
      port: ${HTTP_PORT:-8545}
      targetPort: ${HTTP_PORT:-8545}
    - name: ws
      protocol: TCP
      port: ${WS_PORT:-8546}
      targetPort: ${WS_PORT:-8546}
    - name: p2p-tcp
      protocol: TCP
      port: ${P2P_PORT:-30303}
      targetPort: ${P2P_PORT:-30303}
    - name: p2p-udp
      protocol: UDP
      port: ${P2P_PORT:-30303}
      targetPort: ${P2P_PORT:-30303}
  type: ${service_type}
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: poa-signer-${NODE_NAME}
  namespace: ${K8S_NAMESPACE}
spec:
  serviceName: poa-signer-${NODE_NAME}
  replicas: 1
  selector:
    matchLabels:
      app: poa-signer
      node: ${NODE_NAME}
  template:
    metadata:
      labels:
        app: poa-signer
        node: ${NODE_NAME}
    spec:
      serviceAccountName: ${K8S_SERVICE_ACCOUNT}
EOF
      if [[ -n "${selector_key}" && -n "${selector_value}" ]]; then
        cat <<EOF
      nodeSelector:
        ${selector_key}: ${selector_value}
EOF
      fi
      cat <<EOF
      containers:
        - name: clef
          image: ${CLEF_IMAGE}
          imagePullPolicy: ${K8S_PULL_POLICY}
          env:
            - name: NETWORK_ID
              value: "${NETWORK_ID}"
            - name: CLEF_MASTER_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: ${secrets_name}
                  key: ${name}.pass
          volumeMounts:
            - name: clef-data
              mountPath: /root/.clef
            - name: geth-keystore
              mountPath: /root/.ethereum/keystore
              readOnly: true
            - name: rules-config
              mountPath: /root/rules.js
              subPath: rules.js
        - name: geth
          image: ${GETH_IMAGE}
          imagePullPolicy: ${K8S_PULL_POLICY}
          command: ["geth"]
          args:
            - --datadir
            - /root/.ethereum
            - --networkid
            - "${NETWORK_ID}"
            - --syncmode
            - full
            - --port
            - "${P2P_PORT:-30303}"
            - --http
            - --http.addr
            - 0.0.0.0
            - --http.port
            - "${HTTP_PORT:-8545}"
            - --http.api
            - eth,net,web3,clique,admin,personal
            - --http.corsdomain
            - "*"
            - --http.vhosts
            - "*"
            - --ws
            - --ws.addr
            - 0.0.0.0
            - --ws.port
            - "${WS_PORT:-8546}"
            - --ws.api
            - eth,net,web3,clique,admin,personal
            - --ws.origins
            - "*"
            - --bootnodes
            - "${BOOTNODE_ENODE}"
            - --signer
            - http://127.0.0.1:8550
            - --mine
            - --miner.etherbase
            - "${SIGNER_ADDRESS}"
            - --nat
            - "extip:${PUBLIC_IP}"
            - --ethstats
            - "${ETHSTATS_ID}:${ETHSTATS_WS_SECRET}@${ETHSTATS_ENDPOINT}"
            - --metrics
            - --metrics.expensive
            - --metrics.influxdb
            - --metrics.influxdb.endpoint
            - "${INFLUXDB_HTTP_URI}"
            - --metrics.influxdb.database
            - "${INFLUXDB_DB}"
            - --metrics.influxdb.username
            - "${INFLUXDB_USER}"
            - --metrics.influxdb.password
            - "${INFLUXDB_PASSWORD}"
            - --miner.gasprice
            - "1"
          ports:
            - name: http
              containerPort: ${HTTP_PORT:-8545}
              protocol: TCP
            - name: ws
              containerPort: ${WS_PORT:-8546}
              protocol: TCP
            - name: p2p-tcp
              containerPort: ${P2P_PORT:-30303}
              protocol: TCP
            - name: p2p-udp
              containerPort: ${P2P_PORT:-30303}
              protocol: UDP
          volumeMounts:
            - name: geth-data
              mountPath: /root/.ethereum
            - name: genesis-config
              mountPath: /config/genesis.json
              subPath: genesis.json
EOF
      if [[ "${static_nodes_exists}" == "true" ]]; then
        cat <<'EOF'
            - name: static-nodes
              mountPath: /root/.ethereum/static-nodes.json
              subPath: static-nodes.json
EOF
      fi
      cat <<EOF
      volumes:
        - name: clef-data
          hostPath:
            path: ${clef_host}
            type: DirectoryOrCreate
        - name: geth-keystore
          hostPath:
            path: ${geth_host}/keystore
            type: DirectoryOrCreate
        - name: geth-data
          hostPath:
            path: ${geth_host}
            type: DirectoryOrCreate
        - name: rules-config
          configMap:
            name: poa-shared-config
            items:
              - key: rules.js
                path: rules.js
        - name: genesis-config
          configMap:
            name: poa-shared-config
            items:
              - key: genesis.json
                path: genesis.json
EOF
      if [[ "${static_nodes_exists}" == "true" ]]; then
        cat <<'EOF'
        - name: static-nodes
          configMap:
            name: poa-shared-config
            items:
              - key: static-nodes.json
                path: static-nodes.json
EOF
      fi
      cat <<EOF
EOF
      cat <<'EOF'
      tolerations: []
    volumeClaimTemplates: []
EOF
    } > "${output}"
    echo "Manifest signer ditulis ke ${output}"
  )
}

render_nonsigner_manifest() {
  local name="$1"
  local node_dir="${ROOT_DIR}/nonsigner/${name}"
  local env_file="${node_dir}/node.env"
  [[ -f "${env_file}" ]] || return 0

  (
    set -a
    # shellcheck source=/dev/null
    source "${GLOBAL_ENV}"
    # shellcheck source=/dev/null
    source "${env_file}"
    set +a

    local selector_key=""
    local selector_value=""
    if [[ -n "${K8S_NODE_SELECTOR:-}" ]] && [[ "${K8S_NODE_SELECTOR}" == *"="* ]]; then
      selector_key="${K8S_NODE_SELECTOR%%=*}"
      selector_value="${K8S_NODE_SELECTOR#*=}"
    fi

    local host_base="${HOST_DATA_PATH:-/var/lib/poa/${NODE_NAME}}"
    local geth_host="${host_base}/geth"
    local static_nodes_exists="false"
    if [[ -f "${CONFIG_DIR}/static-nodes.json" ]]; then
      static_nodes_exists="true"
    fi
    local service_type="${K8S_SERVICE_TYPE:-ClusterIP}"

    local output="${NONSIGNER_DIST}/${NODE_NAME}.yaml"
    {
      cat <<EOF
apiVersion: v1
kind: Service
metadata:
  name: poa-nonsigner-${NODE_NAME}
  namespace: ${K8S_NAMESPACE}
spec:
  selector:
    app: poa-nonsigner
    node: ${NODE_NAME}
  ports:
    - name: http
      protocol: TCP
      port: ${HTTP_PORT:-8545}
      targetPort: ${HTTP_PORT:-8545}
    - name: ws
      protocol: TCP
      port: ${WS_PORT:-8546}
      targetPort: ${WS_PORT:-8546}
    - name: p2p-tcp
      protocol: TCP
      port: ${P2P_PORT:-30303}
      targetPort: ${P2P_PORT:-30303}
    - name: p2p-udp
      protocol: UDP
      port: ${P2P_PORT:-30303}
      targetPort: ${P2P_PORT:-30303}
  type: ${service_type}
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: poa-nonsigner-${NODE_NAME}
  namespace: ${K8S_NAMESPACE}
spec:
  serviceName: poa-nonsigner-${NODE_NAME}
  replicas: 1
  selector:
    matchLabels:
      app: poa-nonsigner
      node: ${NODE_NAME}
  template:
    metadata:
      labels:
        app: poa-nonsigner
        node: ${NODE_NAME}
    spec:
      serviceAccountName: ${K8S_SERVICE_ACCOUNT}
EOF
      if [[ -n "${selector_key}" && -n "${selector_value}" ]]; then
        cat <<EOF
      nodeSelector:
        ${selector_key}: ${selector_value}
EOF
      fi
      cat <<EOF
      containers:
        - name: geth
          image: ${GETH_IMAGE}
          imagePullPolicy: ${K8S_PULL_POLICY}
          command: ["geth"]
          args:
            - --datadir
            - /root/.ethereum
            - --networkid
            - "${NETWORK_ID}"
            - --syncmode
            - full
            - --gcmode
            - archive
            - --port
            - "${P2P_PORT:-30303}"
            - --http
            - --http.addr
            - 0.0.0.0
            - --http.port
            - "${HTTP_PORT:-8545}"
            - --http.api
            - eth,net,web3,clique,admin,personal
            - --http.corsdomain
            - "*"
            - --http.vhosts
            - "*"
            - --ws
            - --ws.addr
            - 0.0.0.0
            - --ws.port
            - "${WS_PORT:-8546}"
            - --ws.api
            - eth,net,web3,clique,admin,personal
            - --ws.origins
            - "*"
            - --bootnodes
            - "${BOOTNODE_ENODE}"
            - --nat
            - "extip:${PUBLIC_IP}"
            - --ethstats
            - "${ETHSTATS_ID}:${ETHSTATS_WS_SECRET}@${ETHSTATS_ENDPOINT}"
            - --metrics
            - --metrics.expensive
            - --metrics.influxdb
            - --metrics.influxdb.endpoint
            - "${INFLUXDB_HTTP_URI}"
            - --metrics.influxdb.database
            - "${INFLUXDB_DB}"
            - --metrics.influxdb.username
            - "${INFLUXDB_USER}"
            - --metrics.influxdb.password
            - "${INFLUXDB_PASSWORD}"
            - --miner.gasprice
            - "1"
          ports:
            - name: http
              containerPort: ${HTTP_PORT:-8545}
              protocol: TCP
            - name: ws
              containerPort: ${WS_PORT:-8546}
              protocol: TCP
            - name: p2p-tcp
              containerPort: ${P2P_PORT:-30303}
              protocol: TCP
            - name: p2p-udp
              containerPort: ${P2P_PORT:-30303}
              protocol: UDP
          volumeMounts:
            - name: geth-data
              mountPath: /root/.ethereum
            - name: genesis-config
              mountPath: /config/genesis.json
              subPath: genesis.json
EOF
      if [[ "${static_nodes_exists}" == "true" ]]; then
        cat <<'EOF'
            - name: static-nodes
              mountPath: /root/.ethereum/static-nodes.json
              subPath: static-nodes.json
EOF
      fi
      cat <<EOF
      volumes:
        - name: geth-data
          hostPath:
            path: ${geth_host}
            type: DirectoryOrCreate
        - name: genesis-config
          configMap:
            name: poa-shared-config
            items:
              - key: genesis.json
                path: genesis.json
EOF
      if [[ "${static_nodes_exists}" == "true" ]]; then
        cat <<'EOF'
        - name: static-nodes
          configMap:
            name: poa-shared-config
            items:
              - key: static-nodes.json
                path: static-nodes.json
EOF
      fi
      cat <<'EOF'
      tolerations: []
    volumeClaimTemplates: []
EOF
    } > "${output}"
    echo "Manifest nonsigner ditulis ke ${output}"
  )
}

generate_shared_configmap

for dir in "${ROOT_DIR}/signer"/*/; do
  [[ -d "${dir}" ]] || continue
  name="$(basename "${dir}")"
  render_signer_manifest "${name}"
done

for dir in "${ROOT_DIR}/nonsigner"/*/; do
  [[ -d "${dir}" ]] || continue
  name="$(basename "${dir}")"
  render_nonsigner_manifest "${name}"
done

echo "Render manifest selesai. Periksa direktori ${DIST_DIR}."
