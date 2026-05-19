#!/bin/bash

VERSION=$1
ENABLE_FP=$2
FULL_SYMBOLE=$3
USE_POINTERCOMPRESS=$4
USE_MMAP=$5
ENABLE_MAGLEV=$6
V8_ENABLE_PROFILING=$7
V8_PROFILING_LOG_FILE=$8
USE_ZONE_MEMORY_TRIM=$9
echo "===== param"
echo $V8_ENABLE_PROFILING
echo $V8_PROFILING_LOG_FILE

[ -z "$GITHUB_WORKSPACE" ] && GITHUB_WORKSPACE="$( cd "$( dirname "$0" )"/.. && pwd )"

sudo apt-get install -y \
        pkg-config \
        git \
        subversion \
        curl \
        wget \
        build-essential \
        python3 \
        ninja-build \
        xz-utils \
        zip \
        unzip

pip install virtualenv

# ===== Setup OHOS NDK =====
# Resolution order:
#   1) $OHOS_NDK_HOME directly points to an OHOS native NDK directory (must contain llvm/ and sysroot/).
#   2) $OHOS_SDK_HOME points to an extracted command-line-tools dir whose layout contains
#      command-line-tools/sdk/default/openharmony/native/.
#   3) $OHOS_SDK_ZIP points to a commandline-tools-linux-x64-*.zip file (will be auto-extracted).
#   4) Auto-discover an already-extracted SDK under common paths.
#   5) Auto-discover a zip under common paths and extract it.

is_valid_ndk() {
  [ -n "$1" ] && [ -d "$1/llvm" ] && [ -d "$1/sysroot" ]
}

extract_zip_to_install_dir() {
  local zip="$1"
  local install_dir="$2"
  echo "=====[ Extracting OHOS SDK from $zip to $install_dir ]====="
  mkdir -p "$install_dir"
  unzip -q -o "$zip" -d "$install_dir"
}

OHOS_SDK_INSTALL_DIR="${OHOS_SDK_INSTALL_DIR:-$HOME/ohos-sdk}"
OHOS_SDK_NATIVE_REL="command-line-tools/sdk/default/openharmony/native"

# (1) OHOS_NDK_HOME already valid → use as is.
if is_valid_ndk "$OHOS_NDK_HOME"; then
  :
# (2) OHOS_SDK_HOME points to an extracted SDK root.
elif [ -n "$OHOS_SDK_HOME" ] && is_valid_ndk "$OHOS_SDK_HOME/$OHOS_SDK_NATIVE_REL"; then
  export OHOS_NDK_HOME="$OHOS_SDK_HOME/$OHOS_SDK_NATIVE_REL"
elif [ -n "$OHOS_SDK_HOME" ] && is_valid_ndk "$OHOS_SDK_HOME/native"; then
  export OHOS_NDK_HOME="$OHOS_SDK_HOME/native"
# (3) OHOS_SDK_ZIP given → extract.
elif [ -n "$OHOS_SDK_ZIP" ] && [ -f "$OHOS_SDK_ZIP" ]; then
  extract_zip_to_install_dir "$OHOS_SDK_ZIP" "$OHOS_SDK_INSTALL_DIR"
  export OHOS_NDK_HOME="$OHOS_SDK_INSTALL_DIR/$OHOS_SDK_NATIVE_REL"
else
  # (4) Auto-discover an already-extracted SDK
  for candidate in \
    "$OHOS_SDK_INSTALL_DIR/$OHOS_SDK_NATIVE_REL" \
    "/opt/ohos-sdk/$OHOS_SDK_NATIVE_REL" \
    "/opt/ohos-sdk/native" \
    "/opt/openharmony/native" \
    "$HOME/ohos-sdk/$OHOS_SDK_NATIVE_REL" \
    "$GITHUB_WORKSPACE/sdk/$OHOS_SDK_NATIVE_REL"; do
    if is_valid_ndk "$candidate"; then
      export OHOS_NDK_HOME="$candidate"
      break
    fi
  done

  # (5) Auto-discover a zip and extract it.
  if ! is_valid_ndk "$OHOS_NDK_HOME"; then
    for zip_candidate in \
      "$GITHUB_WORKSPACE"/sdk/commandline-tools-linux-x64-*.zip \
      "$GITHUB_WORKSPACE"/commandline-tools-linux-x64-*.zip \
      "$HOME"/commandline-tools-linux-x64-*.zip \
      /tmp/commandline-tools-linux-x64-*.zip; do
      if [ -f "$zip_candidate" ]; then
        extract_zip_to_install_dir "$zip_candidate" "$OHOS_SDK_INSTALL_DIR"
        export OHOS_NDK_HOME="$OHOS_SDK_INSTALL_DIR/$OHOS_SDK_NATIVE_REL"
        break
      fi
    done
  fi
fi

if ! is_valid_ndk "$OHOS_NDK_HOME"; then
  echo "ERROR: OHOS NDK not found. Tried in order:"
  echo "  1) \$OHOS_NDK_HOME (current: '$OHOS_NDK_HOME')"
  echo "  2) \$OHOS_SDK_HOME (current: '$OHOS_SDK_HOME')"
  echo "  3) \$OHOS_SDK_ZIP  (current: '$OHOS_SDK_ZIP')"
  echo "  4) Common install paths (/opt/ohos-sdk, \$HOME/ohos-sdk, \$GITHUB_WORKSPACE/sdk, ...)"
  echo "  5) Auto-extract a 'commandline-tools-linux-x64-*.zip' under \$GITHUB_WORKSPACE[/sdk], \$HOME, /tmp"
  echo "Either set OHOS_NDK_HOME directly, or place the OpenHarmony commandline-tools zip somewhere reachable."
  exit 1
fi
echo "=====[ Using OHOS_NDK_HOME=$OHOS_NDK_HOME ]====="


cd ~
echo "=====[ Getting Depot Tools ]====="	
git clone -q https://chromium.googlesource.com/chromium/tools/depot_tools.git || true

export PATH=$(pwd)/depot_tools:$PATH
export DEPOT_TOOLS_UPDATE=0
gclient
~/depot_tools/ensure_bootstrap


mkdir v8
cd v8

echo "=====[ Fetching V8 ]====="
fetch v8
echo "target_os = ['android']" >> .gclient
cd ~/v8/v8

# Hard reset all modifications in V8 and its critical subrepos before sync
git reset --hard HEAD 2>/dev/null
git clean -fdx 2>/dev/null
if [ -d build ]; then
  cd build
  git reset --hard HEAD 2>/dev/null
  git clean -fdx 2>/dev/null
  rm -rf config/ohos toolchain/ohos
  cd ..
fi
if [ -d third_party/zlib ]; then
  cd third_party/zlib
  git reset --hard HEAD 2>/dev/null
  git clean -fdx 2>/dev/null
  cd ../..
fi

git checkout refs/tags/$VERSION

gclient sync -D


echo "=====[ add ArrayBuffer_New_Without_Stl ]====="
node $GITHUB_WORKSPACE/node-script/add_arraybuffer_new_without_stl.js .

node $GITHUB_WORKSPACE/node-script/patchs.js . $VERSION

if [ "$ENABLE_FP" == "true" ]; then
  node -e "const fs = require('fs'); fs.writeFileSync('./build/config/compiler/compiler.gni', fs.readFileSync('./build/config/compiler/compiler.gni', 'utf-8').replace('can_unwind_with_frame_pointers = enable_frame_pointers', 'enable_frame_pointers = true\n can_unwind_with_frame_pointers = enable_frame_pointers'));"
fi

echo "=====[ patch for ohos ]====="
node $GITHUB_WORKSPACE/node-script/do-gitpatch.js -p $GITHUB_WORKSPACE/patches/ohos_v8_v$VERSION.patch
cd build
node $GITHUB_WORKSPACE/node-script/do-gitpatch.js -p $GITHUB_WORKSPACE/patches/ohos_build_v$VERSION.patch
cd ../third_party/zlib
node $GITHUB_WORKSPACE/node-script/do-gitpatch.js -p $GITHUB_WORKSPACE/patches/ohos_zlib_v$VERSION.patch
cd ../..

git add -A
git -c user.name="s" -c user.email="s@s.com" commit -m 'test'

if [ "$USE_MMAP" == "true" ]; then
  node $GITHUB_WORKSPACE/node-script/do-gitpatch-commit.js -p $GITHUB_WORKSPACE/patches/use_mmap_12.patch
fi

if [ "$USE_ZONE_MEMORY_TRIM" == "true" ]; then
  node $GITHUB_WORKSPACE/node-script/do-gitpatch-commit.js -p $GITHUB_WORKSPACE/patches/v8-zone-resize-memory.patch
fi

GN_ARGS="target_os=\"ohos\" target_cpu=\"arm64\" is_debug=false v8_enable_i18n_support=false v8_target_cpu=\"arm64\" use_goma=false v8_use_snapshot=true v8_use_external_startup_data=false v8_static_library=true v8_enable_sandbox=false use_custom_libcxx=false use_custom_libcxx_for_host=true use_musl=true"

if [ "$FULL_SYMBOLE" == "true" ]; then
  GN_ARGS=$GN_ARGS" strip_debug_info=false symbol_level=2"
else
  GN_ARGS=$GN_ARGS" strip_debug_info=true symbol_level=0"
fi

if [ "$USE_POINTERCOMPRESS" == "true" ]; then
  GN_ARGS=$GN_ARGS" v8_enable_pointer_compression=true"
else
  GN_ARGS=$GN_ARGS" v8_enable_pointer_compression=false"
fi

if [ "$ENABLE_MAGLEV" == "true" ]; then
  GN_ARGS=$GN_ARGS" v8_enable_maglev=true"
else
  GN_ARGS=$GN_ARGS" v8_enable_maglev=false"
fi

if [ "$V8_ENABLE_PROFILING" == "true" ]; then
  GN_ARGS=$GN_ARGS" v8_enable_builtins_profiling=true"
fi

if [ "$V8_PROFILING_LOG_FILE" == "0" ]; then
  echo "no profiling_log_file"
else
  GN_ARGS=$GN_ARGS" v8_builtins_profiling_log_file=\""$GITHUB_WORKSPACE"/"$V8_PROFILING_LOG_FILE"/ohos_result/merged.profile\""
fi

echo "=====[ Building V8 ]====="
echo $GN_ARGS
gn gen out.gn/arm64.release --args="$GN_ARGS"

ninja -C out.gn/arm64.release -t clean
ninja -v -C out.gn/arm64.release wee8

mkdir -p output/v8/Lib/OHOS/arm64-v8a
cp out.gn/arm64.release/obj/libwee8.a output/v8/Lib/OHOS/arm64-v8a/
mkdir -p output/v8/Bin/OHOS/arm64-v8a
find out.gn/ -type f -name v8cc -exec cp "{}" output/v8/Bin/OHOS/arm64-v8a \;
find out.gn/ -type f -name mksnapshot -exec cp "{}" output/v8/Bin/OHOS/arm64-v8a \;
