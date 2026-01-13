#
# Navidrome (RPi4 Optimized) - Bleeding Edge
#
# Stage 1: Builder
FROM ogarcia/archlinux:latest AS builder

ENV LC_ALL=C.UTF-8
ENV LANG=C.UTF-8

# 1. Install System Dependencies (Arch Linux)
# base-devel: includes gcc, make, etc.
# go, nodejs, npm: Latest versions are in Arch repos
RUN pacman -Syu --noconfirm && \
    pacman -S --noconfirm \
    base-devel \
    git \
    wget \
    curl \
    cmake \
    nasm \
    yasm \
    go \
    nodejs \
    npm \
    python \
    tzdata

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

# PKG_CONFIG_PATH for /usr/local (libs built from source)
ENV PKG_CONFIG_PATH="/usr/local/lib/pkgconfig:/usr/local/lib64/pkgconfig:${PKG_CONFIG_PATH}"

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
    export CGO_ENABLED=1 && \
    export CGO_LDFLAGS="-L/usr/local/lib -ltag -lz -lstdc++ -lm" && \
    export CGO_CFLAGS="-I/usr/local/include/taglib -I/usr/local/include" && \
    go build -tags=netgo -ldflags "-extldflags '-static' -X github.com/navidrome/navidrome/resources.Commit=$(git rev-parse HEAD) -X github.com/navidrome/navidrome/resources.Tag=0.0.0-HEAD" -o navidrome . && \
    cp navidrome /usr/local/bin/navidrome && \
    cd .. && rm -rf navidrome-src

# -----------------------------------------------------------------------------
# 5. User Setup
# -----------------------------------------------------------------------------
RUN useradd -u 1000 -U -s /bin/false -d /data navidrome && \
    mkdir -p /data /music && \
    chown -R navidrome:navidrome /data /music

# -----------------------------------------------------------------------------
# Stage 2: Final (Scratch)
# -----------------------------------------------------------------------------
FROM scratch
LABEL maintainer="JoanMorera"

# 1. SSL Certs (Critical for HTTPS)
COPY --from=builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/

# 2. Timezone Data
COPY --from=builder /usr/share/zoneinfo /usr/share/zoneinfo

# 3. Users/Groups
COPY --from=builder /etc/passwd /etc/passwd
COPY --from=builder /etc/group /etc/group

# 4. Binaries
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
