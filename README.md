# Navidrome (RPi4 Optimized)

This is a personal Docker image for `Navidrome`, specifically built and optimized for the **Raspberry Pi 4** (ARM64 Cortex-A72).

It is built from source, including a custom static **FFmpeg** build, and runs on top of a minimal **Distroless** image for security and efficiency.

## Features & Improvements
- **Architecture**: **ARM64** only, specifically optimized for **Raspberry Pi 4** (`-mcpu=cortex-a72`).
- **Base Image**: `gcr.io/distroless/cc-debian13` (Minimal, Secure, No Shell).
- **FFmpeg**: Built statically with `NEON` optimizations enabled.
  - **Codecs**: `libopus`, `libmp3lame` included.
- **Navidrome**: Built from source matching the latest tagged release.

## Build Policy
The GitHub Actions workflow runs daily to check for:
1. New **Navidrome** releases.
2. New **FFmpeg** tags.
3. Updates to **Distroless** base image.
4. Updates to **libs** (Opus, TagLib, etc).

If any change is detected, the image is automatically rebuilt and published to GHCR.

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
