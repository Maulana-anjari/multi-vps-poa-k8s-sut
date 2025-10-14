# Multi-VPS PoA on k3s

Repository ini menyiapkan seluruh artefak dan manifest Kubernetes untuk menjalankan jaringan Ethereum PoA di atas cluster k3s lima VPS.

## Struktur Utama
- `config/` – salinan `genesis.json`, `rules.js`, `static-nodes.json`, password dan alamat akun signer/nonsigner.
- `artifacts/` – direktori `volumes/` yang siap dikirim ke masing-masing VPS (`geth`, `clef`).
- `signer/` & `nonsigner/` – menyimpan `node.env` per kampus (selector k3s, IP publik, jalur host).
- `scripts/` – otomasi persiapan artefak, render manifest, deploy/destroy.
- `manifests/` – template statis serta hasil render di `manifests/dist/`.
- `docs/` – panduan operasional (`SETUP.md`, `k3s-setup.md`, `cluster-layout.md`, dll).

## Alur Singkat
1. Jalankan `NETWORK_TYPE=PoA ./start-network.sh` di `blockchain-poa-geth`.
2. Dari folder ini, jalankan `./scripts/prepare-artifacts.sh` lalu edit `config/ips.env` dan `global.env`.
3. Render dan deploy:
   ```bash
   ./scripts/render-secrets.sh
   ./scripts/render-manifests.sh
   ./scripts/deploy.sh
   ```
4. Salin isi `artifacts/` ke direktori host masing-masing VPS sesuai `docs/cluster-layout.md`.
5. Pantau dengan `kubectl get pods -n <namespace>` dan ikuti checklist di `docs/SETUP.md`.

Seluruh instruksi detail tersedia di folder `docs/`. Pastikan membaca `docs/k3s-setup.md` sebelum menjalankan manifest pertama kali.
