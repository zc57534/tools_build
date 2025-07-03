#!/bin/bash
set -euo pipefail

# 参数检查
if [ $# -ne 2 ]; then
    echo "用法: $0 <目标架构> <API级别>"
    echo "示例: $0 aarch64-linux-android 24"
    exit 1
fi

TARGET=$1
API=$2
ARCH=${TARGET%-linux-android*}

# 使用您提供的版本
export OPENSSL_VERSION=1.1.1w
export LIBEXPAT_VERSION=2.7.0
export ZLIB_VERSION=1.3.1
export CARES_VERSION=1.34.4
export LIBSSH2_VERSION=1.11.1
export CURL_VERSION=8.4.0
export GIT_VERSION=2.42.0

# 设置环境变量
export NDK_HOME=${NDK_HOME:-$HOME/android-ndk}
export TOOLCHAIN=${TOOLCHAIN:-$NDK_HOME/toolchains/llvm/prebuilt/linux-x86_64}
export CC="$TOOLCHAIN/bin/${TARGET}${API}-clang"
export CXX="$TOOLCHAIN/bin/${TARGET}${API}-clang++"
export AR="$TOOLCHAIN/bin/llvm-ar"
export RANLIB="$TOOLCHAIN/bin/llvm-ranlib"
export STRIP="$TOOLCHAIN/bin/llvm-strip"
export PATH="$TOOLCHAIN/bin:$PATH"

# 工作目录
BUILD_DIR=$(pwd)/build-$TARGET
INSTALL_DIR=$BUILD_DIR/install
mkdir -p $BUILD_DIR $INSTALL_DIR
cd $BUILD_DIR

# 增强版下载函数
download_source() {
    local name=$1
    local url=$2
    local file=$(basename $url)
    
    echo "下载 $name: $url"
    
    # 最多尝试3次下载
    for i in {1..3}; do
        if curl -L -f -o "$file" "$url"; then
            echo "下载成功: $file"
            return 0
        else
            echo "下载失败 (尝试 $i/3), 等待 3 秒后重试..."
            sleep 3
        fi
    done
    
    echo "错误: 无法下载 $name"
    exit 1
}

# 1. 编译 zlib
echo "=== 编译 zlib $ZLIB_VERSION ==="
download_source "zlib" "https://github.com/madler/zlib/releases/download/v$ZLIB_VERSION/zlib-$ZLIB_VERSION.tar.gz"
tar xzf zlib-$ZLIB_VERSION.tar.gz
cd zlib-$ZLIB_VERSION
./configure --prefix=$INSTALL_DIR --static
make -j$(nproc)
make install
cd ..

# 2. 编译 OpenSSL
echo "=== 编译 OpenSSL $OPENSSL_VERSION ==="
download_source "OpenSSL" "https://www.openssl.org/source/openssl-$OPENSSL_VERSION.tar.gz"
tar xzf openssl-$OPENSSL_VERSION.tar.gz
cd openssl-$OPENSSL_VERSION
./Configure android-$ARCH no-shared -D__ANDROID_API__=$API \
    --prefix=$INSTALL_DIR \
    -static
make -j$(nproc)
make install_sw
cd ..

# 3. 编译 Expat
echo "=== 编译 Expat $LIBEXPAT_VERSION ==="
download_source "Expat" "https://github.com/libexpat/libexpat/releases/download/R_${LIBEXPAT_VERSION//./_}/expat-$LIBEXPAT_VERSION.tar.bz2"
tar xjf expat-$LIBEXPAT_VERSION.tar.bz2
cd expat-$LIBEXPAT_VERSION
./configure \
    --host=$TARGET \
    --prefix=$INSTALL_DIR \
    --enable-static \
    --disable-shared \
    --without-docbook \
    --without-examples \
    --without-tests
make -j$(nproc)
make install
cd ..

# 4. 编译 c-ares
echo "=== 编译 c-ares $CARES_VERSION ==="
download_source "c-ares" "https://github.com/c-ares/c-ares/releases/download/v$CARES_VERSION/c-ares-$CARES_VERSION.tar.gz"
tar xzf c-ares-$CARES_VERSION.tar.gz
cd c-ares-$CARES_VERSION
./configure \
    --host=$TARGET \
    --prefix=$INSTALL_DIR \
    --enable-static \
    --disable-shared \
    --disable-tests
make -j$(nproc)
make install
cd ..

# 5. 编译 libssh2
echo "=== 编译 libssh2 $LIBSSH2_VERSION ==="
download_source "libssh2" "https://libssh2.org/download/libssh2-$LIBSSH2_VERSION.tar.bz2"
tar xjf libssh2-$LIBSSH2_VERSION.tar.bz2
cd libssh2-$LIBSSH2_VERSION
./configure \
    --host=$TARGET \
    --prefix=$INSTALL_DIR \
    --enable-static \
    --disable-shared \
    --with-crypto=openssl \
    --with-libssl-prefix=$INSTALL_DIR \
    --disable-examples-build
make -j$(nproc)
make install
cd ..

# 6. 编译 libcurl
echo "=== 编译 libcurl $CURL_VERSION ==="
download_source "libcurl" "https://curl.se/download/curl-$CURL_VERSION.tar.gz"
tar xzf curl-$CURL_VERSION.tar.gz
cd curl-$CURL_VERSION
./configure \
    --host=$TARGET \
    --prefix=$INSTALL_DIR \
    --with-openssl=$INSTALL_DIR \
    --with-expat=$INSTALL_DIR \
    --with-libssh2=$INSTALL_DIR \
    --enable-ares=$INSTALL_DIR \
    --disable-shared \
    --enable-static \
    --enable-http \
    --enable-https \
    --enable-ftp \
    --enable-file \
    --disable-ldap \
    --disable-rtsp \
    --disable-proxy \
    --disable-dict \
    --disable-telnet \
    --disable-tftp \
    --disable-pop3 \
    --disable-imap \
    --disable-smtp \
    --disable-gopher \
    --disable-manual \
    --disable-ipv6 \
    --disable-sspi \
    --disable-crypto-auth \
    --disable-ntlm-wb \
    --disable-tls-srp \
    --disable-unix-sockets \
    --without-zstd \
    --without-librtmp \
    --without-libidn2 \
    --without-libpsl \
    --without-nghttp2 \
    --without-nghttp3 \
    --without-ngtcp2 \
    --without-brotli \
    --without-zlib \
    --without-libgsasl \
    PKG_CONFIG_PATH=$INSTALL_DIR/lib/pkgconfig \
    CC="$CC" CXX="$CXX" AR="$AR" RANLIB="$RANLIB" STRIP="$STRIP"

make -j$(nproc)
make install
cd ..

# 7. 编译 Git
echo "=== 编译 Git $GIT_VERSION ==="
download_source "Git" "https://mirrors.edge.kernel.org/pub/software/scm/git/git-$GIT_VERSION.tar.gz"
tar xzf git-$GIT_VERSION.tar.gz
cd git-$GIT_VERSION

# 配置环境
export CFLAGS="-static -I$INSTALL_DIR/include -Os -fPIE"
export LDFLAGS="-static -L$INSTALL_DIR/lib -fPIE -pie"
export LIBS="-lz -lssl -lcrypto -lcurl -lssh2 -lcares -lexpat"

# 配置 Git
make configure
./configure \
    --host=$TARGET \
    --prefix=/data/local/tmp \
    --with-openssl=$INSTALL_DIR \
    --with-curl=$INSTALL_DIR \
    --with-expat=$INSTALL_DIR \
    --without-tcltk \
    --without-python \
    --without-iconv \
    --without-gettext \
    --without-perl \
    NO_GETTEXT=YesPlease \
    NO_REGEX=YesPlease \
    NO_SYS_POLL_H=YesPlease \
    NO_UNIX_SOCKETS=YesPlease

# 编译并精简
make -j$(nproc) NO_INSTALL_HARDLINKS=Yes
$STRIP git

# 验证二进制文件
file git | grep "statically linked"
echo "编译成功! 二进制大小: $(du -h git | cut -f1)"

# 创建输出目录
OUT_DIR=$(pwd)/../../git-$TARGET
mkdir -p $OUT_DIR
cp git $OUT_DIR/

# 创建压缩包
tar czf $OUT_DIR/git-$TARGET-static.tar.gz -C $OUT_DIR git

echo "=== 构建完成! ==="
echo "输出文件: $OUT_DIR/git"
echo "压缩包: $OUT_DIR/git-$TARGET-static.tar.gz"
