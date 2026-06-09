---
title: "Consuming"
---

## Creating a VM from iv-image

```bash
ssh exe.dev new --image=iv-registry.exe.xyz:5000/iv-image:1.3 --name=<vm> --tag=iv
```

Pin to an exact build or digest for reproducibility:

```bash
ssh exe.dev new --image=iv-registry.exe.xyz:5000/iv-image:1.3.1 ...
ssh exe.dev new --image=iv-registry.exe.xyz:5000/iv-image@sha256:... ...
```

The image is consumed only at VM creation — there is no default-image setting,
so pass `--image` on every `new`.

## Provisioning a doc site

Each repo-VM serves its rendered site on `:8000` (the exe.dev HTTPS proxy port).
After cloning a repo:

```bash
ssh <vm>.exe.xyz "git clone https://<integration>.int.exe.xyz/<org>/<repo>.git ~/<repo>"
ssh <vm>.exe.xyz "provision-docsite ~/<repo>"
```

`provision-docsite` renders the Quarto project and starts a persistent systemd
user service serving `_site` on `:8000`. To re-render after edits, run
`render-site ~/<repo>` — no restart needed.
