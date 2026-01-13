# Navidrome (RPi4 Optimized)

This is a personal Docker image for `Navidrome`, specifically built and optimized for the **Raspberry Pi 4** (ARM64 Cortex-A72).

It is built from source, including a custom static **FFmpeg** build, and runs on top of a minimal **Distroless** image for security and efficiency.

## Features & Improvements
- **Architecture**: **ARM64** only, specifically optimized for **Raspberry Pi 4** (`-mcpu=cortex-a72`).
- **Base Image**: `scratch` (Empty).
  - The final image is a **single layer** containing only the static binaries and necessary system files (certs, timezone).
  - Built using **Arch Linux** to leverage the latest compiler optimizations and libraries.
- **FFmpeg**: **Audio-Only** Minimal Build. Statically compiled with `NEON` optimizations.
  - **Included Codecs**: `AAC`, `Opus` (`libopus`), `MP3` (`libmp3lame`), `FLAC`, `ALAC`.
  - **Bloat Removed**: Video support, network protocols (except pipe/file), and unused filters are disabled to keep the image small and efficient.
- **Navidrome**: Built from the latest available Git commit (**Bleeding Edge**).

## Build Policy
The GitHub Actions workflow runs **Weekly (Sundays)** to check for updates.
Everything is built from the **latest Git commit (HEAD)** of the respective repositories:
1. **Navidrome** (GitHub)
2. **FFmpeg** (GitHub Mirror)
3. **Opus** (Xiph GitHub)
4. **Lame** (Debian Salsa)
5. **TagLib** (GitHub)

If any new link in the chain has a new commit, a fresh image is rebuilt and published to GHCR.

## Usage
The container is configured to use `/data` for configuration and `/music` for your library.

### Basic Usage
```bash
docker run -d \
  --name navidrome \
  --restart=unless-stopped \
  -p 4533:4533 \
  -v /path/to/data:/data \
  -v /path/to/music:/music \
  ghcr.io/joan-morera/navidrome:rpi4
```

### Docker Compose
```yaml
services:
  navidrome:
    image: ghcr.io/joan-morera/navidrome:rpi4
    container_name: navidrome
    restart: unless-stopped
    ports:
      - "4533:4533"
    environment:
      # Optional: Custom settings
      ND_LOGLEVEL: info
    volumes:
      - ./data:/data
      - /path/to/music:/music
```

> **Note**: Permissions
> The container runs as user `navidrome` (UID 1000). Ensure your volume paths are writable by UID 1000.
