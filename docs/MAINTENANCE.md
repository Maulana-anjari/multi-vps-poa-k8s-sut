# Pemeliharaan Rutin

## Backup
- Simpan salinan:
  - `config/genesis.json`, `config/rules.js`, `config/static-nodes.json`
  - `config/addresses/*.addr` dan `config/passwords/*.pass`
  - `signer/*/node.env` dan `nonsigner/*/node.env`
  - Direktori host `/var/lib/poa/<node>` minimal sekali seminggu (gunakan `rsync` atau snapshot storage).
- Catat hash `genesis.json` di sistem monitoring agar mudah mendeteksi perbedaan antar node.

## Rotasi Password Signer
1. Update file `blockchain-poa-geth/config/passwords/signerX.pass`.
2. Regenerasi artefak: `./scripts/prepare-artifacts.sh`.
3. Jalankan `./scripts/render-secrets.sh` dan `kubectl apply -f manifests/shared/secrets.generated.yaml`.
4. Restart pod signer terkait `kubectl rollout restart statefulset/poa-signer-ugm -n $K8S_NAMESPACE`.

## Update Geth/Clef Image
1. Edit `GETH_IMAGE` dan/atau `CLEF_IMAGE` di `global.env`.
2. Jalankan `./scripts/render-manifests.sh`.
3. Terapkan pembaruan `kubectl apply -f manifests/dist/signer -n $K8S_NAMESPACE` dan `manifests/dist/nonsigner`.

## Upgrade Kubernetes
- Upgrade control plane k3s lebih dulu, lalu worker satu per satu. Pastikan setidaknya tiga signer tetap online selama upgrade.
- Setelah upgrade, verifikasi `kubectl get nodes` dan jalankan `kubectl rollout status` untuk memastikan pod otomatis kembali.

## Audit Keamanan
- Tinjau izin secret: `kubectl get secrets -n $K8S_NAMESPACE`.
- Gunakan `kubectl auth can-i` untuk memastikan hanya service account tertentu yang memiliki akses sensitif.
- Terapkan NetworkPolicy jika jaringan antar pod perlu dibatasi.

## Dokumentasi Perubahan
- Catat setiap modifikasi pada `docs/CHANGELOG.md` (buat file bila belum ada) agar anggota tim lain dapat mengikuti evolusi konfigurasi PoA.
