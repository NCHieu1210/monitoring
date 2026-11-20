#!/usr/bin/env bash
set -Eeuo pipefail

# ==============================================================================
# Script tự động cài đặt Docker Engine, Docker Compose plugin và khởi chạy stack
# Hệ điều hành hỗ trợ: Ubuntu Server
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_FILE="${SCRIPT_DIR}/docker-compose.yml"

# Màu sắc log (tự tắt khi không chạy trong terminal tương tác)
if [ -t 1 ]; then
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    RED='\033[0;31m'
    BLUE='\033[0;34m'
    NC='\033[0m'
else
    GREEN='' YELLOW='' RED='' BLUE='' NC=''
fi

CURRENT_STEP="Khởi tạo"

log_step() {
    CURRENT_STEP="$1"
    echo -e "\n${BLUE}============================================================${NC}"
    echo -e "${BLUE}[STEP] ${CURRENT_STEP}${NC}"
    echo -e "${BLUE}============================================================${NC}"
}

log_ok()   { echo -e "${GREEN}[OK] $1${NC}"; }
log_warn() { echo -e "${YELLOW}[WARN] $1${NC}"; }
log_err()  { echo -e "${RED}[ERROR] $1${NC}" >&2; }

on_error() {
    local exit_code=$?
    local line_no=$1
    log_err "Thất bại tại bước: '${CURRENT_STEP}' (dòng ${line_no}, exit code: ${exit_code}). Dừng cài đặt."
    exit "$exit_code"
}
trap 'on_error $LINENO' ERR

# ------------------------------------------------------------------------------
# Bước 1: Kiểm tra hệ điều hành, quyền thực thi và file docker-compose.yml
# ------------------------------------------------------------------------------
log_step "1/8: Kiểm tra môi trường Ubuntu Server và file cấu hình"

if [ ! -f /etc/os-release ]; then
    log_err "Không tìm thấy /etc/os-release. Không thể xác định hệ điều hành."
    exit 1
fi

# shellcheck disable=SC1091
. /etc/os-release
if [ "${ID:-}" != "ubuntu" ]; then
    log_err "Script này dành cho Ubuntu Server (hệ thống hiện tại: ${ID:-unknown})."
    exit 1
fi

if [ "$(id -u)" -eq 0 ]; then
    SUDO=""
else
    if ! command -v sudo >/dev/null 2>&1; then
        log_err "Không tìm thấy lệnh 'sudo'. Vui lòng chạy bằng quyền root hoặc cài đặt sudo."
        exit 1
    fi
    SUDO="sudo"
    $SUDO -v
fi

if [ ! -f "$COMPOSE_FILE" ]; then
    log_err "Không tìm thấy file '${COMPOSE_FILE}'."
    exit 1
fi

log_ok "Môi trường hợp lệ: ${PRETTY_NAME:-Ubuntu} | Compose file: ${COMPOSE_FILE}"

# ------------------------------------------------------------------------------
# Bước 2: Gỡ bỏ các gói Docker cũ/xung đột (nếu có)
# ------------------------------------------------------------------------------
log_step "2/8: Gỡ bỏ các gói Docker cũ hoặc xung đột (nếu có)"

CONFLICT_PKGS=(
    docker.io
    docker-compose
    docker-compose-v2
    docker-doc
    docker-buildx
    podman-docker
    containerd
    runc
)

mapfile -t INSTALLED_OLD_PKGS < <(
    dpkg --get-selections "${CONFLICT_PKGS[@]}" 2>/dev/null | awk '$2 == "install" {print $1}' || true
)

if [ "${#INSTALLED_OLD_PKGS[@]}" -gt 0 ]; then
    echo "Đang gỡ bỏ các gói cũ: ${INSTALLED_OLD_PKGS[*]}"
    $SUDO env DEBIAN_FRONTEND=noninteractive apt-get remove -y "${INSTALLED_OLD_PKGS[@]}"
    log_ok "Đã gỡ bỏ xong các gói cũ."
else
    log_ok "Không có gói Docker cũ nào cần gỡ bỏ."
fi

# ------------------------------------------------------------------------------
# Bước 3: Cập nhật APT và cài đặt gói phụ thuộc
# ------------------------------------------------------------------------------
log_step "3/8: Cập nhật APT và cài đặt ca-certificates, curl"

$SUDO apt-get update
$SUDO env DEBIAN_FRONTEND=noninteractive apt-get install -y ca-certificates curl

log_ok "Đã cài đặt xong các gói phụ thuộc."

# ------------------------------------------------------------------------------
# Bước 4: Thêm Docker GPG key chính thức
# ------------------------------------------------------------------------------
log_step "4/8: Thêm Docker GPG key chính thức"

$SUDO install -m 0755 -d /etc/apt/keyrings
$SUDO curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
$SUDO chmod a+r /etc/apt/keyrings/docker.asc

log_ok "Đã thêm Docker GPG key tại /etc/apt/keyrings/docker.asc."

# ------------------------------------------------------------------------------
# Bước 5: Thêm Docker repository vào nguồn APT
# ------------------------------------------------------------------------------
log_step "5/8: Thêm Docker repository vào APT sources"

SUITE="${UBUNTU_CODENAME:-${VERSION_CODENAME:-}}"
if [ -z "$SUITE" ]; then
    log_err "Không xác định được Ubuntu codename từ /etc/os-release."
    exit 1
fi

ARCH="$(dpkg --print-architecture)"

$SUDO tee /etc/apt/sources.list.d/docker.sources >/dev/null <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: ${SUITE}
Components: stable
Architectures: ${ARCH}
Signed-By: /etc/apt/keyrings/docker.asc
EOF

$SUDO apt-get update

log_ok "Đã cấu hình Docker APT repository (${SUITE} / ${ARCH})."

# ------------------------------------------------------------------------------
# Bước 6: Cài đặt Docker Engine và Docker Compose plugin
# ------------------------------------------------------------------------------
log_step "6/8: Cài đặt Docker Engine và Docker Compose plugin"

$SUDO env DEBIAN_FRONTEND=noninteractive apt-get install -y \
    docker-ce \
    docker-ce-cli \
    containerd.io \
    docker-buildx-plugin \
    docker-compose-plugin

log_ok "Đã cài đặt thành công Docker Engine và Docker Compose plugin."

# ------------------------------------------------------------------------------
# Bước 7: Kích hoạt dịch vụ Docker và kiểm tra cài đặt
# ------------------------------------------------------------------------------
log_step "7/8: Kích hoạt dịch vụ Docker và kiểm tra phiên bản"

$SUDO systemctl enable --now docker
$SUDO systemctl is-active --quiet docker

$SUDO docker --version
$SUDO docker compose version

TARGET_USER="${SUDO_USER:-$([ "$(id -u)" -ne 0 ] && id -un || true)}"
if [ -n "$TARGET_USER" ] && [ "$TARGET_USER" != "root" ]; then
    if ! id -nG "$TARGET_USER" | grep -qw docker; then
        $SUDO usermod -aG docker "$TARGET_USER"
        log_warn "Đã thêm user '${TARGET_USER}' vào nhóm 'docker'. Đăng nhập lại (hoặc chạy 'newgrp docker') để dùng lệnh docker không cần sudo."
    fi
fi

log_ok "Dịch vụ Docker đang hoạt động bình thường."

# ------------------------------------------------------------------------------
# Bước 8: Kiểm tra cấu hình và khởi chạy Docker Compose
# ------------------------------------------------------------------------------
log_step "8/8: Kiểm tra docker-compose.yml và khởi chạy các container"

$SUDO docker compose -f "$COMPOSE_FILE" config -q
log_ok "File docker-compose.yml hợp lệ."

$SUDO docker compose -f "$COMPOSE_FILE" up -d
log_ok "Đã khởi chạy Docker Compose thành công."

echo -e "\nTrạng thái các container:"
$SUDO docker compose -f "$COMPOSE_FILE" ps

echo -e "\n${GREEN}HOÀN TẤT! Docker và toàn bộ dịch vụ trong docker-compose.yml đã được khởi chạy.${NC}"
