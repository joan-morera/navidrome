# qBittorrent Static

This is a personal Docker image for `qBittorrent-nox`, built statically.

I was using the linuxserver.io alpine version but noticed performance issues with `malloc-ng` (high CPU usage/interrupts). I wanted something more optimized, so I rebuilt it using `mimalloc`.

I also decided to build everything statically and mount it over distroless for superior security and a minimal footprint. 

## Features & Improvements
- **Size**: ~64MB Uncompressed.
- **Arch**: Multi-arch (AMD64, ARM64) plus a specifically optimized build for RPi4 (Cortex-A72).
- **Security**: Runs as a dedicated non-root user (`qbt`) inside a shell-less Distroless container.
- **Optimization**: Built with `LTO`, `-O3`, and `mimalloc` (replacing the standard allocator).
  - **Dependencies**: All key C++ dependencies (**Libtorrent, Qt, Boost, Mimalloc**) are also statically compiled with these hardened optimization flags.
  - **RPi4**: The ARM64 variant is specifically tuned with `-mcpu=cortex-a72`.

## Build Policy & Versions
The GitHub Actions workflow runs daily to check for:
1. New **qBittorrent/Libtorrent/Qt** releases (tags) from upstream repositories.
2. Updates to the underlying **Distroless** base image.

If any change is detected, the image is automatically rebuilt and published.
    
## Packages & Tags

I publish two separate packages depending on the **Libtorrent** version you need.

### Package 1: `qbittorrent` (Libtorrent V1)
> **Recommended**. V1 is generally more performant for high-throughput seeding on limited hardware and has wider tracker support.

| Tag | Architecture | Libtorrent | Description |
| :--- | :--- | :--- | :--- |
| `latest` | Multi-Arch | v1.2.x | Generic Stable (AMD64/ARM64) |
| `amd64` | `x86_64` | v1.2.x | Generic AMD64 |
| `arm64` | `aarch64` | v1.2.x | Generic ARM64 |
| `rpi4` | `aarch64` | v1.2.x | **RPi4 Optimized** (Cortex-A72) |

### Package 2: `qbittorrent-lt2` (Libtorrent V2)
> Builds from the default branch (HEAD) of Libtorrent. Support for BitTorrent v2 hybrid torrents. Uses latest Boost libraries.

| Tag | Architecture | Libtorrent | Description |
| :--- | :--- | :--- | :--- |
| `latest` | Multi-Arch | v2.0.x (HEAD) | Generic Stable (AMD64/ARM64) |
| `amd64` | `x86_64` | v2.0.x (HEAD) | Generic AMD64 |
| `arm64` | `aarch64` | v2.0.x (HEAD) | Generic ARM64 |
| `rpi4` | `aarch64` | v2.0.x (HEAD) | **RPi4 Optimized** (Cortex-A72) |

## Usage
The container is configured to store all data and configuration in `/home/qbt` (which you should mount as a volume).

### Basic Usage
```bash
docker run -d \
  --name qbittorrent \
  -p 8080:8080 \
  -p 6881:6881 \
  -p 6881:6881/udp \
  -v qbt_data:/home/qbt \
  ghcr.io/joan-morera/qbittorrent:rpi4
```

### Docker Compose
```yaml
services:
  qbittorrent:
    image: ghcr.io/joan-morera/qbittorrent:latest
    container_name: qbittorrent
    restart: unless-stopped
    ports:
      - "8080:8080"
      - "6881:6881"
      - "6881:6881/udp"
    volumes:
      - qbt_data:/home/qbt
      - /path/to/downloads:/downloads

volumes:
  qbt_data:
```

> Note: Adjust volume paths and PUID/PGID to match your host permissions.
