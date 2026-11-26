#!/bin/bash
# Builds vino-wine: CodeWeavers' CrossOver Wine (MSync and their game fixes) for macOS,
# as one self-contained folder that Vino downloads. Runs on an Intel Mac (or under Rosetta) with Homebrew.
set -euo pipefail

CX_VERSION=${CX_VERSION:-26.1.0}
CX_SHA256=${CX_SHA256:-e4ec87d5821a009dd1f1d2e36ffe2e24b8fcbae9516375ea42f95a16928ab8fa}
ROOT=$(cd "$(dirname "$0")" && pwd)
WORK=$ROOT/work
OUT=$ROOT/out
DEPS=$WORK/deps/lib
STAGE=$OUT/vino-wine
BREW=$(brew --prefix)
JOBS=$(sysctl -n hw.ncpu)

[ "$(uname -m)" = x86_64 ] || { echo "Build on an Intel Mac or under Rosetta: Wine for macOS is x86_64 code." >&2; exit 1; }
mkdir -p "$WORK" "$OUT" "$DEPS"

echo "== CrossOver $CX_VERSION source"
SRC=$WORK/crossover-sources-$CX_VERSION.tar.gz
[ -f "$SRC" ] || curl -fL -o "$SRC" "https://media.codeweavers.com/pub/crossover/source/crossover-sources-$CX_VERSION.tar.gz"
echo "$CX_SHA256  $SRC" | shasum -a 256 -c
[ -d "$WORK/sources/wine" ] || tar xzf "$SRC" -C "$WORK"

echo "== Libraries Wine loads, renamed to @rpath so they're found inside the package on any Mac"
# Wine records each library's install name at configure time and loads it by that name later,
# so these must carry @rpath names before configure runs.
copy_lib() {
    local ref=$1 name src
    name=$(basename "$ref")
    [ -f "$DEPS/$name" ] && return
    src=$(realpath "$ref")
    cp "$src" "$DEPS/$name"
    echo "$src" >> "$WORK/deps/sources.txt"  # licenses.sh finds each library's license from this
    chmod u+w "$DEPS/$name"
    install_name_tool -id "@rpath/$name" "$DEPS/$name"
    install_name_tool -add_rpath @loader_path "$DEPS/$name" 2>/dev/null || true
    # `|| true`: a library with no Homebrew dependencies is fine, not a failed pipeline
    otool -L "$DEPS/$name" | tail -n +2 | awk '{print $1}' | { grep -E "^($BREW/|@rpath/)" || true; } | while read -r dep; do
        local base found
        base=$(basename "$dep")
        [ "$base" = "$name" ] && continue
        if [[ $dep == @rpath/* ]]; then  # already relative: just bring the library along
            found=$(dirname "$src")/$base
            [ -f "$found" ] || found=$BREW/lib/$base
            copy_lib "$found"
        else
            copy_lib "$dep"
            install_name_tool -change "$dep" "@rpath/$base" "$DEPS/$name"
        fi
    done
}
rm -rf "$DEPS" && mkdir -p "$DEPS" && : > "$WORK/deps/sources.txt"
for lib in freetype/lib/libfreetype.6.dylib gnutls/lib/libgnutls.30.dylib sdl2/lib/libSDL2-2.0.0.dylib molten-vk/lib/libMoltenVK.dylib; do
    copy_lib "$BREW/opt/$lib"
done
ln -sf libfreetype.6.dylib "$DEPS/libfreetype.dylib"
ln -sf libgnutls.30.dylib "$DEPS/libgnutls.dylib"
ln -sf libSDL2-2.0.0.dylib "$DEPS/libSDL2.dylib"
ls "$DEPS"

echo "== Configure"
export PATH="$BREW/opt/bison/bin:$BREW/opt/flex/bin:$PATH"
export MACOSX_DEPLOYMENT_TARGET=${MACOSX_DEPLOYMENT_TARGET:-13.0}
export CPPFLAGS="-I$BREW/include"
# the second rpath lets Wine's own build tools (like sfnt2fon, which needs FreeType) run during the build;
# it's removed again before packaging
export LDFLAGS="-L$DEPS -Wl,-rpath,@loader_path/../../ -Wl,-rpath,$DEPS -Wl,-headerpad_max_install_names"
export FREETYPE_CFLAGS="$(pkg-config --cflags freetype2)" FREETYPE_LIBS="-L$DEPS -lfreetype"
export GNUTLS_CFLAGS="$(pkg-config --cflags gnutls)" GNUTLS_LIBS="-L$DEPS -lgnutls"
export SDL2_CFLAGS="$(pkg-config --cflags sdl2)" SDL2_LIBS="-L$DEPS -lSDL2"
mkdir -p "$WORK/build"
cd "$WORK/build"
[ -f Makefile ] || "$WORK/sources/wine/configure" --prefix=/ \
    --enable-archs=i386,x86_64 --with-mingw --without-x --with-vulkan --with-sdl --with-freetype --with-gnutls \
    --without-gstreamer --without-cups --without-krb5 --without-sane --without-gphoto --without-pcap \
    --without-pcsclite --without-netapi --without-capi --without-oss --without-pulse --without-alsa \
    --without-dbus --without-udev --without-usb --without-v4l2 --without-wayland --without-fontconfig \
    --disable-tests

# every library Wine will load must be an @rpath one, or it would look in Homebrew on the user's Mac
grep -E '#define SONAME_' include/config.h
if grep -E '#define SONAME_' include/config.h | grep -q "$BREW"; then
    echo "A library would be loaded from Homebrew's folder; see the list above." >&2
    exit 1
fi

echo "== Build"
make -j"$JOBS"

echo "== Package"
rm -rf "$STAGE"
make install-lib DESTDIR="$STAGE"
cp -a "$DEPS"/*.dylib "$STAGE/lib/"
mkdir -p "$STAGE/share/licenses"
cp "$WORK/sources/wine/COPYING.LIB" "$STAGE/share/licenses/wine-COPYING.LIB"
cp "$WORK/sources/wine/LICENSE" "$STAGE/share/licenses/wine-LICENSE"
cat > "$STAGE/share/licenses/SOURCE.txt" <<EOF
vino-wine is CodeWeavers' CrossOver Wine $CX_VERSION, built unmodified by https://github.com/bhurtyalkritan/vino-wine.
Wine is licensed under the LGPL 2.1 (wine-COPYING.LIB). The exact source used is
https://media.codeweavers.com/pub/crossover/source/crossover-sources-$CX_VERSION.tar.gz
(sha256 $CX_SHA256), also attached to each vino-wine release.
The bundled libraries and their licenses are listed in LIBRARIES.txt.

vino-wine is not affiliated with or endorsed by CodeWeavers. CrossOver and CodeWeavers are trademarks of CodeWeavers, Inc.
EOF
"$ROOT/licenses.sh" "$WORK/deps/sources.txt" "$STAGE/share/licenses" "$OUT/sources"
cat "$STAGE/share/licenses/LIBRARIES.txt"
# drop the build-machine rpath from everything we ship
find "$STAGE" -type f \( -name '*.so' -o -name '*.dylib' -o -perm -u+x \) -exec sh -c \
    'file "$1" | grep -q Mach-O && install_name_tool -delete_rpath "$2" "$1" 2>/dev/null; true' _ {} "$DEPS" \;
if find "$STAGE" -type f -exec sh -c 'file "$1" | grep -q Mach-O && otool -l "$1" | grep -q "path $2 "' _ {} "$DEPS" \; -print | grep -q .; then
    echo "A shipped file still points at the build folder" >&2; exit 1
fi
# install_name_tool invalidates signatures; ad-hoc sign every Mach-O file again
find "$STAGE" -type f \( -name '*.so' -o -name '*.dylib' -o -perm -u+x \) -exec sh -c 'file "$1" | grep -q Mach-O && codesign --force -s - "$1"' _ {} \;

echo "== Self-test"
"$STAGE/bin/wine" --version
export WINEPREFIX=$WORK/test-prefix WINEDEBUG=err+all,err+font
rm -rf "$WINEPREFIX"
"$STAGE/bin/wine" wineboot -i 2>&1 | tail -5
out=$("$STAGE/bin/wine" cmd /c echo vino-wine-ok 2>&1)
echo "$out" | tail -5
echo "$out" | grep -q vino-wine-ok
if "$STAGE/bin/wine" cmd /c echo 2>&1 | grep -i 'cannot find the freetype'; then echo "FreeType didn't load" >&2; exit 1; fi
WINEMSYNC=1 "$STAGE/bin/wine" cmd /c echo msync-ok 2>&1 | grep -q msync-ok
"$STAGE/bin/wineserver" -k || true

echo "== Archive"
tar -C "$OUT" -cJf "$OUT/vino-wine-$CX_VERSION.tar.xz" vino-wine
(cd "$OUT" && shasum -a 256 "vino-wine-$CX_VERSION.tar.xz" > "vino-wine-$CX_VERSION.tar.xz.sha256" && cat "vino-wine-$CX_VERSION.tar.xz.sha256")
