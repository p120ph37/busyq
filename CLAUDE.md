# busyq - Development Context

## What this is
A single static binary combining busybox + GNU bash + curl + jq. Intended for
distroless containers and script shebangs. Always launches as bash, with all
busybox applets + curl + jq available as pseudo-builtins.

## Project layout
- `src/` - C source for entry point, applet table, namespace header
- `ports/` - vcpkg overlay ports for bash, busybox, curl, jq
- `config/` - Busybox defconfig
- `scripts/` - Helper scripts (cert generation)
- `patches/` - Legacy patches (superseded by ports/*/patches)
- `CMakeLists.txt` - Final link step
- `Dockerfile` - Multi-stage build (uses p120ph37/alpine-clang-vcpkg)

## Build
```sh
docker buildx build --output=out .
```
Produces `out/busyq` (no SSL) and `out/busyq-ssl` (with mbedtls).

### Build architecture (vcpkg overlay ports)
Each component is a vcpkg overlay port in `ports/`:
- `ports/busyq-bash/` - Builds bash 5.3 as static libraries
- `ports/busyq-busybox/` - Builds busybox 1.37.0 as static library
- `ports/busyq-curl/` - Builds curl 8.18.0 (with optional SSL feature)
- `ports/busyq-jq/` - Builds jq 1.8.1 as static library

vcpkg handles dependency resolution, source downloading, patch application,
and build orchestration. The top-level CMakeLists.txt links everything together.

## Architecture decisions
- vcpkg overlay ports for all four components (bash, busybox, curl, jq)
- Symbol collisions resolved via `bb_namespace.h` (compile-time #define renaming)
- Bash command lookup patched in findcmd.c to check applet table before PATH
- NOFORK applets run in-process for speed; others fork for isolation
- Entry point always calls bash_main(); bash's own sh/POSIX-mode logic preserved
- curl+jq main() renamed via -Dmain=curl_main / -Dmain=jq_main

## Iterative development with Docker

For iterative debugging and building without running the full Dockerfile,
use the dev container script to get a shell inside the build environment:

```sh
source scripts/dev-container.sh
dev-start          # starts dockerd + pulls image + launches container
dev-build          # runs vcpkg install + cmake build
dev-test           # runs smoke tests against the built binary
dev-exec '<cmd>'   # run any command inside the container
dev-stop           # tear down the container
```

### How it works
The script launches a persistent `p120ph37/alpine-clang-vcpkg` container
with the project directory bind-mounted at `/src`. It handles:
- Starting dockerd with sandbox-compatible flags (no iptables/bridge/overlayfs)
- Forwarding proxy environment variables into the container
- Extracting and installing TLS-intercepting proxy CA certificates
- Installing build dependencies (bison, flex, linux-headers, perl)
- Using `--network=host` so the container shares the host network stack
  (required when dockerd runs with `--bridge=none`)

### Manual usage (without the script)
```sh
# Start dockerd (sandbox environments only)
dockerd --iptables=false --ip6tables=false --bridge=none --storage-driver=vfs &

# Launch container (--network=host is required when using --bridge=none)
docker run -d --name busyq-dev \
  --network=host \
  -e "http_proxy=$http_proxy" -e "https_proxy=$https_proxy" \
  -v "$(pwd):/src" -w /src \
  p120ph37/alpine-clang-vcpkg:latest sleep infinity

# Run commands
docker exec -w /src busyq-dev vcpkg install
docker exec -w /src busyq-dev cmake -B build -S . -DBUSYQ_SSL=OFF \
  -D_VCPKG_INSTALLED_DIR=/src/vcpkg_installed -DVCPKG_TARGET_TRIPLET=x64-linux
docker exec -w /src busyq-dev cmake --build build

# Test
docker exec -w /src busyq-dev ./build/busyq -c 'echo hello | awk "{print}"'
```

### Proxy CA certificates
In environments with TLS-intercepting proxies (like Claude Code web), the
container needs the proxy CA installed before `apk add` or `vcpkg install`
will work. The `dev-container.sh` script handles this automatically. For
manual setup, extract the CA from `/etc/ssl/certs/ca-certificates.crt` on
the host and append it to the same file inside the container.
