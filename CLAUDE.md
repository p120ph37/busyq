# busyq - Development Context

## What this is
A single static binary combining GNU bash + curl + jq + GNU coreutils +
upstream GNU tools. Intended for distroless containers and script shebangs.
Always launches as bash, with all bundled tools available as pseudo-builtins.

## Project layout
- `src/` - C source for entry point and applet table
- `src/applets.def` - Canonical applet registry (machine-readable)
- `ports/` - vcpkg overlay ports (bash, curl, jq, coreutils, future tools)
- `scripts/busyq-scan` - Bash script command analyzer
- `scripts/gen-applet-table.sh` - Generates applet_table.c from applets.def
- `scripts/` - Other helper scripts (cert generation, dev container)
- `CMakeLists.txt` - Builds libbusyq.a (library) + busyq (binary)
- `CMakePresets.json` - Build presets (vcpkg toolchain, no-ssl/ssl variants)
- `Dockerfile` - Multi-stage build (uses p120ph37/alpine-clang-vcpkg)
- `PLAN.md` - Roadmap for adding upstream GNU tool replacements

## Build
```sh
docker buildx build --output=out .
```
Produces:
- `out/busyq` and `out/busyq-ssl` — full binaries
- `out/libbusyq.a` and `out/libbusyq-ssl.a` — LTO library artifacts
- `out/busyq-dev/` — headers and scripts for custom builds

### Custom builds (minimal binary for a specific script)
```sh
# 1. Scan a bash script to find what commands it uses
scripts/busyq-scan myscript.sh

# 2. Get the applet list in cmake format
scripts/busyq-scan --cmake myscript.sh
#  → -DBUSYQ_APPLETS=cat;curl;jq;ls;mkdir;sort

# 3a. Build with cmake (if in the build environment)
cmake --preset no-ssl -DBUSYQ_APPLETS="cat;curl;jq;ls;mkdir;sort"
cmake --build --preset no-ssl

# 3b. Or link against the pre-built library (fast, no vcpkg needed)
scripts/gen-applet-table.sh --applets 'cat;curl;jq;ls;mkdir;sort' -o at.c
cc -flto -static -Os at.c -Isrc/ libbusyq.a -lm -ldl -lpthread -o busyq
```

### Build architecture (vcpkg overlay ports)
Each component is a vcpkg overlay port in `ports/`:
- `ports/busyq-bash/` - Builds bash 5.3 as static libraries
- `ports/busyq-coreutils/` - Builds GNU coreutils 9.5 as static library
- `ports/busyq-curl/` - Builds curl 8.18.0 (with optional SSL feature)
- `ports/busyq-jq/` - Builds jq 1.8.1 as static library

Additional upstream tools will be added as vcpkg overlay ports (see PLAN.md).
vcpkg handles dependency resolution, source downloading, patch application,
and build orchestration. The top-level CMakeLists.txt links everything together.

## Architecture decisions
- vcpkg overlay ports for each component (bash, curl, jq, coreutils, etc.)
- Bash command lookup patched in findcmd.c to check applet table before PATH
- Entry point always calls bash_main(); bash's own sh/POSIX-mode logic preserved
- Tool main() functions renamed via -Dmain=toolname_main at compile time
- All tools registered in src/applet_table.c as {name, main_func} entries
- Multi-call packages (coreutils) use one dispatch entry point that routes on argv[0]

### All libraries via vcpkg (no system libraries except musl)
Every library dependency must be built via vcpkg — never use system-installed
libraries from `apk add`. This ensures full LTO (`-flto`) is applied across
the entire binary, including dependencies. The `alpine-clang-vcpkg` base image
propagates LTO flags through `EXTRA_CFLAGS`/`EXTRA_LDFLAGS` to all vcpkg builds.

Examples of dependencies handled this way:
- **ncurses** — needed by bash/readline; built via vcpkg `ncurses` port
  (not `apk add ncurses-dev`)
- **mbedtls** — needed for SSL variant; built via vcpkg `mbedtls` port
- **oniguruma** — needed by jq; built via vcpkg `oniguruma` port
- **brotli, zstd, zlib, nghttp2** — needed by curl; all built via vcpkg

The only system-level packages installed via `apk add` should be build-time
tools that don't produce linked libraries (bison, flex, perl, etc.) and
linux-headers for kernel API definitions.

### Symbol isolation (critical for multi-package linking)
Multiple GNU packages embed gnulib, causing symbol collisions (xmalloc,
hash_insert, yyparse, etc.) when statically linked into one binary. Each
package's portfile resolves this:

1. `ld -r --whole-archive libfoo_raw.a -o foo_combined.o` — combine all
   objects into one relocatable file (resolves internal dupes)
2. `nm -u foo_combined.o` — record undefined symbols (libc, pthreads, etc.)
3. `objcopy --prefix-symbols=foo_` — namespace all symbols
4. `objcopy --redefine-syms=unprefix.map` — unprefix the external deps
   (so libc calls work) and rename `foo_main` → `toolname_main`
5. Package into `libfoo.a`

This pattern is implemented in `ports/busyq-coreutils/portfile.cmake` and
should be reused for all future packages that embed gnulib (gawk, sed, grep,
findutils, diffutils, etc.).

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
- Fixing DNS resolution inside the container (adds `nameserver 8.8.8.8`)
- Telling vcpkg to use the system curl (`VCPKG_FORCE_SYSTEM_BINARIES=1`)
- Installing build dependencies (bison, flex, linux-headers, perl, xz)
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

# Fix DNS (sandbox environments may have empty /etc/resolv.conf)
docker exec busyq-dev sh -c 'grep -q nameserver /etc/resolv.conf || echo "nameserver 8.8.8.8" > /etc/resolv.conf'

# Install proxy CA (required for TLS-intercepting proxies)
# See install_proxy_ca() in dev-container.sh for automated extraction
docker exec busyq-dev mkdir -p /usr/local/share/ca-certificates
docker cp /tmp/proxy-ca.pem busyq-dev:/usr/local/share/ca-certificates/proxy-ca.crt
docker exec busyq-dev sh -c 'cat /usr/local/share/ca-certificates/proxy-ca.crt >> /etc/ssl/certs/ca-certificates.crt'

# Install build deps
docker exec busyq-dev apk add --no-cache bison flex linux-headers perl xz

# Build (VCPKG_FORCE_SYSTEM_BINARIES makes vcpkg use system curl which
# respects proxy env vars; vcpkg's bundled curl does not)
# CMakePresets.json configures the vcpkg toolchain, which handles
# package installation automatically during cmake configure.
docker exec -e VCPKG_FORCE_SYSTEM_BINARIES=1 \
  -e "http_proxy=$http_proxy" -e "https_proxy=$https_proxy" \
  -w /src busyq-dev cmake --preset no-ssl
docker exec -w /src busyq-dev cmake --build --preset no-ssl

# Test
docker exec -w /src busyq-dev ./build/no-ssl/busyq -c 'echo hello && ls / && date +%s'
```

### Proxy and DNS troubleshooting
In sandbox environments (like Claude Code web), three things must be set up
for network access inside the container:

1. **`--network=host`** — Required when dockerd runs with `--bridge=none`.
   Without this, the container has no network connectivity at all.

2. **Proxy CA certificate** — The TLS-intercepting proxy's CA must be
   appended to `/etc/ssl/certs/ca-certificates.crt` inside the container.
   Without this, `apk add` and `curl` get TLS verification errors.
   The `dev-container.sh` script extracts the CA automatically by scanning
   the host trust store for certificates with "sandbox-egress" or
   "TLS Inspection" in the subject.

3. **DNS resolver** — Docker may generate an empty `/etc/resolv.conf`
   inside the container. Add `nameserver 8.8.8.8` if DNS resolution fails.

4. **`VCPKG_FORCE_SYSTEM_BINARIES=1`** — vcpkg bundles its own curl
   binary which does NOT respect `http_proxy`/`https_proxy` env vars.
   Setting this env var makes vcpkg use the system curl instead, which
   does respect proxy settings. Without this, `vcpkg install` fails to
   download source tarballs.

The `dev-container.sh` script handles all four of these automatically.
