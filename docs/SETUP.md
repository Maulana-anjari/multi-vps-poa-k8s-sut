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
   - `BOOTNODE_ENODE` harus sudah berisi IP bootnode (di-update otomatis jika `PUBLIC_IP_UT` terisi).
   - Set `ETHSTATS_*` dan kredensial monitoring agar konsisten dengan stack observasi.
5. Gunakan `rsync` atau `scp` untuk menyalin subfolder `artifacts/signer/*` dan `artifacts/nonsigner/*` ke masing-masing VPS. Target direktori default berada di `/var/lib/poa/<node>/{geth,clef}` dan dapat diubah melalui `HOST_DATA_PATH` pada `signer/<KAMPUS>/node.env`.

## 2. Menyiapkan Cluster k3s (Ringkasan)
- Bentuk cluster k3s menggunakan panduan di `docs/k3s-setup.md`.
- Label setiap worker dengan `kubectl label node <hostname> poa-host=vps-a` dan seterusnya mengikuti tabel di `docs/cluster-layout.md`.
- Pastikan storage class `local-path` aktif (default k3s) atau sesuaikan `global.env` bila menggunakan storage class lain.

## 3. Sinkronisasi ke VPS-Caliper
Jika `git pull` di VPS-Caliper tidak menyertakan berkas yang di-ignore (mis. `global.env`, `config/ips.env`, artefak signer/nonsigner), gunakan skrip berikut dari mesin lokal:
```bash
rsync -avz multi-vps-poa-k8s/ user@<ip-vps-caliper>:/home/user/multi-vps-poa-k8s
```
Skrip akan membuat direktori target jika belum ada, lalu menyalin `global.env`, `config/ips.env`, `config/addresses/`, `config/passwords/`, seluruh `artifacts/`, serta manifest hasil render. Jalankan ulang setiap kali artefak berubah sebelum men-deploy dari VPS-Caliper.

## 4. Sinkronisasi artefak ke VPS pekerja
Setelah manifest terdeploy, salin data signer dan nonsigner ke hostPath masing-masing VPS. Cara paling mudah:
```bash
# sinkron seluruh signer & nonsigner
./scripts/sync-host-artifacts.sh

# atau target tertentu saja
SUDO_PASSWORD='*******' ./scripts/sync-host-artifacts.sh UGM ITB UI UNIMED
```
Skrip akan:
1. Menghapus direktori lama (`/var/lib/poa/<node>/clef` dan/atau `/var/lib/poa/<node>/geth`).
2. Membuat ulang direktori dengan kepemilikan user SSH (`REMOTE_USER`, default `maul`).
3. Menyalin data dari `artifacts/signer/<NODE>/volumes/{clef,geth}/` atau `artifacts/nonsigner/<NODE>/volumes/geth/`.
4. Mengembalikan kepemilikan ke root serta mengatur izin `masterseed.json` (`chmod 400`).

Jika memilih manual, jalankan perintah `ssh` + `rsync` seperti pada `script setup k3s pos.txt`, lalu pastikan direktori akhir dimiliki root sebelum pod berjalan.

## 5. Deployment di Kubernetes
1. Pastikan kubeconfig cluster aktif (`kubectl config current-context`).
2. Jalankan `./scripts/deploy.sh`. Opsi yang tersedia:
   - `--skip-artifacts` jika artefak sudah siap dan tidak ingin menyalin ulang.
   - `--skip-secrets` bila tidak ingin men-generate ulang secret password.
   - `./scripts/deploy.sh --skip-artifacts --skip-secrets`
3. Script akan:
   - Membuat namespace (`K8S_NAMESPACE` di `global.env`) bila belum ada.
   - Mengapply `ConfigMap` (`poa-shared-config`) dan secret password (`poa-geth-passwords`).
   - Mengapply StatefulSet + Service untuk seluruh signer dan nonsigner berdasarkan file `node.env`.
4. Untuk hanya menyalakan node tertentu
   a. Apply hanya manifest yang diperlukan
   Pastikan ConfigMap dan secret di apply
   ```bash
   ./scripts/render-secrets.sh
   kubectl apply -f manifests/shared/secrets.generated.yaml
   kubectl get secret poa-geth-passwords -n default
   
   ./scripts/render-manifests.sh
   kubectl apply -f manifests/dist/shared/configmap.yaml
   kubectl get configmap poa-shared-config -n default
   ```
   ```bash
   kubectl apply -f manifests/dist/signer/ugm.yaml
   kubectl apply -f manifests/dist/signer/itb.yaml
   kubectl apply -f manifests/dist/signer/ui.yaml
   kubectl apply -f manifests/dist/nonsigner/unimed.yaml
   ```

   b. Scale statefulset target, sisanya biarkan 0
   Jalankan ./scripts/deploy.sh --skip-artifacts, lalu matikan node yang tidak dibutuhkan:
   ```bash
   kubectl scale statefulset/poa-signer-itb -n default --replicas=0
   kubectl scale statefulset/poa-nonsigner-unud -n default --replicas=0
   ```
5. Pantau status pod:
   ```bash
   kubectl get pods -n default
   kubectl get pods -n default -o wide
   kubectl logs -n default statefulset/poa-signer-ugm -c geth --tail=200
   kubectl logs -n default statefulset/poa-signer-ui -c geth --tail=200
   kubectl logs -n default statefulset/poa-signer-ui -c geth --tail=200
   kubectl logs -n default statefulset/poa-signer-ub -c geth --tail=200
   kubectl logs -n default statefulset/poa-signer-its -c geth --tail=200

   kubectl logs -n default statefulset/poa-nonsigner-unimed -c geth --tail=200

   # restart
   kubectl rollout restart statefulset/poa-nonsigner-unimed -n default
   kubectl rollout restart statefulset/poa-signer-ugm -n default
   kubectl rollout restart statefulset/poa-signer-itb -n default
   kubectl rollout restart statefulset/poa-signer-ui -n default

   kubectl logs poa-signer-ugm-0 -c clef -n default --tail=200
   kubectl logs poa-signer-itb-0 -c clef -n default --tail=200
   kubectl logs poa-signer-ui-0 -c clef -n default --tail=200
   kubectl logs poa-signer-ub-0 -c clef -n default --tail=200
   kubectl logs poa-signer-its-0 -c clef -n default --tail=200
   ```
6. Cek event pod untuk konfirmasi node dan volume tersambung:
   ```bash
   kubectl describe pod poa-signer-ugm-0 -n default
   kubectl describe pod poa-signer-itb-0 -n default
   kubectl describe pod poa-signer-ui-0 -n default
   kubectl describe pod poa-signer-ub-0 -n default
   kubectl describe pod poa-signer-its-0 -n default

   kubectl describe pod poa-nonsigner-unimed-0 -n default
   kubectl describe pod poa-nonsigner-unud-0 -n default
   kubectl describe pod poa-nonsigner-gundar-0 -n default
   kubectl describe pod poa-nonsigner-ut-0 -n default
   kubectl describe pod poa-nonsigner-undip-0 -n default
   ```
7. Cek peers tiap pod
   ```bash
   kubectl exec -it poa-signer-ugm-0 -n default -c geth -- geth attach /root/.ethereum/geth.ipc

   kubectl exec -it poa-signer-itb-0 -n default -c geth -- geth attach /root/.ethereum/geth.ipc

   kubectl exec -it poa-signer-ui-0 -n default -c geth -- geth attach /root/.ethereum/geth.ipc

   kubectl exec -it poa-nonsigner-unimed-0 -n default -c geth -- geth attach /root/.ethereum/geth.ipc

   # Di console yang muncul:

   net.peerCount
   admin.peers
   ```

## 6. Operasi Rutin
- **Rollout ulang**: jalankan `kubectl rollout restart statefulset/poa-signer-ugm -n default`.
- **Update IP**: ubah `config/ips.env`, jalankan `prepare-artifacts.sh` agar `node.env` ter-update, lalu `scripts/render-manifests.sh` dan `kubectl apply`.
- **Penonaktifan**: gunakan `./scripts/destroy.sh` `--keep-namespace` bila ingin mempertahankan namespace).

## 7. Checklist Pasca Deploy
- Semua pod `Ready`.
- `kubectl get svc -n $K8S_NAMESPACE` menampilkan setiap signer/nonsigner dengan port HTTP/WS/p2p.
- RPC signer dapat diakses (contoh: `kubectl port-forward service/poa-signer-ugm 8545:8545` lalu `eth_blockNumber`).
- Ethstats menampilkan seluruh node dengan status online.
- Monitoring (InfluxDB/Prometheus) menerima metrik baru.
