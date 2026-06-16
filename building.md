---
title: "Maintaining"
---

There is no image build anymore. VMs run stock `boldsoftware/exeuntu` and get
the IV layer from `provision-iv.sh` at a pinned git tag/sha. To change what VMs
receive, edit the provisioning script and/or the vendored skills, then commit
and tag.

## Changing tool versions

Tool versions are pinned inside `provision-iv.sh` (`DUCKDB_VERSION`,
`QUARTO_VERSION`). Edit the pins, commit, and tag a new revision. Newly
provisioned VMs pick up the change when they check out the new tag.

```bash
cd ~/iv-image
$EDITOR provision-iv.sh        # bump DUCKDB_VERSION / QUARTO_VERSION, etc.
# commit + tag
```

## Refreshing the vendored skills

Team skills are vendored into `skills/` (committed to the repo so they are
frozen — `provision-iv.sh` copies them in with no node/npx on the VM). To
refresh the snapshot, run `vendor-skills.sh` on any machine with node, then
commit the result.

```bash
./vendor-skills.sh             # refreshes skills/ — needs node/npx
# review the diff, commit, tag
```

`vendor-skills.sh` installs into a throwaway `HOME` and requires `node`/`npx`;
it is the only maintenance step that needs node.
