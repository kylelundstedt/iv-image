---
title: "Registry"
---

> **Deprecated.** The Docker registry on `iv-registry` is no longer needed under
> the script-based approach — no images are built or pulled. VMs run stock
> `boldsoftware/exeuntu` and are provisioned by `provision-iv.sh` (see
> `consuming.md`). This doc is retained for historical reference and in case the
> registry is still used for other purposes.

## What `iv-registry` is now

Under the script-based approach nothing is built or pulled, so the Docker
registry service is gone. `iv-registry` survives only as the host for this doc
site, served on `:8000` over the exe.dev HTTPS proxy at
`https://iv-registry.exe.xyz/`. It runs stock `boldsoftware/exeuntu` with Quarto
installed and the site served by a systemd user service — the same `:8000`
doc-site pattern every IV VM uses. (It could equally be retired and the site
moved to any other VM, or dropped entirely.)

If you still run the legacy `registry:2` container here for unrelated reasons,
it is independent of this project and out of scope for these docs.

### Disaster recovery (rebuild the doc-site host)

If `iv-registry` is destroyed, recreate it like any other IV VM (see
`bootstrap.md`) and provision this repo as its doc site:

```bash
ssh exe.dev new --name=iv-registry --tag=iv
ssh exe.dev integrations attach github-kylelundstedt-iv-image vm:iv-registry
ssh iv-registry.exe.xyz "git clone https://github-kylelundstedt-iv-image.int.exe.xyz/kylelundstedt/iv-image.git ~/iv-image \
  && ~/iv-image/provision-iv.sh \
  && provision-docsite ~/iv-image"
```

`provision-iv.sh` installs Quarto; `provision-docsite` renders the site and
serves `_site` on `:8000`. The VM is reached over the exe.dev edge; run the
`join-tailnet` skill only if you want `ssh iv-registry` short-name access.
