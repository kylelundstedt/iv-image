---
title: "Maintaining"
---

There is no image build anymore. VMs run stock `boldsoftware/exeuntu` and get
the IV layer from `provision-iv.sh` at a pinned git tag/sha. To change what VMs
receive, edit the provisioning script and/or the vendored skills, then commit
and tag.

## Changing tool versions

Tool versions and per-architecture checksums are pinned inside
`provision-iv.sh`. Change both the version and checksum values, run the local
validation suite, test provisioning on a disposable stock exeuntu VM, then
commit and tag the revision. The provisioner checks installed versions and
upgrades mismatches when it is re-run.

```bash
cd ~/iv-image
$EDITOR provision-iv.sh
./tests/test-ssh-guard.sh
python3 -m unittest discover -s tests -p 'test_*.py' -v
bin/render-site .
# provision + tests/smoke-provision.sh on a disposable VM
```

## Cutting a release

Provisioning releases are Git tags, not OCI image tags. Prepare and review a
release branch, merge it to `main`, then tag the exact tested merge commit:

```bash
git switch main
git pull --ff-only
# verify HEAD is the reviewed release commit and rerun the validation suite
git tag -a 2.5.0 -m "iv provisioning 2.5.0"
git push origin main
git push origin 2.5.0
```

Never move an existing release tag. Consumers pin the recipe by checking out the
tag before running `provision-iv.sh`.

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
