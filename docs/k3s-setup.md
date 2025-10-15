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
3. **Akses Kubectl**
  ```
  mkdir -p ~/.kube
  sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
  sudo chown "$(id -u):$(id -g)" ~/.kube/config
  export KUBECONFIG=$HOME/.kube/config
  ```

4. **Verifikasi**  
   Edit ~/.kube/config and change the server line so it uses the same IP/DNS you passed to --tls-san, e.g.:
    server: https://<ip-control-plane>:6443    # replace with your control-plane IP or hostname
   ```bash
   kubectl get nodes -o wide
   ```

## 3. Label & Taint
```
kubectl label node <hostname-vps-a> poa-host=vps-a --overwrite
kubectl label node <hostname-vps-b> poa-host=vps-b --overwrite
kubectl label node <hostname-vps-c> poa-host=vps-c --overwrite
kubectl label node <hostname-vps-d> poa-host=vps-d --overwrite
kubectl label node <hostname-vps-e> poa-host=vps-e --overwrite
```

Tambahkan toleration/taint bila dibutuhkan (mis. memisahkan monitoring). Untuk PoA standar cukup menggunakan label selector.

## 4. Persiapan Storage
- `local-path` (default k3s) sudah memadai untuk PVC kecil, namun PoA membutuhkan data besar. Gunakan `hostPath` pada manifest (sudah dihasilkan otomatis) dan pastikan direktori `/var/lib/poa/<node>` tersedia di masing-masing worker.
- Salin folder `artifacts/signer/<KAMPUS>/volumes` dan `artifacts/nonsigner/<KAMPUS>/volumes` ke worker yang bersangkutan sebelum menjalankan pod. Jika login root dinonaktifkan (`PermitRootLogin no`), gunakan user biasa (`maul`) dan jalankan rsync dengan bantuan sudo di sisi remote:
  ```bash
  # contoh untuk signer UGM di VPS-A
  ssh -t maul@<ip-vps-a> "sudo mkdir -p /var/lib/poa/ugm && sudo chown maul:maul /var/lib/poa/ugm"
  rsync -avz artifacts/signer/UGM/ maul@<ip-vps-a>:/var/lib/poa/ugm

  # nonsigner UNIMED di VPS-A
  ssh -t maul@<ip-vps-a> "sudo mkdir -p /var/lib/poa/unimed && sudo chown maul:maul /var/lib/poa/unimed"
  rsync -avz --rsync-path="sudo rsync" artifacts/nonsigner/UNIMED/ maul@<ip-vps-a>:/var/lib/poa/unimed
  ```

## 5. Monitoring & Firewall
- Buka port minimal: `6443/tcp`, `8472/udp`, `10250/tcp`, port RPC/WS/p2p PoA (`30303-30304`, `8545-8546`), serta port monitoring (`3000`, `9090`, `9091`).
- Aktifkan `kubectl top nodes/pods` dengan memasang Metrics Server jika belum ada:
  ```bash
  kubectl get deployment metrics-server -n kube-system
  # jika output "NotFound", instal:
  kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/high-availability.yaml
  ```
  Setelah rollout selesai:
  ```bash
  kubectl wait --for=condition=available deployment/metrics-server -n kube-system --timeout=120s
  atau
  kubectl get deployment metrics-server -n kube-system
  lalu
  kubectl top nodes
  kubectl top pods -A | head
  ```
  Bila muncul error TLS (`x509: certificate signed by unknown authority`), tambahkan args ini ke deployment:
  ```bash
  kubectl patch deployment metrics-server -n kube-system \
    --type='json' \
    -p='[{"op":"add","path":"/spec/template/spec/containers/0/args","value":["--kubelet-insecure-tls","--kubelet-preferred-address-types=InternalIP,Hostname,ExternalIP"]}]'
  kubectl rollout restart deployment metrics-server -n kube-system
  ```
  (Sesuaikan flag dengan kebijakan keamanan internal; untuk produksi lebih baik memasang sertifikat valid pada kubelet.)

## 6. Backup & Pemeliharaan
- Simpan salinan `node-token`, kubeconfig, dan `artifacts/` di repositori privat.
- Untuk upgrade k3s:
  ```bash
  sudo systemctl stop k3s
  curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION="v1.34.x+k3s1" sh -
  ```
  Lakukan rolling upgrade worker satu per satu agar validator tidak mati bersamaan.

## Allow firewall
```bash
sudo ufw allow 22/tcp
sudo ufw allow 30303/tcp
sudo ufw allow 30303/udp
sudo ufw allow 31303/tcp
sudo ufw allow 31303/udp
sudo ufw allow 8545/tcp
sudo ufw allow 8546/tcp
sudo ufw allow 8557/tcp
sudo ufw allow 8558/tcp
sudo ufw allow 8559/tcp
sudo ufw allow 8560/tcp
sudo ufw allow 8561/tcp
sudo ufw allow 8562/tcp
sudo ufw allow 8551/tcp
sudo ufw allow 9551/tcp
sudo ufw allow 8085/tcp
sudo ufw allow 8086/tcp
sudo ufw allow 9090/tcp
sudo ufw allow 9091/tcp
sudo ufw reload
```