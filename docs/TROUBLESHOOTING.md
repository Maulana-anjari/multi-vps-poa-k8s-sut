# Troubleshooting PoA k3s

## Pod CrashLoopBackOff
- **Cek log Clef**  
  ```bash
  kubectl logs statefulset/poa-signer-ugm -c clef -n $K8S_NAMESPACE --tail=200
  ```
  Jika error `permission denied` pada `masterseed.json`, pastikan file di host memiliki mode `400` dan pemilik `root`.
- **Cek log Geth**  
  ```bash
  kubectl logs statefulset/poa-signer-ugm -c geth -n $K8S_NAMESPACE --tail=200
  ```
  Periksa apakah `BOOTNODE_ENODE` sudah menyertakan IP publik yang benar.

## Pod Tidak Terschedule
- Jalankan `kubectl describe pod <nama-pod> -n $K8S_NAMESPACE` dan cari pesan `0/5 nodes are available: no nodes match pod affinity/selector`.
- Pastikan label `poa-host=<nilai>` terpasang di node (`kubectl get nodes --show-labels | grep poa-host`).
- Hapus label lama yang salah dengan `kubectl label node <hostname> poa-host-`.

## Data Tidak Sinkron / Node Membangun Ulang Chain
- Verifikasi direktori host:
  ```bash
  ssh root@<ip-vps> ls /var/lib/poa/ugm/geth
  ```
- Pastikan `artifacts/` terbaru sudah dikopi ulang setelah menjalankan `prepare-artifacts.sh`.
- Jika perlu reset, hentikan pod, hapus isi direktori host lalu rsync ulang data dari artefak terbaru.

## RPC Tidak Dapat Diakses
- Gunakan port-forward sementara untuk verifikasi:
  ```bash
  kubectl port-forward svc/poa-signer-ugm 18545:8545 -n $K8S_NAMESPACE
  curl -s localhost:18545 -X POST --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' -H 'Content-Type: application/json'
  ```
- Jika berhasil melalui port-forward namun tidak langsung, periksa aturan firewall/SG di VPS (port 8545/8546/30303).

## Ethstats Tidak Menampilkan Node
- Pastikan variabel `ETHSTATS_ID`, `ETHSTATS_ENDPOINT`, dan `ETHSTATS_WS_SECRET` konsisten di `global.env` serta `node.env`.
- Cek konektivitas dari pod:
  ```bash
  kubectl exec -n $K8S_NAMESPACE poa-signer-ugm-0 -c geth -- wget -qO- http://<ethstats-host>:3000
  ```

## Penggunaan Resource Tinggi
- Periksa pemakaian CPU/memori:
  ```bash
  kubectl top pods -n $K8S_NAMESPACE
  kubectl top nodes
  ```
- Adjust `resources` limit di manifest jika perlu (tambahkan di file `manifests/dist/...` atau modifikasi generator).
