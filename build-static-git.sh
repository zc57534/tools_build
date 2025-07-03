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
if [ "$TARGET" = "i686-linux-android" ]; then
    ARCH="x86"
fi

# 设置环境变量
export NDK_HOME=${NDK_HOME:-$HOME/android-ndk}
export TOOLCHAIN=${TOOLCHAIN:-$NDK_HOME/toolchains/llvm/prebuilt/linux-x86_64}
export CC="$TOOLCHAIN/bin/${TARGET}${API}-clang"
export CXX="$TOOLCHAIN/bin/${TARGET}${API}-clang++"
export AR="$TOOLCHAIN/bin/llvm-ar"
export RANLIB="$TOOLCHAIN/bin/llvm-ranlib"
export STRIP="$TOOLCHAIN/bin/llvm-strip"
export LD="$TOOLCHAIN/bin/ld"
export AS="$TOOLCHAIN/bin/llvm-as"
export NM="$TOOLCHAIN/bin/llvm-nm"

# 工作目录
BUILD_DIR=$(pwd)/build-$TARGET
INSTALL_DIR=$BUILD_DIR/install
mkdir -p $BUILD_DIR $INSTALL_DIR
cd $BUILD_DIR

# 下载源码
download_source() {
    local url=$1
    local file=$(basename $url)
    local dir=${file%.tar.*}
    
    if [ ! -f "$file" ]; then
        echo "下载: $url"
        curl -L -o $file $url
    fi
    
    if [ ! -d "$dir" ]; then
        echo "解压: $file"
        tar xf $file
    fi
    
    echo $dir
}

# 1. 编译 zlib
echo "编译 zlib..."
ZLIB_VER=1.3
ZLIB_DIR=$(download_source https://zlib.net/zlib-$ZLIB_VER.tar.gz)
cd $ZLIB_DIR
./configure --prefix=$INSTALL_DIR --static
make -j$(nproc)
make install
cd ..

# 2. 编译 OpenSSL
echo "编译 OpenSSL..."
OPENSSL_VER=3.0.10
OPENSSL_DIR=$(download_source https://www.openssl.org/source/openssl-$OPENSSL_VER.tar.gz)
cd $OPENSSL_DIR
./Configure android-$ARCH no-shared -D__ANDROID_API__=$API \
    --prefix=$INSTALL_DIR \
    -static
make -j$(nproc)
make install_sw
cd ..

# 3. 编译 libcurl (可选，用于 HTTPS 支持)
echo "编译 libcurl..."
CURL_VER=8.4.0
CURL_DIR=$(download_source https://curl.se/download/curl-$CURL_VER.tar.gz)
cd $CURL_DIR
./configure \
    --host=$TARGET \
    --prefix=$INSTALL_DIR \
    --with-openssl=$INSTALL_DIR \
    --disable-shared \
    --enable-static \
    --without-zstd \
    --disable-ftp \
    --disable-ldap \
    --disable-ldaps \
    --disable-rtsp \
    --disable-proxy \
    --disable-dict \
    --disable-telnet \
    --disable-tftp \
    --disable-pop3 \
    --disable-imap \
    --disable-smb \
    --disable-smtp \
    --disable-gopher \
    --disable-manual \
    --disable-ipv6 \
    --disable-sspi \
    --disable-crypto-auth \
    --disable-ntlm-wb \
    --disable-tls-srp \
    --disable-unix-sockets \
    --without-librtmp \
    --without-libidn2 \
    --without-libpsl \
    --without-nghttp2 \
    --without-nghttp3 \
    --without-ngtcp2 \
    --without-brotli \
    --without-zlib \
    --without-libssh2 \
    --without-libgsasl \
    PKG_CONFIG_PATH=$INSTALL_DIR/lib/pkgconfig \
    CC="$CC" CXX="$CXX" AR="$AR" RANLIB="$RANLIB" STRIP="$STRIP"

make -j$(nproc)
make install
cd ..

# 4. 编译 Git
echo "编译 Git..."
GIT_VER=2.42.0
GIT_DIR=$(download_source https://mirrors.edge.kernel.org/pub/software/scm/git/git-$GIT_VER.tar.gz)
cd $GIT_DIR

# 配置环境
export CFLAGS="-static -I$INSTALL_DIR/include -Os -fPIE"
export LDFLAGS="-static -L$INSTALL_DIR/lib -fPIE -pie"
export LIBS="-lz -lssl -lcrypto"

# 配置 Git
make configure
./configure \
    --host=$TARGET \
    --prefix=/data/local/tmp \
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

echo "构建完成! 输出文件: $OUT_DIR/git"
