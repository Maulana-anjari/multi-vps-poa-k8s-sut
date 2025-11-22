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

## 2. Menyiapkan Cluster k3s (Ringkasan)
- Bentuk cluster k3s menggunakan panduan di `docs/k3s-setup.md`.
- Label setiap worker dengan `kubectl label node <hostname> poa-host=vps-a` dan seterusnya mengikuti tabel di `docs/cluster-layout.md`.
- Pastikan storage class `local-path` aktif (default k3s) atau sesuaikan `global.env` bila menggunakan storage class lain.

## 3. Sinkronisasi ke VPS-Caliper
Jika `git pull` di VPS-Caliper tidak menyertakan berkas yang di-ignore (mis. `global.env`, `config/ips.env`, artefak signer/nonsigner), gunakan skrip berikut dari mesin lokal:
```bash
rsync -avz multi-vps-poa-k8s/ user@<ip-vps-caliper>:/home/user/multi-vps-poa-k8s
rsync -avz multi-vps-poa-k8s/ maul@77.237.244.170:/home/maul/multi-vps-poa-k8s
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
   kubectl scale statefulset/poa-signer-ugm -n default --replicas=0
   kubectl scale statefulset/poa-signer-itb -n default --replicas=0
   kubectl scale statefulset/poa-signer-ui -n default --replicas=0
   kubectl scale statefulset/poa-nonsigner-unimed -n default --replicas=0

   kubectl scale statefulset/poa-signer-ub -n default --replicas=0
   kubectl scale statefulset/poa-signer-its -n default --replicas=0
   kubectl scale statefulset/poa-nonsigner-ut -n default --replicas=0
   kubectl scale statefulset/poa-nonsigner-unud -n default --replicas=0
   kubectl scale statefulset/poa-nonsigner-undip -n default --replicas=0
   kubectl scale statefulset/poa-nonsigner-gundar -n default --replicas=0

   # hidupkan lagi
   kubectl scale statefulset/poa-nonsigner-ut -n default --replicas=1
   kubectl scale statefulset/poa-nonsigner-unud -n default --replicas=1

   kubectl scale statefulset/poa-signer-ub -n default --replicas=1
   kubectl scale statefulset/poa-signer-its -n default --replicas=1
   kubectl scale statefulset/poa-nonsigner-undip -n default --replicas=1
   kubectl scale statefulset/poa-nonsigner-gundar -n default --replicas=1

   ```
5. Pantau status pod:
   ```bash
   kubectl get pods -n default
   kubectl get pods -n default -o wide
   kubectl logs -n default statefulset/poa-signer-ugm -c geth --tail=200
   kubectl logs -n default statefulset/poa-signer-itb -c geth --tail=200
   kubectl logs -n default statefulset/poa-signer-ui -c geth --tail=200
   kubectl logs -n default statefulset/poa-signer-ub -c geth --tail=200
   kubectl logs -n default statefulset/poa-signer-its -c geth --tail=200

   kubectl logs -n default statefulset/poa-nonsigner-unimed -c geth --tail=200
   kubectl logs -n default statefulset/poa-nonsigner-ut -c geth --tail=200
   kubectl logs -n default statefulset/poa-nonsigner-unud -c geth --tail=200
   kubectl logs -n default statefulset/poa-nonsigner-undip -c geth --tail=200
   kubectl logs -n default statefulset/poa-nonsigner-gundar -c geth --tail=200

   # restart
   kubectl rollout restart statefulset/poa-signer-ugm -n default
   kubectl rollout restart statefulset/poa-signer-itb -n default
   kubectl rollout restart statefulset/poa-signer-ui -n default
   kubectl rollout restart statefulset/poa-signer-ub -n default
   kubectl rollout restart statefulset/poa-signer-its -n default
   kubectl rollout restart statefulset/poa-nonsigner-unimed -n default
   kubectl rollout restart statefulset/poa-nonsigner-ut -n default
   kubectl rollout restart statefulset/poa-nonsigner-unud -n default
   kubectl rollout restart statefulset/poa-nonsigner-undip -n default
   kubectl rollout restart statefulset/poa-nonsigner-gundar -n default

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

## Chaos Mesh Fault Injection

Gunakan Chaos Mesh agar skenario PoA identik dengan PoS Kurtosis.

- `.env` Caliper untuk PoA:
  
  ```bash
  FAULT_INJECT_K8S_TARGET_KIND="pod"
  FAULT_INJECT_K8S_CONTEXT="default"
  FAULT_INJECT_K8S_NAMESPACE="default"
  FAULT_INJECT_K8S_TARGET_NAME="poa-nonsigner-unimed-0"   # RPC UNIMED
  ```

- NetworkChaos template (delay 300 ms, jitter 50 ms, loss 3 %):
  
  ```yaml
  apiVersion: chaos-mesh.org/v1alpha1
  kind: NetworkChaos
  metadata:
    name: poa-rpc-delay
  spec:
    action: netem
    mode: all
    selector:
      namespaces:
        - default
      pods:
        default:
          - poa-nonsigner-unimed-0
    delay:
      latency: "300ms"
      jitter: "50ms"
      correlation: "100"
    loss:
      loss: "3"
      correlation: "100"
    duration: "10m"
  ```

  Terapkan sebelum trial Caliper dan hapus manifest untuk fase recovery. Ganti nama pod sesuai target jika hanya sebagian node yang dihidupkan.
  Salinan default tersedia di `ethereum-caliper-workspace/chaos/poa-rpc-delay.yaml`.

Export ke csv untuk Semua skenario inti (loop):

```bash
PROM="http://77.237.244.170:9102"
START="2025-11-16T11:43:10Z"
END="2025-11-16T13:43:11Z"
RUN_LABEL="POS_5V-5NV_Default_Trial_1"

for s in throughput-fixed-load throughput-step prewarm-mint-certificate prewarm-lam \
         read-intensive worker-scale-w1 worker-scale-w3 worker-scale-w5 \
         certificate-lifecycle stability-soak fault-injection-k8s; do
  ./scripts/prometheus-to-csv.sh \
    --prom "$PROM" \
    --scenario "$s" \
    --start "$START" \
    --end "$END" \
    --step 60s \
    --run-label "$RUN_LABEL"
done
```

Khusus fault-injection-k8s: pre/during/post per variant dan trial
Skrip mendukung --fault-window dengan label variant/trial; ini akan mencari marker on/off dan mengekspor tiga interval.
for v in default consensus access; do for t in 1 2 3; do ./scripts/prometheus-to-csv.sh --prom "$PROM" --scenario fault-injection-k8s --fault-window --variant "$v" --trial "$t" --lookback "240 hours" --pre 300 --post 300 --step 15s --run-label "fault-$v-t$t-$(date +%Y%m%d-%H%M)"; done; done


Ekstrak waktu start/finish fault-injection dari logs/running.log

Konteks:
Folder sumber: ethereum-caliper-workspace/logs/<RUN_LABEL>/running.log
Baris target memiliki pola: “Scenario fault-injection-k8s (variant VAR, trial N) timing: started YYYY-MM-DD HH:MM:SS, finished YYYY-MM-DD HH:MM:SS, duration …”

Tugas:
Scan semua running.log di bawah logs/.
Ambil run_label dari nama folder induk (mis. logs/PoA_5S-5NS_20251110-051000 → run_label=PoA_5S-5NS_20251110-051000).
Ekstrak variant, trial, waktu started/finished UTC.
Jika ada logs/<RUN_LABEL>/fault-injection.log, coba juga ekstrak waktu “ON/OFF” yang lebih presisi:
ON: baris yang memuat “disrupting …” (catat timestampnya).
OFF: baris pemulihan seperti “recovered”/“recovery” (catat timestampnya).
Hasilkan keluaran utama berupa tabel CSV dengan kolom:
run_label, variant, trial, start_wib, finish_wib, start_utc, finish_utc, on_utc?, off_utc?
Sertakan ringkasan:
Jumlah per variant dan trial, daftar kombinasi variant/trial yang tidak ditemukan, serta flags jika hanya punya window start/finish tanpa marker on/off.
Laporkan anomali:
Timestamp kosong/format invalid, started > finished, atau entry ganda untuk variant/trial yang sama dalam satu run.
Output yang diharapkan:
Tabel CSV (disajikan inline) + ringkasan poin.
Contoh satu baris CSV:
PoA_5S-5NS_20251110-051000,default,1,2025-11-10 12:18:28 WIB,2025-11-10 12:34:43 WIB,2025-11-10T05:18:28Z,2025-11-10T05:34:43Z,2025-11-10T05:20:28Z,2025-11-10T05:32:28Z


Verifikasi ekspor “POS_5V-5NV_Trial_4” di folder csv/
Konteks:
Folder sumber: ethereum-caliper-workspace/csv
File yang dihasilkan skrip: <RUN_LABEL>_<scenario>_tps_finished.csv, _success_ratio.csv, _latency_p50.csv, latency_p95.csv, dan <RUN_LABEL><scenario>_summary.csv
Daftar skenario yang diharapkan:
throughput-fixed-load, throughput-step, prewarm-mint-certificate, prewarm-lam, read-intensive, worker-scale-w1, worker-scale-w3, worker-scale-w5, certificate-lifecycle, stability-soak, fault-injection-k8s
Tugas:
Kerjakan verifikasi untuk batch tersebut.
Untuk tiap skenario:
Pastikan keempat file metrik ada dan tidak kosong (≥2 baris).
Validasi format CSV: 2 kolom “timestamp,value”, timestamp monoton naik, value numerik (tidak NaN/empty).
Konsistensi rentang waktu:
Nilai timestamp awal dan akhir kira-kira selaras antar keempat file (selisih awal/akhir kecil).
Langkah waktu (“step”) konsisten atau hampir konsisten (mis. 60s untuk all‑history).
Korelasi metrik:
success_ratio berada di [0,1].
tps_finished tidak semua nol sepanjang window (kecuali memang tidak ada aktivitas).
Periksa summary CSV:
Ada entri mean/median/p95 untuk tiap metrik; tidak kosong.
Hasilkan ringkasan:
Daftar skenario OK, dan daftar skenario dengan masalah (missing file, file kosong, timestamp tidak monoton, NaN).
Tunjukkan 1–2 sampel baris awal per file yang bermasalah.
Rekomendasi perbaikan jika ada masalah:
Cek label scenario di Prometheus, persempit START/END ke waktu run yang ada data, atau sesuaikan step.
Output yang diharapkan:
Ringkasan status per skenario (OK/Warning/Error) dalam daftar bullet.
Tabel kecil “anomaly report” (skenario → masalah).
Opsional: saran tindakan per masalah yang ditemukan.


Pertimbangkan menyalakan resource monitor Caliper atau telemetry node supaya bisa mengaitkan lonjakan latensi 30s dengan penggunaan CPU/mem atau log prysm/geth selama fault berlangsung.

Verifikasi ekspor “POS_5V-5NV_Default_Trial_1” di folder csv/ hiraukan sub folder history, historytest2, dan historytest3
saya menjalankan: dengan waktu sesuai scenario di file 
PROM="http://77.237.244.170:9102"
START="2025-11-17T15:18:16Z"
END="2025-11-17T15:21:48Z"
RUN_LABEL="POS_5V-5NV_Default_Trial_4_Test1"

./scripts/prometheus-to-csv.sh \
  --prom "$PROM" \
  --scenario "throughput-fixed-load" \
  --start "$START" \
  --end "$END" \
  --step 60s \
  --run-label "$RUN_LABEL"


./scripts/export_from_log.sh \
  --log logs/POS_5V-5NV_Trial_4/running.log \
  --prom http://77.237.244.170:9102 \
  --run-label POS_5V-5NV_Trial_4_cobakedua_final \
  --step 60s \
  --align-window \
  --align-buffer 120 \
  --auto-step \
  --verbose \
  --tz-offset +00:00