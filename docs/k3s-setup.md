# K3s Setup untuk PoA

Panduan ini meringkas langkah menyiapkan cluster k3s lima VPS mengikuti pola pada `blockchain-pos-geth/docs/pos-kurtosis-k8s.md`, namun disederhanakan untuk kebutuhan PoA.

## 1. Topologi yang Direkomendasikan

| VPS | Label `poa-host` | Validator | Nonsigner |
|-----|-----------------|-----------|-----------|
| VPS-A | vps-a | UGM | UNIMED |
| VPS-B | vps-b | ITB | UNUD |
| VPS-C | vps-c | UI | Gundar |
| VPS-D | vps-d | UB | UT |
| VPS-E | vps-e | ITS | UNDIP |

> VPS-Caliper tetap bertindak sebagai control plane + workstation `kubectl`. Worker k3s direkomendasikan hanya menjalankan pod PoA.

## 2. Instalasi k3s
1. **Control Plane (VPS-Caliper)**  
   ```bash
   curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION="v1.33.4+k3s1" sh -s - \
     --write-kubeconfig-mode 644 \
     --tls-san <ip-control-plane> \
     --cluster-cidr 10.42.0.0/16 \
     --service-cidr 10.43.0.0/16

   sudo cat /var/lib/rancher/k3s/server/node-token
   ```
   Simpan `node-token` untuk proses join worker.

2. **Worker (VPS-A…E)**  
   ```bash
   export K3S_URL="https://<ip-control-plane>:6443"
   export K3S_TOKEN="<node-token>"
   curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION="v1.33.4+k3s1" K3S_URL=$K3S_URL K3S_TOKEN=$K3S_TOKEN sh -
   ```

3. **Verifikasi**  
   ```bash
   kubectl get nodes -o wide
   ```
   Pastikan seluruh worker berstatus `Ready`.

## 3. Label & Taint
```
kubectl label node <hostname-vps-a> poa-host=vps-a --overwrite
kubectl label node <hostname-vps-b> poa-host=vps-b --overwrite
...
kubectl label node <hostname-vps-e> poa-host=vps-e --overwrite
```

Tambahkan toleration/taint bila dibutuhkan (mis. memisahkan monitoring). Untuk PoA standar cukup menggunakan label selector.

## 4. Persiapan Storage
- `local-path` (default k3s) sudah memadai untuk PVC kecil, namun PoA membutuhkan data besar. Gunakan `hostPath` pada manifest (sudah dihasilkan otomatis) dan pastikan direktori `/var/lib/poa/<node>` tersedia di masing-masing worker.
- Salin folder `artifacts/signer/<KAMPUS>/volumes` dan `artifacts/nonsigner/<KAMPUS>/volumes` ke worker yang bersangkutan sebelum menjalankan pod:
  ```bash
  rsync -avz artifacts/signer/UGM/ root@<ip-vps-a>:/var/lib/poa/ugm
  ```

## 5. Akses Kubectl
```
mkdir -p ~/.kube
sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
sudo chown "$(id -u):$(id -g)" ~/.kube/config
export KUBECONFIG=$HOME/.kube/config
```

## 6. Hak Akses
Setelah `kurtosis engine start` (jika masih digunakan), buat ulang binding admin:
```
kubectl delete clusterrolebinding kurtosis-engine-admin --ignore-not-found
kubectl create clusterrolebinding kurtosis-engine-admin \
  --clusterrole=cluster-admin \
  --serviceaccount=<namespace-engine>:<service-account-engine>
```

## 7. Monitoring & Firewall
- Buka port minimal: `6443/tcp`, `8472/udp`, `10250/tcp`, port RPC/WS/p2p PoA (`30303-30304`, `8545-8546`), serta port monitoring (`3000`, `9090`, `9091`).
- Aktifkan `kubectl top nodes` dengan menginstal `metrics-server` bila dibutuhkan (`kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/high-availability.yaml`).

## 8. Backup & Pemeliharaan
- Simpan salinan `node-token`, kubeconfig, dan `artifacts/` di repositori privat.
- Untuk upgrade k3s:
  ```bash
  sudo systemctl stop k3s
  curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION="v1.34.x+k3s1" sh -
  ```
  Lakukan rolling upgrade worker satu per satu agar validator tidak mati bersamaan.
