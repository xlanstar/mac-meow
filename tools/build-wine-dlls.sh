#!/bin/bash
# 從 CrossOver 26.3.0 原始碼重建 patches/bin/x86_64-windows/ 的修補版 Wine DLL（wsock32、advapi32）。
# 只建置需要的 PE 模組（不建整個 Wine）。產物會覆寫 patches/bin/x86_64-windows/*.dll。
#
# 需求：Xcode（/usr/bin/clang，x86_64 host 編譯經 Rosetta）、Homebrew：llvm lld bison
#   brew install llvm lld bison
# 用法：bash tools/build-wine-dlls.sh
# 完成後更新 patches/bin/SHA256SUMS 與 patches/SOURCES.md（見 docs/development.md）。
set -euo pipefail
# shellcheck source=lib.sh
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"

B="$ROOT/build"
CX_VER=26.3.0
CX_TAR="$B/archives/crossover-sources-$CX_VER.tar.gz"
CX_URL="https://media.codeweavers.com/pub/crossover/source/crossover-sources-$CX_VER.tar.gz"
CX_SHA256=ac99c8ca4b3848f3e81784135f023df266b61c2345726ea55a50b3e030dd6872
SRC="$B/src/sources/wine"
OBJ="$B/wine64"
DST="$ROOT/patches/bin/x86_64-windows"
MODULES=(wsock32 advapi32)   # 新增修補時在此加入模組

llvm_paths || exit 1
[[ -x "$BISON_BIN/bison" ]] || die "缺少 bison（brew install bison）"
export PATH="$BISON_BIN:$LLD_BIN:/usr/bin:/bin:/usr/sbin:/sbin:$LLVM_BIN"

# 1. 原始碼（約 150 MB）
mkdir -p "$B/archives" "$B/src"
[[ -f "$CX_TAR" ]] || curl -fL -o "$CX_TAR" "$CX_URL"
echo "$CX_SHA256  $CX_TAR" | /usr/bin/shasum -a 256 -c - || die "原始碼校驗失敗"
[[ -d "$SRC" ]] || tar -xzf "$CX_TAR" -C "$B/src"

# 2. 套用本專案的修補（可重複執行）
for p in "$ROOT"/patches/*.patch; do
  if patch -d "$SRC" -p1 -R --dry-run -s -f <"$p" >/dev/null 2>&1; then
    echo "已套用：$(basename "$p")"
  else
    patch -d "$SRC" -p1 -s <"$p"; echo "套用：$(basename "$p")"
  fi
done

# 3. 最小設定：x86_64 host（Rosetta）+ Homebrew LLVM 交叉編譯 PE
mkdir -p "$OBJ"
if [[ ! -f "$OBJ/Makefile" ]]; then
  ( cd "$OBJ" && arch -x86_64 env CC="/usr/bin/clang -arch x86_64" x86_64_CC="$LLVM_BIN/clang" \
    "$SRC/configure" --enable-archs=x86_64 --disable-tests \
    --without-x --without-freetype --without-gnutls --without-vulkan --without-gstreamer --without-sdl \
    --without-cups --without-sane --without-krb5 --without-netapi --without-pcap --without-usb --without-v4l2 \
    --without-pulse --without-alsa --without-oss --without-capi --without-dbus --without-gphoto --without-opencl \
    --without-pcsclite --without-wayland --without-ffmpeg --without-inotify --without-udev --without-unwind \
    --without-osmesa --without-opengl --without-fontconfig --without-coreaudio )
fi

# 4. 建置並去除除錯資訊
mkdir -p "$DST"
for m in "${MODULES[@]}"; do
  ( cd "$OBJ" && arch -x86_64 make -j"$(sysctl -n hw.ncpu)" "dlls/$m/x86_64-windows/$m.dll" )
  "$LLVM_BIN/llvm-strip" --strip-debug -o "$DST/$m.dll" "$OBJ/dlls/$m/x86_64-windows/$m.dll"
  echo "完成：patches/bin/x86_64-windows/$m.dll"
done
echo "SHA-256（與 patches/bin/SHA256SUMS 比對；有變更時更新該檔與 patches/SOURCES.md）："
( cd "$DST" && /usr/bin/shasum -a 256 *.dll )
