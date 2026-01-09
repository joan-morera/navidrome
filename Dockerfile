#
# Navidrome (RPi4 Optimized) - Bleeding Edge
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
    zlib1g-dev \
    # Go & Node (Install dynamically)
    # Cleanup
    && rm -rf /var/lib/apt/lists/*

# Install Node.js 24 (LTS)
RUN echo "[SETUP] Installing Node.js 24..." && \
    curl -fsSL https://deb.nodesource.com/setup_24.x | bash - && \
    apt-get install -y nodejs && \
    npm install -g npm@latest

# Install Go (Latest Stable usually required for Navidrome)
RUN echo "[SETUP] Installing Go..." && \
    GO_DL_ARCH="arm64" && \
    # Fetch latest stable Go (or semi-hardcoded, update as needed)
    GO_VER="1.23.4" && \
    wget "https://go.dev/dl/go${GO_VER}.linux-${GO_DL_ARCH}.tar.gz" && \
    rm -rf /usr/local/go && tar -C /usr/local -xzf go${GO_VER}.linux-${GO_DL_ARCH}.tar.gz && \
    rm go${GO_VER}.linux-${GO_DL_ARCH}.tar.gz

ENV PATH="/usr/local/go/bin:${PATH}"

# Arguments (Versions = Commit SHAs)
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

# LAME (MP3) - From Debian Salsa (Multimedia Team)
RUN echo "[BUILD] Building Lame (Commit: ${MP3LAME_VERSION})..." && \
    git clone https://salsa.debian.org/multimedia-team/lame.git lame-src && \
    cd lame-src && \
    git checkout ${MP3LAME_VERSION} && \
    ./configure \
      --prefix=/usr/local \
      --enable-static \
      --disable-shared \
      --enable-nasm \
      && \
    make -j$(nproc) "CFLAGS=${CFLAGS}" && \
    make install && \
    cd .. && rm -rf lame-src

# Opus - From GitHub
RUN echo "[BUILD] Building Opus (Commit: ${OPUS_VERSION})..." && \
    git clone https://github.com/xiph/opus.git opus-src && \
    cd opus-src && \
    git checkout ${OPUS_VERSION} && \
    ./autogen.sh && \
    ./configure \
      --prefix=/usr/local \
      --enable-static \
      --disable-shared \
      --disable-doc \
      --disable-extra-programs \
      && \
    make -j$(nproc) "CFLAGS=${CFLAGS}" && \
    make install && \
    cd .. && rm -rf opus-src

# TagLib (Needed for Navidrome) - From GitHub
RUN echo "[BUILD] Building TagLib (Commit: ${TAGLIB_VERSION})..." && \
    git clone https://github.com/taglib/taglib.git taglib-src && \
    cd taglib-src && \
    git checkout ${TAGLIB_VERSION} && \
    git submodule update --init --recursive && \
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
    cd .. && rm -rf taglib-src

# -----------------------------------------------------------------------------
# 3. Build FFmpeg - From Git (GitHub Mirror)
# -----------------------------------------------------------------------------
RUN echo "[BUILD] Building FFmpeg (Commit: ${FFMPEG_VERSION})..." && \
    git clone https://github.com/FFmpeg/FFmpeg.git ffmpeg-src && \
    cd ffmpeg-src && \
    git checkout ${FFMPEG_VERSION} && \
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
      --enable-protocol=pipe \
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
      --enable-muxer=null \
      --enable-demuxer=aac \
      --enable-demuxer=ogg \
      --enable-demuxer=mp3 \
      --enable-demuxer=flac \
      --enable-demuxer=wav \
      --enable-demuxer=mov \
      --enable-demuxer=m4a \
      --enable-demuxer=null \
      # Filters (Resampling is critical for transcoding)
      --enable-filter=aresample \
      --enable-filter=anull \
      # Hardware
      --enable-neon \
      --enable-asm \
      && \
    make -j$(nproc) && \
    make install && \
    cd .. && rm -rf ffmpeg-src

# -----------------------------------------------------------------------------
# 4. Build Navidrome - From GitHub (HEAD)
# -----------------------------------------------------------------------------
RUN echo "[BUILD] Building Navidrome (Commit: ${NAVIDROME_VERSION})..." && \
    git clone https://github.com/navidrome/navidrome.git navidrome-src && \
    cd navidrome-src && \
    git checkout ${NAVIDROME_VERSION} && \
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
    go build -tags=netgo -ldflags "-extldflags '-static' -X github.com/navidrome/navidrome/resources.Commit=$(git rev-parse HEAD) -X github.com/navidrome/navidrome/resources.Tag=0.0.0-HEAD" -o navidrome . && \
    cp navidrome /usr/local/bin/navidrome && \
    cd .. && rm -rf navidrome-src

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
