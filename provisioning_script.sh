#!/bin/bash
# Vast.ai ComfyUI Provisioning Script
# Runs on first boot only via PROVISIONING_SCRIPT env variable
# Logs to /var/log/provisioning.log

exec >> /var/log/provisioning.log 2>&1
echo "=== Provisioning started: $(date) ==="

# ── Install dependencies ───────────────────────────────────────────────────────
echo "Installing Python dependencies..."
uv pip install --system av requests

# ── Install Tailscale ──────────────────────────────────────────────────────────
echo "Installing Tailscale..."
curl -fsSL https://tailscale.com/install.sh | sh
tailscaled --tun=userspace-networking --socks5-server=localhost:1055 &
sleep 3
tailscale up \
    --authkey=tskey-auth-kRPnWXJXnL11CNTRL-nxf487n8Y4WtYTBtuzsj3WdPTdFxNfnm \
    --hostname=vast-comfyui \
    --ephemeral

# ── Install rclone ─────────────────────────────────────────────────────────────
echo "Installing rclone..."
curl https://rclone.org/install.sh | bash

# ── Install custom nodes ───────────────────────────────────────────────────────
CUSTOM_NODES="/workspace/ComfyUI/custom_nodes"
echo "Installing custom nodes..."

if [ ! -d "$CUSTOM_NODES/ComfyUI-VideoHelperSuite" ]; then
    git clone https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite "$CUSTOM_NODES/ComfyUI-VideoHelperSuite"
    uv pip install --system -r "$CUSTOM_NODES/ComfyUI-VideoHelperSuite/requirements.txt"
fi

if [ ! -d "$CUSTOM_NODES/ComfyUI_IPAdapter_plus" ]; then
    git clone https://github.com/cubiq/ComfyUI_IPAdapter_plus "$CUSTOM_NODES/ComfyUI_IPAdapter_plus"
fi

# ── Download LoRAs ─────────────────────────────────────────────────────────────
CIVITAI_KEY="81e5e8b7cb990604f1dfa1e2987f8a21"
LORA_DIR="/workspace/ComfyUI/models/loras"
echo "Downloading LoRAs..."

if [ ! -f "$LORA_DIR/DetailTweakerXL.safetensors" ]; then
    wget -q --content-disposition \
        "https://civitai.com/api/download/models/135867?type=Model&format=SafeTensor&token=$CIVITAI_KEY" \
        -O "$LORA_DIR/DetailTweakerXL.safetensors" &
fi

if [ ! -f "$LORA_DIR/skin texture style v4.safetensors" ]; then
    wget -q --content-disposition \
        "https://civitai.com/api/download/models/707763?type=Model&format=SafeTensor&token=$CIVITAI_KEY" \
        -O "$LORA_DIR/skin texture style v4.safetensors" &
fi

# ── Download watchdog script ───────────────────────────────────────────────────
echo "Downloading watchdog script..."
curl -fsSL https://raw.githubusercontent.com/broken665/vast-comfyui-setup/main/vast_watchdog.py \
    -o /workspace/vast_watchdog.py
chmod +x /workspace/vast_watchdog.py

# ── Add watchdog to supervisor ─────────────────────────────────────────────────
echo "Configuring watchdog supervisor service..."
cat > /etc/supervisor/conf.d/vast_watchdog.conf << 'EOF'
[program:vast_watchdog]
command=/usr/bin/python3 /workspace/vast_watchdog.py
autostart=true
autorestart=true
stderr_logfile=/var/log/vast_watchdog.err
stdout_logfile=/var/log/vast_watchdog.log
EOF

supervisorctl reread
supervisorctl update

echo "=== Provisioning complete: $(date) ==="
