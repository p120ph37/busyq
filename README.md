# busyq

A single static binary combining **GNU bash** + **curl** + **jq** + **GNU coreutils** + 200+ upstream GNU/BSD tools. Designed for distroless containers and script shebangs.

Always launches as bash, with all bundled tools available as pseudo-builtins — no PATH required.

## Quick start

```dockerfile
FROM p120ph37/busyq:latest
ENTRYPOINT ["/busyq", "-c"]
CMD ["echo hello world"]
```

```sh
# Run directly
docker run --rm p120ph37/busyq /busyq -c 'echo "hello" | jq -Rn "[inputs]"'

# Interactive shell
docker run --rm -it p120ph37/busyq /busyq
```

## Available images

All images are multi-arch (`linux/amd64` + `linux/arm64`).

| Image | Description |
|-------|-------------|
| `p120ph37/busyq:latest` | Full binary with SSL/TLS (mbedtls + embedded Mozilla CA bundle) |
| `p120ph37/busyq:nossl` | Smaller binary without SSL support |
| `p120ph37/busyq:custom` | Alpine-based build environment for creating minimal custom binaries |

Version-pinned tags follow Alpine versioning: `3.23`, `3.23.3`, `3.23-nossl`, `3.23.3-nossl`, `3.23-custom`, `3.23.3-custom`.

## Copy into your own image

The binary is fully static — just copy it:

```dockerfile
FROM p120ph37/busyq:latest AS busyq

FROM your-base-image
COPY --from=busyq /busyq /usr/local/bin/busyq
```

Or in a `FROM scratch` image:

```dockerfile
FROM p120ph37/busyq:latest AS busyq

FROM scratch
COPY --from=busyq /busyq /busyq
ENTRYPOINT ["/busyq"]
```

## Use as a script interpreter

busyq supports embedded script overlays — append a bash script after the binary to create a self-contained executable:

```sh
# Extract the binary
docker run --rm p120ph37/busyq cat /busyq > busyq && chmod +x busyq

# Create a self-contained script binary
cat busyq myscript.sh > myapp && chmod +x myapp
./myapp arg1 arg2

# With gzip compression
{ cat busyq; gzip -9c myscript.sh; } > myapp && chmod +x myapp
```

## Custom builds

The `p120ph37/busyq:custom` image lets you build minimal busyq binaries containing only the tools your script needs. This dramatically reduces binary size by letting LTO strip unused code.

### Automatic (scan + build)

```sh
# Build a minimal binary for your script
docker run --rm -i p120ph37/busyq:custom < myscript.sh > mybinary
chmod +x mybinary

# With embedded script overlay
docker run --rm -i p120ph37/busyq:custom --embed < myscript.sh > mybinary
chmod +x mybinary

# With extra applets not detected by scanning
docker run --rm -i p120ph37/busyq:custom --applets curl,jq < myscript.sh > mybinary
chmod +x mybinary
```

### Manual (specify applets directly)

```sh
# Build with specific applets only (no script scanning)
docker run --rm p120ph37/busyq:custom --applets curl,jq,ls --no-script > mybinary
chmod +x mybinary
```

### Options

| Flag | Description |
|------|-------------|
| `--embed` | Embed the input script as an overlay in the output binary |
| `--ssl` | Use the SSL variant (includes mbedtls + CA certificates) |
| `--applets LIST` | Comma-separated list of additional applets to include |
| `--no-script` | Skip script scanning (use with `--applets` for manual builds) |

## Built-in tools

Over 200 commands from these packages:

- **GNU bash** 5.3 — shell
- **curl** 8.18 — HTTP client (with SSL/TLS in the default image)
- **jq** 1.8 — JSON processor
- **GNU coreutils** 9.5 — cat, ls, cp, mv, sort, date, etc. (79 commands)
- **GNU gawk** — awk
- **GNU sed** — stream editor
- **GNU grep** — grep, egrep, fgrep
- **GNU diffutils** — diff, cmp, diff3, sdiff
- **GNU findutils** — find, xargs
- **GNU ed** — line editor
- **GNU patch** — patch
- **GNU tar** — archiver
- **gzip, bzip2, xz, lzop** — compression
- **GNU cpio** — cpio archiver
- **Info-ZIP** — zip, unzip
- **GNU bc** — calculator (bc, dc)
- **less** — pager
- **GNU strings** — binary string extractor
- **GNU time** — process timer
- **dos2unix** — line ending converter
- **GNU sharutils** — uuencode, uudecode
- **tset/reset** — terminal setup
- **GNU which** — command locator
- **GNU wget** — HTTP downloader
- **OpenBSD netcat** — nc
- **iputils** — ping
- **hostname** — hostname utility
- **whois** — whois lookup
- **procps-ng** — ps, free, top, pgrep, pmap, etc.
- **psmisc** — killall, fuser, pstree
- **lsof** — open file lister
- **util-linux** — cal, flock, hexdump, column, nsenter, unshare, etc. (50+ commands)
- **xxd** — hex dump tool

## Building from source

```sh
docker buildx build --output=out .
```

Produces `out/busyq` (SSL), `out/busyq-nossl`, plus library artifacts for custom builds.

## License

The busyq integration code is MIT-licensed. Bundled components retain their original licenses (GPL-3.0+, MIT, BSD, Apache-2.0 — see individual packages).
