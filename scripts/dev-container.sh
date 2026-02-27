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
#   dev-exec './build/no-ssl/busyq -c "echo hello | sort"'
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
    # Use --network=host so the container shares the host's network stack.
    # This is required in sandbox environments where dockerd runs with
    # --bridge=none (no virtual bridge), which makes container-private
    # networking unreachable. With host networking, the container inherits
    # the host's proxy settings and CA certificates automatically.
    docker run -d \
        --name "${DEV_CONTAINER_NAME}" \
        --network=host \
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

    # Fix DNS — sandbox environments may generate empty /etc/resolv.conf
    # inside the container, breaking name resolution even with --network=host
    docker exec "${DEV_CONTAINER_NAME}" sh -c \
        'grep -q nameserver /etc/resolv.conf 2>/dev/null || echo "nameserver 8.8.8.8" > /etc/resolv.conf'

    # Install build dependencies
    echo "dev-container: installing build dependencies..."
    docker exec "${DEV_CONTAINER_NAME}" \
        apk add --no-cache bison flex linux-headers perl xz 2>&1 | tail -1

    echo "dev-container: ready. Use 'dev-exec <cmd>' to run commands."
}

# ── Execute a command in the container ───────────────────────────────────
# Forwards proxy env vars and VCPKG_FORCE_SYSTEM_BINARIES so that vcpkg
# uses the system curl (which respects proxy settings) instead of its own.
dev-exec() {
    local env_args=(-e "VCPKG_FORCE_SYSTEM_BINARIES=1")
    local var
    for var in http_proxy https_proxy HTTP_PROXY HTTPS_PROXY no_proxy NO_PROXY; do
        if [ -n "${!var:-}" ]; then
            env_args+=(-e "${var}=${!var}")
        fi
    done
    docker exec "${env_args[@]}" -w /src "${DEV_CONTAINER_NAME}" sh -c "$*"
}

# ── Run the full build ───────────────────────────────────────────────────
dev-build() {
    echo "dev-container: configuring + building busyq (no SSL)..."
    dev-exec 'cmake --preset no-ssl && cmake --build --preset no-ssl'

    echo "dev-container: build complete."
    echo "  Binary:  build/no-ssl/busyq"
    echo "  Library: build/no-ssl/libbusyq.a"
}

# ── Stop and remove the container ────────────────────────────────────────
dev-stop() {
    docker rm -f "${DEV_CONTAINER_NAME}" >/dev/null 2>&1
    echo "dev-container: stopped and removed '${DEV_CONTAINER_NAME}'"
}

# ── Quick test ───────────────────────────────────────────────────────────
dev-test() {
    echo "=== Smoke tests ==="
    dev-exec './build/no-ssl/busyq -c "echo \"bash: ok\""'
    dev-exec './build/no-ssl/busyq -c "ls / > /dev/null && echo \"ls: ok\""'
    dev-exec './build/no-ssl/busyq -c "cat /dev/null && echo \"cat: ok\""'
    dev-exec './build/no-ssl/busyq -c "date +%s > /dev/null && echo \"date: ok\""'
    dev-exec './build/no-ssl/busyq -c "echo -e \"b\na\nc\" | sort | head -1 | tr a-z A-Z && echo \"coreutils: ok\""'
    dev-exec './build/no-ssl/busyq -c "jq -n \"{test: true}\" && echo \"jq: ok\""'
    dev-exec './build/no-ssl/busyq -c "curl --version > /dev/null && echo \"curl: ok\""'
    echo "=== All smoke tests passed ==="
}

echo "dev-container: functions loaded. Run 'dev-start' to begin."
