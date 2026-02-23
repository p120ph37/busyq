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
