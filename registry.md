---
title: "Registry"
---

## Topology

`iv-registry` is an exe.dev VM running two services:

| Port    | Service                        | Access                                     |
| ------- | ------------------------------ | ------------------------------------------ |
| `:8000` | Doc site (this site)           | `https://iv-registry.exe.xyz/` (Private)   |
| `:5000` | Docker registry (`registry:2`) | `https://iv-registry.exe.xyz:5000/` (Private) |

The registry stores OCI images pushed by `build.sh`. Consumer VMs pull via the
exe.dev HTTPS proxy at `iv-registry.exe.xyz:5000`.

## iv-registry runs iv-image

Unlike earlier versions, `iv-registry` itself runs `iv-image` — giving it Quarto,
`provision-docsite`, and every tool baked into the image. This avoids maintaining
a special-case VM.

### Disaster recovery (bootstrap from scratch)

If `iv-registry` is destroyed, the registry is gone and you can't pull `iv-image`
to recreate it. Two-step bootstrap:

```bash
# 1. Create from stock exeuntu (no --image)
ssh exe.dev new --name=iv-registry --tag=iv \
  --integration=github-kylelundstedt-iv-image

# 2. Start the registry, clone, build, push
ssh iv-registry.exe.xyz
docker run -d --restart=always --name registry \
  -p 5000:5000 -v ~/registry-data:/var/lib/registry registry:2
git clone https://github-kylelundstedt-iv-image.int.exe.xyz/kylelundstedt/iv-image.git ~/iv-image
cd ~/iv-image && bash build.sh

# 3. Recreate from iv-image
exit
ssh exe.dev rm iv-registry
ssh exe.dev new --name=iv-registry --tag=iv \
  --integration=github-kylelundstedt-iv-image \
  --image=iv-registry.exe.xyz:5000/iv-image:1.3
# Then: start registry, clone repo, provision-docsite
```

## Registry data

Image layers are stored in a Docker volume at `~/registry-data` on the VM.
This persists across container restarts but not VM recreation. Images are fully
reproducible from the `iv-image` GitHub repo — `build.sh` rebuilds everything
from source.
