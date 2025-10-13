# Pemetaan Node PoA ke k3s

Gunakan tabel berikut untuk memastikan setiap pod PoA ditempatkan pada VPS yang sesuai. Label `poa-host` dipakai oleh `node.env` via variabel `K8S_NODE_SELECTOR`.

| Peran | Nama Pod | Label `poa-host` | VPS | Direktori Host (`HOST_DATA_PATH`) |
|-------|----------|------------------|-----|-----------------------------------|
| Signer | `poa-signer-ugm` | `vps-a` | VPS-A | `/var/lib/poa/ugm` |
| Signer | `poa-signer-itb` | `vps-b` | VPS-B | `/var/lib/poa/itb` |
| Signer | `poa-signer-ui`  | `vps-c` | VPS-C | `/var/lib/poa/ui` |
| Signer | `poa-signer-ub`  | `vps-d` | VPS-D | `/var/lib/poa/ub` |
| Signer | `poa-signer-its` | `vps-e` | VPS-E | `/var/lib/poa/its` |
| Nonsigner | `poa-nonsigner-unimed` | `vps-a` | VPS-A | `/var/lib/poa/unimed` |
| Nonsigner | `poa-nonsigner-unud`   | `vps-b` | VPS-B | `/var/lib/poa/unud` |
| Nonsigner | `poa-nonsigner-gundar` | `vps-c` | VPS-C | `/var/lib/poa/gundar` |
| Nonsigner | `poa-nonsigner-ut`     | `vps-d` | VPS-D | `/var/lib/poa/ut` |
| Nonsigner | `poa-nonsigner-undip`  | `vps-e` | VPS-E | `/var/lib/poa/undip` |

## Catatan
- Jika `HOST_DATA_PATH` diubah pada `node.env`, sesuaikan tabel ini dan lakukan sinkronisasi ulang artefak ke VPS terkait.
- `render-manifests.sh` membaca nilai `K8S_NODE_SELECTOR` dan `HOST_DATA_PATH` secara langsung dari `node.env`, sehingga perubahan di file tersebut harus diikuti dengan `./scripts/render-manifests.sh` sebelum `kubectl apply`.
- Simpan catatan IP publik setiap VPS di `config/ips.env` agar script dapat memperbarui `PUBLIC_IP` secara otomatis.
