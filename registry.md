---
title: "Registry"
---

> **Retired.** The `iv-registry` VM was destroyed on 2026-07-14 (tailnet node
> deleted too). Nothing pulled from its legacy `registry:2` container under the
> script-based approach, and the hosted doc site it served was dropped — the
> docs are readable in-repo, and any IV VM can serve them again with
> `provision-docsite ~/iv-image` (disaster-recovery steps below double as the
> recreate recipe). This doc is retained for historical reference.

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
