#
# Static qBittorrent (RPi4 Optimized)
#
# Stage 1: Builder
FROM debian:trixie-slim AS builder

ENV LC_ALL=C.UTF-8
ENV LANG=C.UTF-8

# 1. Install System Dependencies
RUN apt-get update && apt-get upgrade -y && apt-get install -y --no-install-recommends \
    locales \
    build-essential \
    cmake \
    git \
    wget \
    curl \
    python3 \
    python3-dev \
    perl \
    ninja-build \
    pkg-config \
    libclang-rt-dev \
    ca-certificates \
    linux-headers-generic \
    # Build dependencies
    zlib1g-dev \
    libzstd-dev \
    zstd \
    && rm -rf /var/lib/apt/lists/*

# Arguments (Versions)
ARG QBITTORRENT_VERSION
ARG LIBTORRENT_VERSION
ARG QT_VERSION
ARG BOOST_VERSION
ARG OPENSSL_VERSION
ARG MIMALLOC_VERSION

# Common Hardening & Optimization Flags
# Defaults are for "Generic" optimized build (-O3).
# RPi4 specific flags (-mcpu=cortex-a72) are passed via build-args.
ARG CFLAGS="-O3 -fstack-protector-strong -D_FORTIFY_SOURCE=2 -Wformat -Werror=format-security"
ARG CXXFLAGS="-O3 -fstack-protector-strong -D_FORTIFY_SOURCE=2 -Wformat -Werror=format-security -flto"
ARG LDFLAGS="-Wl,-z,relro -Wl,-z,now -flto"

# Working Directory
WORKDIR /build

# -----------------------------------------------------------------------------
# 2. Build OpenSSL (Static)
# -----------------------------------------------------------------------------
ARG TARGETARCH
RUN echo "[BUILD] Building OpenSSL ${OPENSSL_VERSION} for ${TARGETARCH}..." && \
    wget "https://github.com/openssl/openssl/archive/refs/tags/${OPENSSL_VERSION}.tar.gz" -O openssl.tar.gz && \
    tar xzf openssl.tar.gz && \
    cd openssl-openssl-$(echo $OPENSSL_VERSION | sed 's/openssl-//') && \
    # Determine Architecture
    if [ "$TARGETARCH" = "amd64" ]; then \
        OPENSSL_TARGET="linux-x86_64"; \
    elif [ "$TARGETARCH" = "arm64" ]; then \
        OPENSSL_TARGET="linux-aarch64"; \
    else \
        echo "Unsupported architecture: $TARGETARCH"; exit 1; \
    fi && \
    ./config --prefix=/usr/local --openssldir=/usr/local/ssl no-shared $OPENSSL_TARGET && \
    make -j$(nproc) && \
    make install_sw && \
    cd .. && rm -rf openssl*

# -----------------------------------------------------------------------------
# 3. Build Mimalloc (Static)
# -----------------------------------------------------------------------------
RUN echo "[BUILD] Building Mimalloc ${MIMALLOC_VERSION}..." && \
    wget "https://github.com/microsoft/mimalloc/archive/refs/tags/${MIMALLOC_VERSION}.tar.gz" -O mimalloc.tar.gz && \
    tar xzf mimalloc.tar.gz && \
    cd mimalloc-$(echo $MIMALLOC_VERSION | sed 's/v//') && \
    mkdir build && cd build && \
    cmake \
      -DCMAKE_BUILD_TYPE=Release \
      -DMI_BUILD_STATIC=ON \
      -DMI_BUILD_SHARED=OFF \
      -DMI_OVERRIDE=ON \
      -DMI_INSTALL_TOPLEVEL=ON \
      -DCMAKE_C_FLAGS="$CFLAGS" \
      -DCMAKE_CXX_FLAGS="$CXXFLAGS" \
      .. && \
    make -j$(nproc) && \
    make install && \
    cd ../.. && rm -rf mimalloc*

# -----------------------------------------------------------------------------
# 4. Build Boost (Static)
# -----------------------------------------------------------------------------
# Boost formatting: boost-1.88.0 -> 1.88.0
RUN echo "[BUILD] Building Boost ${BOOST_VERSION}..." && \
    BOOST_VER_CLEAN=$(echo $BOOST_VERSION | sed 's/boost-//') && \
    BOOST_VER_CLEAN=$(echo $BOOST_VERSION | sed 's/boost-//') && \
    git clone --depth 1 --branch ${BOOST_VERSION} --recurse-submodules https://github.com/boostorg/boost.git boost-${BOOST_VERSION} && \
    cd boost-${BOOST_VERSION} && \
    ./bootstrap.sh --prefix=/usr/local && \
    ./b2 -j$(nproc) install \
      variant=release \
      link=static \
      threading=multi \
      runtime-link=static \
      cxxflags="$CXXFLAGS" \
      --with-system \
      --with-filesystem \
      --with-thread \
      --with-date_time \
      --with-chrono \
    && \
    cd .. && rm -rf boost*

# -----------------------------------------------------------------------------
# 5. Build Qt6 (Static, Minimal)
# -----------------------------------------------------------------------------
    # Qt is massive. We configure a very minimal build for qBittorrent-nox.
    # We fetch the 'qtbase' submodule directly to avoid downloading gigabytes of unused modules.
    RUN echo "[BUILD] Building Qt ${QT_VERSION}..." && \
    QT_VER_CLEAN=$(echo $QT_VERSION | sed 's/v//') && \
    QT_VER_SHORT=$(echo $QT_VER_CLEAN | cut -d. -f1-2) && \
    wget "https://download.qt.io/official_releases/qt/${QT_VER_SHORT}/${QT_VER_CLEAN}/submodules/qtbase-everywhere-src-${QT_VER_CLEAN}.tar.xz" -O qt.tar.xz && \
    tar xf qt.tar.xz && \
    cd qtbase-everywhere-src-${QT_VER_CLEAN} && \
    # Configure for static build
    ./configure \
      -prefix /usr/local \
      -static \
      -release \
      -optimize-size \
      -no-gui \
      -no-widgets \
      -no-dbus \
      -no-glib \
      -no-icu \
      -no-libpng \
      -no-libjpeg \
      -no-freetype \
      -no-harfbuzz \
      -no-sql-sqlite \
      -no-feature-accessibility \
      -no-feature-testlib \
      -no-feature-printsupport \
      -no-opengl \
      -no-vulkan \
      -opensource -confirm-license \
      -nomake examples -nomake tests \
      -platform linux-g++ \
      -- \
      -DCMAKE_CXX_FLAGS="$CXXFLAGS" \
      -DCMAKE_C_FLAGS="$CFLAGS" \
      && \
    cmake --build . --parallel $(nproc) && \
    cmake --install . && \
    cd .. && rm -rf qtbase-everywhere-src-${QT_VER_CLEAN} && \
    # Build qttools (needed for LinguistTools)
    wget "https://download.qt.io/official_releases/qt/${QT_VER_SHORT}/${QT_VER_CLEAN}/submodules/qttools-everywhere-src-${QT_VER_CLEAN}.tar.xz" -O qttools.tar.xz && \
    tar xf qttools.tar.xz && \
    cd qttools-everywhere-src-${QT_VER_CLEAN} && \
    /usr/local/bin/qt-configure-module . && \
    cmake --build . --parallel $(nproc) && \
    cmake --install . && \
    cd .. && rm -rf qttools*

# -----------------------------------------------------------------------------
# 6. Build Libtorrent (Static)
# -----------------------------------------------------------------------------
RUN echo "[BUILD] Building Libtorrent ${LIBTORRENT_VERSION}..." && \
    # Clone full repo (needed to checkout specific commit hash for V2)
    git clone --recurse-submodules https://github.com/arvidn/libtorrent.git && \
    cd libtorrent && \
    git checkout ${LIBTORRENT_VERSION} && \
    git submodule update --init --recursive && \
    cmake -B build -G Ninja \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_INSTALL_PREFIX=/usr/local \
      -DCMAKE_CXX_STANDARD=20 \
      -DBUILD_SHARED_LIBS=OFF \
      -Dstatic_runtime=ON \
      -Ddeprecated-functions=OFF \
      -DCMAKE_CXX_FLAGS="$CXXFLAGS" \
      && \
    cmake --build build --parallel $(nproc) && \
    cmake --install build && \
    cd .. && rm -rf libtorrent

# -----------------------------------------------------------------------------
# 7. Build qBittorrent (Static)
# -----------------------------------------------------------------------------
RUN echo "[BUILD] Building qBittorrent ${QBITTORRENT_VERSION}..." && \
    git clone --depth 1 --branch ${QBITTORRENT_VERSION} https://github.com/qbittorrent/qBittorrent.git && \
    cd qBittorrent && \
    cmake -B build -G Ninja \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_INSTALL_PREFIX=/usr/local \
      -DGUI=OFF \
      -DQT6=ON \
      -DSTACKTRACE=OFF \
      -DCMAKE_CXX_STANDARD=20 \
      -DCMAKE_CXX_FLAGS="$CXXFLAGS" \
      -DLIBS="-lmimalloc -latomic" \
      && \
    cmake --build build --parallel $(nproc) && \
    cmake --install build && \
    # Strip binary
    strip /usr/local/bin/qbittorrent-nox && \
    cd .. && rm -rf qBittorrent

# -----------------------------------------------------------------------------
# 8. User Setup
# -----------------------------------------------------------------------------
RUN useradd -u 1000 -s /bin/false -d /home/qbt qbt && \
    mkdir -p /home/qbt/data /usr/share/qbt && \
    chown -R qbt:qbt /home/qbt

# -----------------------------------------------------------------------------
# Stage 2: Final (Distroless)
# -----------------------------------------------------------------------------
FROM gcr.io/distroless/cc-debian13
LABEL maintainer="JoanMorera"

# Copy user
COPY --from=builder /etc/passwd /etc/passwd
COPY --from=builder /etc/group /etc/group
# Copy locales locally to runtime
COPY --from=builder /usr/lib/locale /usr/lib/locale

# Copy Binary
COPY --from=builder --chown=qbt:qbt /usr/local/bin/qbittorrent-nox /usr/bin/qbittorrent-nox

# Env
ENV HOME="/home/qbt" \
    XDG_CONFIG_HOME="/home/qbt" \
    XDG_DATA_HOME="/home/qbt" \
    LC_ALL=C.UTF-8 \
    LANG=C.UTF-8

# Runtime Config
USER qbt
WORKDIR /home/qbt

EXPOSE 8080 6881 6881/udp

ENTRYPOINT ["/usr/bin/qbittorrent-nox"]
