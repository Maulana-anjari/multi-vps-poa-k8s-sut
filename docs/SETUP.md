# Setup PoA di k3s

Dokumen ini merangkum urutan kerja untuk menjalankan jaringan Ethereum PoA dengan artefak dari `blockchain-poa-geth` di atas cluster k3s. Ikuti langkah berurutan agar data genesis, akun signer, serta konfigurasi jaringan konsisten di seluruh VPS.

## 1. Persiapan Artefak Lokal
1. Jalankan `NETWORK_TYPE=PoA ./start-network.sh` dari direktori `blockchain-poa-geth`. Masukkan password ketika diminta hingga jaringan lokal selesai sinkron.
2. Pindah ke folder ini (`multi-vps-poa-k8s`) dan jalankan:
   ```bash
   ./scripts/prepare-artifacts.sh
   ./scripts/render-secrets.sh
   ./scripts/render-manifests.sh
   ```
   Perintah pertama menyalin `genesis.json`, `rules.js`, password, keystore, dan masterseed ke struktur `artifacts/`. Password signer otomatis disalin ke `signer/<KAMPUS>/node.env`.
3. Edit `config/ips.env` dengan IP publik terbaru setiap node. Jalankan ulang `prepare-artifacts.sh` jika nilai IP berubah.
4. Sesuaikan `global.env` (salinan dari `global.env.example`):
   - `BOOTNODE_ENODE` harus sudah berisi IP bootnode (di-update otomatis jika `PUBLIC_IP_UNIMED` terisi).
   - Set `ETHSTATS_*` dan kredensial monitoring agar konsisten dengan stack observasi.
5. Gunakan `rsync` atau `scp` untuk menyalin subfolder `artifacts/signer/*` dan `artifacts/nonsigner/*` ke masing-masing VPS. Target direktori default berada di `/var/lib/poa/<node>/{geth,clef}` dan dapat diubah melalui `HOST_DATA_PATH` pada `signer/<KAMPUS>/node.env`.

## 2. Menyiapkan Cluster k3s (Ringkasan)
- Bentuk cluster k3s menggunakan panduan di `docs/k3s-setup.md`.
- Label setiap worker dengan `kubectl label node <hostname> poa-host=vps-a` dan seterusnya mengikuti tabel di `docs/cluster-layout.md`.
- Pastikan storage class `local-path` aktif (default k3s) atau sesuaikan `global.env` bila menggunakan storage class lain.

## 3. Deployment di Kubernetes
1. Pastikan kubeconfig cluster aktif (`kubectl config current-context`).
2. Jalankan `./scripts/deploy.sh`. Opsi yang tersedia:
   - `--skip-artifacts` jika artefak sudah siap dan tidak ingin menyalin ulang.
   - `--skip-secrets` bila tidak ingin men-generate ulang secret password.
3. Script akan:
   - Membuat namespace (`K8S_NAMESPACE` di `global.env`) bila belum ada.
   - Mengapply `ConfigMap` (`poa-shared-config`) dan secret password (`poa-geth-passwords`).
   - Mengapply StatefulSet + Service untuk seluruh signer dan nonsigner berdasarkan file `node.env`.
4. Pantau status pod:
   ```bash
   kubectl get pods -n $K8S_NAMESPACE
   kubectl logs -n $K8S_NAMESPACE statefulset/poa-signer-ugm -c geth
   ```

## 4. Operasi Rutin
- **Rollout ulang**: jalankan `kubectl rollout restart statefulset/poa-signer-ugm -n $K8S_NAMESPACE`.
- **Update IP**: ubah `config/ips.env`, jalankan `prepare-artifacts.sh` agar `node.env` ter-update, lalu `scripts/render-manifests.sh` dan `kubectl apply`.
- **Penonaktifan**: gunakan `./scripts/destroy.sh` (`--keep-namespace` bila ingin mempertahankan namespace).

## 5. Checklist Pasca Deploy
- Semua pod `Ready`.
- `kubectl get svc -n $K8S_NAMESPACE` menampilkan setiap signer/nonsigner dengan port HTTP/WS/p2p.
- RPC signer dapat diakses (contoh: `kubectl port-forward service/poa-signer-ugm 8545:8545` lalu `eth_blockNumber`).
- Ethstats menampilkan seluruh node dengan status online.
- Monitoring (InfluxDB/Prometheus) menerima metrik baru.
