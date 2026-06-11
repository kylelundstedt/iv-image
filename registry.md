---
title: "Registry"
---

## Topology

`iv-registry` is an exe.dev VM running two services:

| Port    | Service                        | Access                                        |
| ------- | ------------------------------ | --------------------------------------------- |
| `:8000` | Doc site (this site)           | `https://iv-registry.exe.xyz/` (Private)      |
| `:5000` | Docker registry (`registry:2`) | `https://iv-registry.exe.xyz:5000/` (Private) |

The registry stores OCI images pushed by `build.sh`. Consumer VMs pull via the
exe.dev HTTPS proxy at `iv-registry.exe.xyz:5000`.

## iv-registry runs stock exeuntu

`iv-registry` cannot run `iv-image` — destroying the VM kills the registry it
would need to pull from (chicken-and-egg). It runs stock `boldsoftware/exeuntu`
with Quarto installed manually. The doc site is provisioned with a systemd user
service, same as the iv-image VMs.

### Disaster recovery (bootstrap from scratch)

If `iv-registry` is destroyed, rebuild it from scratch:

```bash
# 1. Create from stock exeuntu (no --image)
ssh exe.dev new --name=iv-registry --tag=iv \
  --integration=github-kylelundstedt-iv-image

# 2. Fix Docker DNS — fresh exe.dev VMs have broken DNS inside
#    Docker builds despite --network=host. Set explicit nameservers:
ssh iv-registry.exe.xyz
echo '{"dns": ["1.1.1.1", "8.8.8.8"]}' | sudo tee /etc/docker/daemon.json
sudo systemctl restart docker

# 3. Start the registry, clone, build, push
docker run -d --restart=always --name registry \
  -p 5000:5000 -v ~/registry-data:/var/lib/registry registry:2
git clone https://github-kylelundstedt-iv-image.int.exe.xyz/kylelundstedt/iv-image.git ~/iv-image
cd ~/iv-image && bash build.sh    # ~5 min from cold cache

# 4. Install Quarto and provision the doc site
curl -fsSL https://github.com/quarto-dev/quarto-cli/releases/download/v1.9.38/quarto-1.9.38-linux-amd64.tar.gz -o /tmp/quarto.tar.gz
sudo mkdir -p /opt/quarto
sudo tar -xzf /tmp/quarto.tar.gz -C /opt/quarto --strip-components=1
sudo ln -sf /opt/quarto/bin/quarto /usr/local/bin/quarto
rm /tmp/quarto.tar.gz

# 5. Render and serve the doc site on :8000
cd ~/iv-image && quarto render
export XDG_RUNTIME_DIR="/run/user/$(id -u)"
loginctl enable-linger exedev
mkdir -p ~/.config/systemd/user
cat > ~/.config/systemd/user/docsite.service <<UNIT
[Unit]
Description=Doc site on :8000
After=network-online.target
[Service]
Type=simple
WorkingDirectory=/home/exedev/iv-image/_site
ExecStart=/usr/bin/python3 -m http.server 8000 --bind 0.0.0.0
Restart=always
RestartSec=2
[Install]
WantedBy=default.target
UNIT
systemctl --user daemon-reload
systemctl --user enable --now docsite.service
```

The rebuilt VM is reached over the exe.dev edge (`ssh iv-registry.exe.xyz`) — it
does **not** auto-join the tailnet. The registry and doc site work over the
exe.dev HTTPS proxy regardless; run the `join-tailnet` skill only if you want
`ssh iv-registry` short-name (Tailscale) access.

## Registry data

Image layers are stored in a Docker volume at `~/registry-data` on the VM.
This persists across container restarts but not VM recreation. Images are fully
reproducible from the `iv-image` GitHub repo — `build.sh` rebuilds everything
from source.
