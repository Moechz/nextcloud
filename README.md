# nextcloud-for-tos

> TerraMaster TOS 7 App Center — **Docker application** package for
> [Nextcloud](https://github.com/linuxserver/docker-nextcloud).

## What this is

A four-file TOS Docker application archive (`nextclouddocker.tar.gz`) that installs
Nextcloud on TOS 7 through the App Center:

- `config.ini` — TOS application metadata (`application_type: docker`, id `nextclouddocker`)
- `nextclouddocker.lang` — 23-language superset (TOS requires 14)
- `nextclouddocker.svg` — application icon (873 bytes, 2 SVG elements)
- `docker-compose.yml` — one service, image `linuxserver/nextcloud:35.0.2-ls461`

## How it works

| | |
|---|---|
| Container image | `linuxserver/nextcloud:35.0.2-ls461` (Docker Hub, used unmodified) |
| Open | `http://<NAS-IP>:8014/` (container port 8080) |
| Runs as | non-root, `user: "1000:1000"` |
| Persistent data | `/config` → `/Volume1/DockerAppData/nextclouddocker/config`, `/data` → `/Volume1/DockerAppData/nextclouddocker/data` |
| Logs | `docker logs nextclouddocker` (stdout/stderr) |

`config` holds the Nextcloud code, configuration and app-store data; `data` holds the user files and the SQLite database. Copying both folders is a complete backup.

## Design highlights

- **Non-root.** `user: "1000:1000"`; verified on real hardware (the container reports uid 1000).
- **Entrypoint wrapper**: the upstream image is built to run as root and keeps state in root-owned paths, so the compose file replaces the entrypoint with `src/entrypoint.sh`, which makes the service run as an unprivileged user. See that file for the details.
- **Fixed image tag, never `:latest`**, Docker Hub only, no `privileged`, no `network_mode: host`, and no Docker socket, no `cap_add`.
- **Health check** probing the service on container port 8080.
- **Deterministic build**: GNU tar with uid/gid 0 and zeroed timestamps, gzip without a timestamp, plus the review-standards self-check above.
- **Non-root, no s6.** The upstream image starts s6-overlay as root and drops to its internal user; this entrypoint bypasses s6 and starts nginx and PHP-FPM directly as uid 1000, with PID, temporary and log paths below `/config` and `/tmp`.
- **Code and data in the volumes.** The application code is seeded from `/app/www/src` into `/config/www/nextcloud` on first start (and refreshed when the image version changes); the user data directory is `/data`, so nothing writable lives in the image.
- **SQLite by default.** The container needs no external database; the first-run page creates the admin account and the database in `/data`.
- **Health check** probes `/status.php`, which answers even before the first-run wizard is completed.
- **Fixed image tag, never `:latest`**, Docker Hub only, no `privileged`, no `network_mode: host`, no Docker socket, no `cap_add`.

## Runtime file manifest

Everything the application writes on the NAS lives inside its own data
directory; the container-internal `/tmp` is discarded with the container. The
table lists what is created and how it behaves. Nothing else is written.

| Path | Purpose | Created when | Growth bound | Lifecycle |
|---|---|---|---|---|
| `config/www/nextcloud/version.php` | Nextcloud code version marker (the code is seeded here on first start) | first start | static | refreshed when the image version changes |
| `config/www/nextcloud/config/config.php` | Nextcloud configuration and installed-app state | first start | grows with settings and apps | never overwritten; back it up |
| `/Volume1/DockerAppData/nextclouddocker/config` | Nextcloud application data (everything the container writes outside /tmp) | on first start / on demand | bounded by your own data | persistent; kept on uninstall unless you ask to delete it |
| `/Volume1/DockerAppData/nextclouddocker/data` | Nextcloud application data (everything the container writes outside /tmp) | on first start / on demand | bounded by your own data | persistent; kept on uninstall unless you ask to delete it |

## Architectures

The TOS store takes one package per architecture. This release provides both,
built from the same sources by `scripts/build-dual.sh`:

| Architecture | Package | Size | SHA-256 |
|---|---|---|---|
| x86_64 | `nextclouddocker_x86_64.tar.gz` | 6239 B | `f079a64da1f1b64a59b8b4d46815873895a81482961a4c0f5b9caa95c28881f7` |
| aarch64 | `nextclouddocker_aarch64.tar.gz` | 6237 B | `39a580a1294cdd27c89de62c94e15e7d62314c176630de1af9283ca0873b227b` |

The x86_64 package was verified with the full on-device E2E; the aarch64 package
passes the official `TOSAppSelfTestingTool -c` check and the developer platform's
automated validation (no ARM host was available for a container E2E).

## Build

```bash
scripts/build.sh                  # -> out/nextclouddocker.tar.gz + .sha256
scripts/build.sh 35.0.2-2   # packaging iteration bump
scripts/build.sh 35.0.2-1 aarch64
```

The build stages the four files, substitutes the version/platform placeholders,
embeds `src/entrypoint.sh` into the compose file (escaping every `$` as `$$`), removes CRLF/BOM/AppleDouble, then runs
`tools/verify.py`, a review-standards self-check (archive layout, JSON validity,
required fields, 14+ language coverage, version consistency, Docker-Hub-only
images, fixed tag, reserved/recommended host ports, non-root user, per-service
healthcheck/TZ/restart, data path below the application data root, never the
`/Volume*` wildcard, comment-free sequence blocks, `x-app-meta` position, no
literal secrets and the SVG size/element limits).

## Local verification

```bash
./TOSAppSelfTestingTool -c out/nextclouddocker.tar.gz   # official spec check
bash test/install-and-verify.sh                  # on-device E2E (needs root)
```

> Docker applications cannot be side-loaded through the App Center's manual
> install page (it accepts `.deb` only); the official self-testing tool's `-i`
> mode or `docker compose` are the only ways to install one for testing.

## Store submission checklist

1. Public GitHub repo (code + README only).
2. Release **tag `v35.0.2-1`**, assets `nextclouddocker.tar.gz` +
   `nextclouddocker.tar.gz.sha256` (Docker asset naming: `<app_id>.tar.gz`, **no
   platform suffix**).
3. Developer platform → Add Application: ID `nextclouddocker`, package type Docker,
   repository URL, architecture `x86_64`.
4. Version Management → Add Version `35.0.2-1` → automated validation → review.

## License / branding

Nextcloud is distributed by its upstream authors under **GPL-3.0-only**. The container image is the official image from Docker Hub (`linuxserver/nextcloud:35.0.2-ls461`) and is used unmodified; no upstream source code is redistributed here. This packaging is an independent community submission by Moechz and is not affiliated with the upstream project or TerraMaster.

## Limitations

SQLite is the only database in this package; there is no external database, Redis, or object storage integration. It is intended for home and small-team use.
The user data directory is `/data`; files are stored in the application data folder, not in a TOS shared folder.
The page is plain HTTP on the LAN and has no TLS. Put a TLS reverse proxy in front before exposing it to the internet.
The first start copies the Nextcloud code (about 830 MB) into the data volume, which takes a few seconds on a local disk and uses that space.
Docker applications cannot be upgraded in place in the App Center: updating means uninstalling and reinstalling, which keeps the data folders.

---

Packaged for TOS 7 by Moechz. Upstream image used unmodified from Docker Hub.
