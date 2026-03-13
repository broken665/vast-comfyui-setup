#!/bin/bash
# ComfyUI Provisioning Script for Vast.ai
# Based on vast-ai/base-image default provisioning script
# Customized for broken665's setup
#
# Required environment variables (set in Vast.ai template):
#   HF_TOKEN        - HuggingFace token (for gated models like SVD-XT)
#   CIVITAI_TOKEN   - CivitAI API token
#   TAILSCALE_AUTHKEY - Tailscale auth key

source /venv/main/bin/activate
COMFYUI_DIR=${WORKSPACE}/ComfyUI

APT_PACKAGES=(
    # "package-1"
)

PIP_PACKAGES=(
    "av"
)

NODES=(
    "https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite"
    "https://github.com/cubiq/ComfyUI_IPAdapter_plus"
)

CHECKPOINT_MODELS=(
    "https://huggingface.co/broken667/comfyui-models/resolve/main/checkpoints/lustifySDXLNSFW_ggwpV7.safetensors"
    "https://huggingface.co/broken667/comfyui-models/resolve/main/checkpoints/svd_xt.safetensors"
)

UNET_MODELS=(
)

LORA_MODELS=(
    "https://huggingface.co/broken667/comfyui-models/resolve/main/loras/DetailTweakerXL.safetensors"
    "https://huggingface.co/broken667/comfyui-models/resolve/main/loras/skin%20texture%20style%20v4.safetensors"
)

VAE_MODELS=(
)

ESRGAN_MODELS=(
)

CONTROLNET_MODELS=(
)

### DO NOT EDIT BELOW HERE UNLESS YOU KNOW WHAT YOU ARE DOING ###

function provisioning_start() {
    provisioning_print_header
    provisioning_get_apt_packages
    provisioning_get_nodes
    provisioning_get_pip_packages
    provisioning_get_files \
        "${COMFYUI_DIR}/models/checkpoints" \
        "${CHECKPOINT_MODELS[@]}"
    provisioning_get_files \
        "${COMFYUI_DIR}/models/unet" \
        "${UNET_MODELS[@]}"
    provisioning_get_files \
        "${COMFYUI_DIR}/models/loras" \
        "${LORA_MODELS[@]}"
    provisioning_get_files \
        "${COMFYUI_DIR}/models/controlnet" \
        "${CONTROLNET_MODELS[@]}"
    provisioning_get_files \
        "${COMFYUI_DIR}/models/vae" \
        "${VAE_MODELS[@]}"
    provisioning_get_files \
        "${COMFYUI_DIR}/models/esrgan" \
        "${ESRGAN_MODELS[@]}"
    provisioning_setup_tailscale
    provisioning_setup_rclone
    provisioning_setup_watchdog
    provisioning_print_end
}

function provisioning_get_apt_packages() {
    if [[ -n $APT_PACKAGES ]]; then
        sudo $APT_INSTALL ${APT_PACKAGES[@]}
    fi
}

function provisioning_get_pip_packages() {
    if [[ -n $PIP_PACKAGES ]]; then
        pip install --no-cache-dir ${PIP_PACKAGES[@]}
    fi
}

function provisioning_get_nodes() {
    for repo in "${NODES[@]}"; do
        dir="${repo##*/}"
        path="${COMFYUI_DIR}/custom_nodes/${dir}"
        requirements="${path}/requirements.txt"
        if [[ -d $path ]]; then
            if [[ ${AUTO_UPDATE,,} != "false" ]]; then
                printf "Updating node: %s...\n" "${repo}"
                ( cd "$path" && git pull )
                if [[ -e $requirements ]]; then
                    pip install --no-cache-dir -r "$requirements"
                fi
            fi
        else
            printf "Downloading node: %s...\n" "${repo}"
            git clone "${repo}" "${path}" --recursive
            if [[ -e $requirements ]]; then
                pip install --no-cache-dir -r "${requirements}"
            fi
        fi
    done
}

function provisioning_get_files() {
    if [[ -z $2 ]]; then return 1; fi

    dir="$1"
    mkdir -p "$dir"
    shift
    arr=("$@")
    printf "Downloading %s model(s) to %s...\n" "${#arr[@]}" "$dir"
    for url in "${arr[@]}"; do
        printf "Downloading: %s\n" "${url}"
        provisioning_download "${url}" "${dir}"
        printf "\n"
    done
}

function provisioning_setup_tailscale() {
    printf "Setting up Tailscale...\n"
    if ! command -v tailscale &> /dev/null; then
        curl -fsSL https://tailscale.com/install.sh | sh
    fi
    if ! pgrep -x tailscaled > /dev/null; then
        tailscaled --tun=userspace-networking --socks5-server=localhost:1055 &
        sleep 3
    fi
    if [[ -n $TAILSCALE_AUTHKEY ]]; then
        tailscale up --authkey=$TAILSCALE_AUTHKEY --hostname=vast-comfyui
    else
        printf "WARNING: TAILSCALE_AUTHKEY not set — skipping Tailscale auth\n"
    fi
}

function provisioning_setup_rclone() {
    printf "Setting up rclone...\n"
    if ! command -v rclone &> /dev/null; then
        curl https://rclone.org/install.sh | bash
    fi
}

function provisioning_setup_watchdog() {
    printf "Setting up watchdog...\n"
    curl -fsSL https://raw.githubusercontent.com/broken665/vast-comfyui-setup/main/vast_watchdog.py \
        -o /workspace/vast_watchdog.py
    chmod +x /workspace/vast_watchdog.py

    cat > /etc/supervisor/conf.d/vast_watchdog.conf << 'SUPERVISOREOF'
[program:vast_watchdog]
command=/venv/main/bin/python /workspace/vast_watchdog.py
autostart=true
autorestart=true
stderr_logfile=/var/log/vast_watchdog.err
stdout_logfile=/var/log/vast_watchdog.log
SUPERVISOREOF

    supervisorctl reread
    supervisorctl update
}

function provisioning_print_header() {
    printf "\n##############################################\n#                                            #\n#          Provisioning container            #\n#                                            #\n#         This will take some time           #\n#                                            #\n# Your container will be ready on completion #\n#                                            #\n##############################################\n\n"
}

function provisioning_print_end() {
    printf "\nProvisioning complete:  Application will start now\n\n"
}

function provisioning_has_valid_hf_token() {
    [[ -n "$HF_TOKEN" ]] || return 1
    url="https://huggingface.co/api/whoami-v2"
    response=$(curl -o /dev/null -s -w "%{http_code}" -X GET "$url" \
        -H "Authorization: Bearer $HF_TOKEN" \
        -H "Content-Type: application/json")
    if [ "$response" -eq 200 ]; then
        return 0
    else
        return 1
    fi
}

function provisioning_has_valid_civitai_token() {
    [[ -n "$CIVITAI_TOKEN" ]] || return 1
    url="https://civitai.com/api/v1/models?hidden=1&limit=1"
    response=$(curl -o /dev/null -s -w "%{http_code}" -X GET "$url" \
        -H "Authorization: Bearer $CIVITAI_TOKEN" \
        -H "Content-Type: application/json")
    if [ "$response" -eq 200 ]; then
        return 0
    else
        return 1
    fi
}

# Download from $1 URL to $2 file path
function provisioning_download() {
    if [[ -n $HF_TOKEN && $1 =~ ^https://([a-zA-Z0-9_-]+\.)?huggingface\.co(/|$|\?) ]]; then
        auth_token="$HF_TOKEN"
    elif [[ -n $CIVITAI_TOKEN && $1 =~ ^https://([a-zA-Z0-9_-]+\.)?civitai\.com(/|$|\?) ]]; then
        auth_token="$CIVITAI_TOKEN"
    fi
    if [[ -n $auth_token ]]; then
        wget --header="Authorization: Bearer $auth_token" -qnc --content-disposition --show-progress -e dotbytes="${3:-4M}" -P "$2" "$1"
    else
        wget -qnc --content-disposition --show-progress -e dotbytes="${3:-4M}" -P "$2" "$1"
    fi
}

# Allow user to disable provisioning if they started with a script they didn't want
if [[ ! -f /.noprovisioning ]]; then
    provisioning_start
fi
