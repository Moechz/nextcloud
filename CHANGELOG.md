# Changelog

All notable user-visible changes to the Nextcloud TOS application package.

## 35.0.2-1 — 2026-11-08

### Added
- First release. Nextcloud (`linuxserver/nextcloud:35.0.2-ls461`, Docker Hub official image, unmodified)
  packaged as a TOS 7 Docker application, published on port 8014 and running
  as a non-root user (1000:1000).
- Persistent data is kept under `/Volume1/DockerAppData/nextclouddocker/`.

### Architectures
- Dual-architecture release: `nextclouddocker_x86_64.tar.gz` (6239 B, `f079a64da1f1b64a59b8b4d46815873895a81482961a4c0f5b9caa95c28881f7`) and
  `nextclouddocker_aarch64.tar.gz` (6237 B, `39a580a1294cdd27c89de62c94e15e7d62314c176630de1af9283ca0873b227b`), built by `scripts/build-dual.sh`.
  x86_64 has the full on-device E2E; aarch64 passes the official check and the
  platform validation (no ARM host available for a container E2E).
