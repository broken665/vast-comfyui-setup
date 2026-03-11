#!/usr/bin/env python3
"""
ComfyUI Watchdog Script for Vast.ai ComfyUI Template
- Monitors ComfyUI for inactivity
- Syncs output folder to TrueNAS via rclone over Tailscale SSH before shutdown
- Stops instance cleanly via Vast.ai CLI after 30 minutes of inactivity
"""

import time
import subprocess
import requests
import logging
import os

# ── Config ────────────────────────────────────────────────────────────────────
COMFYUI_URL    = "http://localhost:18188"   # Template uses port 18188 internally
IDLE_TIMEOUT   = 30 * 60                    # 30 minutes
POLL_INTERVAL  = 60                         # Check every 60 seconds
OUTPUT_DIR     = "/workspace/ComfyUI/output"
TRUENAS_USER   = "root"
TRUENAS_IP     = "100.124.40.118"
TRUENAS_PATH   = "/mnt/Storage/ComfyUI-Output"
LOG_FILE       = "/var/log/vast_watchdog.log"

# ── Logging ───────────────────────────────────────────────────────────────────
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    handlers=[
        logging.FileHandler(LOG_FILE),
        logging.StreamHandler()
    ]
)
log = logging.getLogger(__name__)

# ── Helpers ───────────────────────────────────────────────────────────────────
def get_queue_status():
    """Returns True if ComfyUI queue has active or pending jobs."""
    try:
        r = requests.get(f"{COMFYUI_URL}/queue", timeout=5)
        data = r.json()
        running = len(data.get("queue_running", []))
        pending = len(data.get("queue_pending", []))
        return (running + pending) > 0
    except Exception as e:
        log.warning(f"Could not reach ComfyUI: {e}")
        return False

def get_comfyui_activity():
    """Returns True if ComfyUI is reachable."""
    try:
        r = requests.get(f"{COMFYUI_URL}/system_stats", timeout=5)
        return r.status_code == 200
    except Exception:
        return False

def sync_outputs():
    """Rclone output folder to TrueNAS via SFTP over Tailscale SSH."""
    log.info("Syncing outputs to TrueNAS...")
    dest = f":sftp,host={TRUENAS_IP},user={TRUENAS_USER}:{TRUENAS_PATH}"
    result = subprocess.run(
        ["rclone", "copy", OUTPUT_DIR, dest, "--sftp-key-use-agent=false"],
        capture_output=True, text=True
    )
    if result.returncode == 0:
        log.info("Sync completed successfully.")
    else:
        log.error(f"Sync failed: {result.stderr}")

def shutdown():
    """Sync outputs then stop instance via Vast.ai CLI."""
    log.info("Idle timeout reached. Syncing before shutdown...")
    sync_outputs()

    container_id = os.environ.get("CONTAINER_ID", "")
    if container_id:
        log.info(f"Stopping instance {container_id} via Vast.ai CLI...")
        subprocess.run(["vastai", "stop", "instance", container_id])
    else:
        log.warning("CONTAINER_ID not set, falling back to poweroff...")
        subprocess.run(["poweroff"])

# ── Main loop ─────────────────────────────────────────────────────────────────
def main():
    log.info("Watchdog started. Idle timeout: 30 minutes.")
    log.info(f"Monitoring ComfyUI at {COMFYUI_URL}")
    last_activity = time.time()

    while True:
        queue_active   = get_queue_status()
        comfyui_alive  = get_comfyui_activity()

        if queue_active or comfyui_alive:
            last_activity = time.time()

        idle_seconds = time.time() - last_activity
        idle_minutes = int(idle_seconds // 60)
        log.info(f"Idle for {idle_minutes} min — queue: {'active' if queue_active else 'empty'}")

        if idle_seconds >= IDLE_TIMEOUT:
            shutdown()
            break

        time.sleep(POLL_INTERVAL)

if __name__ == "__main__":
    main()
