# busyq - Development Context

## What this is
A single static binary combining busybox + GNU bash + curl + jq. Intended for
distroless containers and script shebangs. Always launches as bash, with all
busybox applets + curl + jq available as pseudo-builtins.

## Project layout
- `src/` - C source for entry point, applet table, namespace header
- `patches/` - Patches for bash, busybox, curl, jq (organized by project)
- `config/` - Busybox defconfig
- `scripts/` - Build orchestration scripts
- `Dockerfile` - Multi-stage build (uses p120ph37/alpine-clang-vcpkg)

## Build
```sh
docker buildx build --output=out .
```
Produces `out/busyq` (no SSL) and `out/busyq-ssl` (with mbedtls).

## Architecture decisions
- Hybrid build: vcpkg for library deps (mbedtls, oniguruma), direct clang for
  main projects (busybox, bash, curl, jq) since they need heavy patching
- Symbol collisions resolved via `bb_namespace.h` (compile-time #define renaming)
- Bash command lookup patched in findcmd.c to check applet table before PATH
- NOFORK applets run in-process for speed; others fork for isolation
- Entry point always calls bash_main(); bash's own sh/POSIX-mode logic preserved
- curl+jq main() renamed via -Dmain=curl_main / -Dmain=jq_main
