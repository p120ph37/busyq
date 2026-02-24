#!/bin/bash
# dev-container.sh - Launch a development container for iterative busyq debugging
#
# Sets up a Docker daemon (if needed) and launches a persistent container
# based on p120ph37/alpine-clang-vcpkg with the project mounted at /src.
#
# Usage:
#   source scripts/dev-container.sh   # set up env + define functions
#   dev-start                         # start daemon + container
#   dev-exec <command>                # run a command in the container
#   dev-build                         # run full vcpkg install + cmake build
#   dev-stop                          # stop and remove the container
#
# Examples:
#   dev-exec apk add --no-cache bison flex
#   dev-exec 'vcpkg install && cmake -B build -S . && cmake --build build'
#   dev-exec './build/busyq -c "awk \"BEGIN {print 42}\""'
#
set -euo pipefail

DEV_CONTAINER_NAME="${DEV_CONTAINER_NAME:-busyq-dev}"
DEV_IMAGE="${DEV_IMAGE:-p120ph37/alpine-clang-vcpkg:latest}"
PROJECT_DIR="${PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

# ── Start Docker daemon ──────────────────────────────────────────────────
# Handles sandbox environments that lack iptables/overlayfs/bridge support.
setup_dockerd() {
    if docker info >/dev/null 2>&1; then
        echo "dev-container: dockerd already running"
        return 0
    fi

    echo "dev-container: starting dockerd..."
    dockerd \
        --iptables=false \
        --ip6tables=false \
        --bridge=none \
        --storage-driver=vfs \
        >/tmp/dockerd.log 2>&1 &

    local i=0
    while ! docker info >/dev/null 2>&1; do
        sleep 1
        i=$((i + 1))
        if [ "$i" -ge 30 ]; then
            echo "dev-container: ERROR - dockerd failed to start" >&2
            tail -20 /tmp/dockerd.log >&2
            return 1
        fi
    done
    echo "dev-container: dockerd ready"
}

# ── Extract and install proxy CA certificate ─────────────────────────────
# Needed when running behind a TLS-intercepting proxy (e.g. Claude Code web).
install_proxy_ca() {
    local container="$1"

    # Try to extract proxy CA from host trust store
    if [ -f /etc/ssl/certs/ca-certificates.crt ] && command -v python3 >/dev/null 2>&1; then
        python3 -c "
import re, sys, subprocess
with open('/etc/ssl/certs/ca-certificates.crt', 'r') as f:
    bundle = f.read()
certs = re.findall(r'(-----BEGIN CERTIFICATE-----.*?-----END CERTIFICATE-----)', bundle, re.DOTALL)
for cert_pem in certs:
    result = subprocess.run(['openssl', 'x509', '-noout', '-subject'], input=cert_pem, capture_output=True, text=True)
    if 'sandbox-egress' in result.stdout or 'TLS Inspection' in result.stdout:
        with open('/tmp/proxy-ca.pem', 'w') as out:
            out.write(cert_pem + '\n')
        sys.exit(0)
sys.exit(1)
" 2>/dev/null || true
    fi

    if [ -f /tmp/proxy-ca.pem ]; then
        echo "dev-container: installing proxy CA certificate into container..."
        docker exec "$container" mkdir -p /usr/local/share/ca-certificates
        docker cp /tmp/proxy-ca.pem "$container":/usr/local/share/ca-certificates/proxy-ca.crt
        docker exec "$container" sh -c \
            'cat /usr/local/share/ca-certificates/proxy-ca.crt >> /etc/ssl/certs/ca-certificates.crt'
        echo "dev-container: proxy CA installed"
    fi
}

# ── Start the development container ──────────────────────────────────────
dev-start() {
    setup_dockerd

    # Pull latest image
    echo "dev-container: pulling ${DEV_IMAGE}..."
    docker pull "${DEV_IMAGE}" 2>&1 | tail -1

    # Remove existing container if present
    docker rm -f "${DEV_CONTAINER_NAME}" >/dev/null 2>&1 || true

    # Collect proxy env vars to forward
    local proxy_args=()
    for var in http_proxy https_proxy HTTP_PROXY HTTPS_PROXY no_proxy NO_PROXY; do
        if [ -n "${!var:-}" ]; then
            proxy_args+=(-e "${var}=${!var}")
        fi
    done

    echo "dev-container: starting container '${DEV_CONTAINER_NAME}'..."
    docker run -d \
        --name "${DEV_CONTAINER_NAME}" \
        "${proxy_args[@]}" \
        -v "${PROJECT_DIR}:/src" \
        -w /src \
        "${DEV_IMAGE}" \
        sleep infinity

    # Wait for container to be ready
    local i=0
    while ! docker exec "${DEV_CONTAINER_NAME}" true 2>/dev/null; do
        sleep 1
        i=$((i + 1))
        if [ "$i" -ge 30 ]; then
            echo "dev-container: ERROR - container failed to start" >&2
            docker logs "${DEV_CONTAINER_NAME}" 2>&1 | tail -10 >&2
            return 1
        fi
    done

    # Install proxy CA if behind a TLS proxy
    install_proxy_ca "${DEV_CONTAINER_NAME}"

    # Install build dependencies
    echo "dev-container: installing build dependencies..."
    docker exec "${DEV_CONTAINER_NAME}" \
        apk add --no-cache bison flex ncurses-dev ncurses-static linux-headers perl 2>&1 | tail -1

    echo "dev-container: ready. Use 'dev-exec <cmd>' to run commands."
}

# ── Execute a command in the container ───────────────────────────────────
dev-exec() {
    docker exec -w /src "${DEV_CONTAINER_NAME}" sh -c "$*"
}

# ── Run the full build ───────────────────────────────────────────────────
dev-build() {
    echo "dev-container: running vcpkg install..."
    dev-exec 'vcpkg install'

    echo "dev-container: building busyq (no SSL)..."
    dev-exec 'cmake -B build/none -S . \
        -DCMAKE_BUILD_TYPE=Release \
        -DBUSYQ_SSL=OFF \
        -D_VCPKG_INSTALLED_DIR=$(pwd)/vcpkg_installed \
        -DVCPKG_TARGET_TRIPLET=x64-linux \
        && cmake --build build/none'

    echo "dev-container: build complete. Binary at build/none/busyq"
}

# ── Stop and remove the container ────────────────────────────────────────
dev-stop() {
    docker rm -f "${DEV_CONTAINER_NAME}" >/dev/null 2>&1
    echo "dev-container: stopped and removed '${DEV_CONTAINER_NAME}'"
}

# ── Quick test ───────────────────────────────────────────────────────────
dev-test() {
    echo "=== Smoke tests ==="
    dev-exec './build/none/busyq -c "echo \"bash: ok\""'
    dev-exec './build/none/busyq -c "type ls && ls / > /dev/null && echo \"applets: ok\""'
    dev-exec './build/none/busyq -c "jq -n \"{test: true}\" && echo \"jq: ok\""'
    dev-exec './build/none/busyq -c "curl --version > /dev/null && echo \"curl: ok\""'
    dev-exec './build/none/busyq -c "echo test | awk \"{print \\\"awk:\\\", \\\$0}\""'
    echo "=== All smoke tests passed ==="
}

echo "dev-container: functions loaded. Run 'dev-start' to begin."
