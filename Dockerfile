#
# Navidrome (RPi4 Optimized)
#
# Stage 1: Builder
FROM debian:trixie-slim AS builder

ENV LC_ALL=C.UTF-8
ENV LANG=C.UTF-8
ENV DEBIAN_FRONTEND=noninteractive

# 1. Install System Dependencies
RUN apt-get update && apt-get upgrade -y && apt-get install -y --no-install-recommends \
    build-essential \
    pkg-config \
    git \
    wget \
    curl \
    ca-certificates \
    python3 \
    # Build Tools
    cmake \
    autoconf \
    automake \
    libtool \
    nasm \
    yasm \
    # Go & Node (Install dynamically)
    # Cleanup
    && rm -rf /var/lib/apt/lists/*

# Install Node.js 24 (LTS)
RUN echo "[SETUP] Installing Node.js 24..." && \
    curl -fsSL https://deb.nodesource.com/setup_24.x | bash - && \
    apt-get install -y nodejs && \
    npm install -g npm@latest

# Install Go (Latest Stable usually required for Navidrome)
# We will use a fixed recent version or fetch via arg, but for now hardcode a known good generic or script?
# Better to use the requested arg or just fetch standard. 
# Plan: Download Go in the Navidrome build step.

# Arguments (Versions)
ARG NAVIDROME_VERSION
ARG FFMPEG_VERSION
ARG OPUS_VERSION
ARG MP3LAME_VERSION
ARG TAGLIB_VERSION

# Optimization Flags (RPi4 / Cortex-A72)
ARG CFLAGS="-O3 -mcpu=cortex-a72 -fstack-protector-strong -D_FORTIFY_SOURCE=2"
ARG CXXFLAGS="-O3 -mcpu=cortex-a72 -fstack-protector-strong -D_FORTIFY_SOURCE=2"
ARG LDFLAGS="-Wl,-z,relro -Wl,-z,now"

# Working Directory
WORKDIR /build

# -----------------------------------------------------------------------------
# 2. Build Dependencies (Audio Codecs)
# -----------------------------------------------------------------------------

# LAME (MP3)
RUN echo "[BUILD] Building Lame ${MP3LAME_VERSION}..." && \
    wget "https://downloads.sourceforge.net/project/lame/lame/${MP3LAME_VERSION}/lame-${MP3LAME_VERSION}.tar.gz" -O lame.tar.gz && \
    tar xzf lame.tar.gz && \
    cd lame-${MP3LAME_VERSION} && \
    ./configure \
      --prefix=/usr/local \
      --enable-static \
      --disable-shared \
      --enable-nasm \
      && \
    make -j$(nproc) "CFLAGS=${CFLAGS}" && \
    make install && \
    cd .. && rm -rf lame*

# Opus
RUN echo "[BUILD] Building Opus ${OPUS_VERSION}..." && \
    wget "https://github.com/xiph/opus/releases/download/v${OPUS_VERSION}/opus-${OPUS_VERSION}.tar.gz" -O opus.tar.gz && \
    tar xzf opus.tar.gz && \
    cd opus-${OPUS_VERSION} && \
    ./configure \
      --prefix=/usr/local \
      --enable-static \
      --disable-shared \
      --disable-doc \
      --disable-extra-programs \
      && \
    make -j$(nproc) "CFLAGS=${CFLAGS}" && \
    make install && \
    cd .. && rm -rf opus*

# TagLib (Needed for Navidrome)
RUN echo "[BUILD] Building TagLib ${TAGLIB_VERSION}..." && \
    wget "https://taglib.github.io/releases/taglib-${TAGLIB_VERSION}.tar.gz" -O taglib.tar.gz && \
    tar xzf taglib.tar.gz && \
    cd taglib-${TAGLIB_VERSION} && \
    cmake -B build \
      -DCMAKE_INSTALL_PREFIX=/usr/local \
      -DCMAKE_BUILD_TYPE=Release \
      -DBUILD_SHARED_LIBS=OFF \
      -DWITH_ZLIB=OFF \
      -DCMAKE_CXX_FLAGS="${CXXFLAGS}" \
      -DCMAKE_C_FLAGS="${CFLAGS}" \
      && \
    cmake --build build --parallel $(nproc) && \
    cmake --install build && \
    cd .. && rm -rf taglib*

# -----------------------------------------------------------------------------
# 3. Build FFmpeg
# -----------------------------------------------------------------------------
RUN echo "[BUILD] Building FFmpeg ${FFMPEG_VERSION}..." && \
    # FFmpeg releases are usually tarballs. Only snapshot is git. We'll assume tarball for named version.
    wget "https://ffmpeg.org/releases/ffmpeg-${FFMPEG_VERSION}.tar.xz" -O ffmpeg.tar.xz && \
    tar xf ffmpeg.tar.xz && \
    cd ffmpeg-${FFMPEG_VERSION} && \
    ./configure \
      --prefix=/usr/local \
      --pkg-config-flags="--static" \
      --extra-cflags="${CFLAGS}" \
      --extra-ldflags="${LDFLAGS} -static" \
      --extra-libs="-lpthread -lm" \
      --bindir="/usr/local/bin" \
      --enable-static \
      --disable-shared \
      --disable-ffplay \
      --disable-ffprobe \
      --disable-doc \
      --disable-network \
      # Minimal Audio Only
      --disable-everything \
      --enable-protocol=file \
      --enable-libmp3lame \
      --enable-libopus \
      # Decoders (Common Audio)
      --enable-decoder=aac \
      --enable-decoder=libopus \
      --enable-decoder=mp3 \
      --enable-decoder=flac \
      --enable-decoder=alac \
      --enable-decoder=pcm_s16le \
      --enable-decoder=wavpack \
      # Encoders (Transcoding Targets)
      --enable-encoder=aac \
      --enable-encoder=libopus \
      --enable-encoder=libmp3lame \
      # Muxers/Demuxers
      --enable-muxer=adts \
      --enable-muxer=opus \
      --enable-muxer=mp3 \
      --enable-muxer=flac \
      --enable-muxer=ipod \
      --enable-demuxer=aac \
      --enable-demuxer=ogg \
      --enable-demuxer=mp3 \
      --enable-demuxer=flac \
      --enable-demuxer=wav \
      --enable-demuxer=mov \
      --enable-demuxer=m4a \
      # Filters (Resampling is critical for transcoding)
      --enable-filter=aresample \
      # Hardware
      --enable-neon \
      --enable-asm \
      && \
    make -j$(nproc) && \
    make install && \
    cd .. && rm -rf ffmpeg*

# -----------------------------------------------------------------------------
# 4. Build Navidrome
# -----------------------------------------------------------------------------
# Install Go
RUN echo "[SETUP] Installing Go..." && \
    GO_DL_ARCH="arm64" && \
    # Fetch latest stable Go (or semi-hardcoded, update as needed)
    GO_VER="1.23.4" && \
    wget "https://go.dev/dl/go${GO_VER}.linux-${GO_DL_ARCH}.tar.gz" && \
    rm -rf /usr/local/go && tar -C /usr/local -xzf go${GO_VER}.linux-${GO_DL_ARCH}.tar.gz && \
    rm go${GO_VER}.linux-${GO_DL_ARCH}.tar.gz

ENV PATH="/usr/local/go/bin:${PATH}"

RUN echo "[BUILD] Building Navidrome ${NAVIDROME_VERSION}..." && \
    git clone --depth 1 --branch "v${NAVIDROME_VERSION}" https://github.com/navidrome/navidrome.git && \
    cd navidrome && \
    # Frontend
    make setup && \
    make buildjs && \
    # Backend
    # Navidrome uses a specific build script/Makefile usually, but we want explicit control for static link
    # Check if they have a 'build' target. Usually: 'go build'
    # We must link taglib static. pkg-config is handled by CGO usually.
    # We force static link.
    export CGO_ENABLED=1 && \
    export CGO_LDFLAGS="-L/usr/local/lib -ltag -lz -lstdc++ -lm" && \
    export CGO_CFLAGS="-I/usr/local/include/taglib -I/usr/local/include" && \
    go build -tags=netgo -ldflags "-extldflags '-static' -X github.com/navidrome/navidrome/resources.Commit=$(git rev-parse HEAD) -X github.com/navidrome/navidrome/resources.Tag=v${NAVIDROME_VERSION}" -o navidrome . && \
    cp navidrome /usr/local/bin/navidrome && \
    cd .. && rm -rf navidrome

# -----------------------------------------------------------------------------
# 5. User Setup
# -----------------------------------------------------------------------------
RUN useradd -u 1000 -s /bin/false -d /data navidrome && \
    mkdir -p /data /music && \
    chown -R navidrome:navidrome /data /music

# -----------------------------------------------------------------------------
# Stage 2: Final (Distroless)
# -----------------------------------------------------------------------------
FROM gcr.io/distroless/cc-debian13
LABEL maintainer="JoanMorera"

# Copy user
COPY --from=builder /etc/passwd /etc/passwd
COPY --from=builder /etc/group /etc/group

# Copy Binaries
COPY --from=builder --chown=navidrome:navidrome /usr/local/bin/navidrome /navidrome
COPY --from=builder --chown=navidrome:navidrome /usr/local/bin/ffmpeg /usr/bin/ffmpeg

# Configuration
ENV ND_MUSICFOLDER="/music" \
    ND_DATAFOLDER="/data" \
    ND_SCANSCHEDULE="@every 1h" \
    ND_LOGLEVEL="info" \
    ND_FFMPEG="/usr/bin/ffmpeg"

WORKDIR /data
VOLUME ["/data", "/music"]

EXPOSE 4533

USER navidrome

ENTRYPOINT ["/navidrome"]
