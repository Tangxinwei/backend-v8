#!/bin/bash

VERSION=$1
ENABLE_FP=$2
FULL_SYMBOLE=$3

[ -z "$GITHUB_WORKSPACE" ] && GITHUB_WORKSPACE="$( cd "$( dirname "$0" )"/.. && pwd )"

if [ "$VERSION" == "10.6.194" ] || [ "$VERSION" == "11.8.172" ] || [ "$VERSION" == "11.8.172.18" ] || [ "$VERSION" == "11.8.172.18-pgo" ]; then 
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
        cmake
        
    pip install virtualenv
else
    sudo apt-get install -y \
        pkg-config \
        git \
        subversion \
        curl \
        wget \
        build-essential \
        python \
        xz-utils \
        zip
fi

cd ~

if [ "$VERSION" == "11.8.172" ] || [ "$VERSION" == "11.8.172.18" ] || [ "$VERSION" == "11.8.172.18-pgo" ]; then 
    echo "============ intall clang-17"
    sudo apt update
    sudo apt install -y wget gnupg lsb-release software-properties-common
    wget -O - https://apt.llvm.org/llvm-snapshot.gpg.key | sudo apt-key add -
    sudo add-apt-repository "deb http://apt.llvm.org/$(lsb_release -cs)/ llvm-toolchain-$(lsb_release -cs)-17 main"
    sudo apt update
    sudo apt install -y clang-17 libc++-17-dev libc++abi-17-dev lld
    ln -s /usr/lib/llvm-17 ~/customclang
fi

if [ "$VERSION" == "10.6.194" ]; then 
    echo "============ intall clang-16"
    sudo apt update
    sudo apt install -y wget gnupg lsb-release software-properties-common
    wget -O - https://apt.llvm.org/llvm-snapshot.gpg.key | sudo apt-key add -
    sudo add-apt-repository "deb http://apt.llvm.org/$(lsb_release -cs)/ llvm-toolchain-$(lsb_release -cs)-16 main"
    sudo apt update
    sudo apt install -y clang-16 libc++-16-dev libc++abi-16-dev lld
    ln -s /usr/lib/llvm-16 ~/customclang
fi

echo "=====[ Getting Depot Tools ]====="	
git clone -q https://chromium.googlesource.com/chromium/tools/depot_tools.git
if [ "$VERSION" != "10.6.194" ] && [ "$VERSION" != "11.8.172" ] && [ "$VERSION" != "11.8.172.18" ] && [ "$VERSION" != "11.8.172.18-pgo" ]; then
    cd depot_tools
    git reset --hard 8d16d4a
    cd ..
fi
export DEPOT_TOOLS_UPDATE=0
if [ "$VERSION" == "10.6.194" ] || [ "$VERSION" == "11.8.172" ] || [ "$VERSION" == "11.8.172.18" ] || [ "$VERSION" == "11.8.172.18-pgo" ]; then 
    export PATH=$(pwd)/depot_tools:$PATH
else
    export PATH=$(pwd)/depot_tools:$(pwd)/depot_tools/.cipd_bin/2.7/bin:$PATH
fi
gclient


mkdir v8
cd v8

echo "=====[ Fetching V8 ]====="
fetch v8
echo "target_os = ['linux']" >> .gclient
cd ~/v8/v8
git checkout refs/tags/$VERSION
gclient sync

# echo "=====[ Patching V8 ]====="
# git apply --cached $GITHUB_WORKSPACE/patches/builtins-puerts.patches
# git checkout -- .

if [ "$VERSION" == "11.8.172" ] || [ "$VERSION" == "11.8.172.18" ] || [ "$VERSION" == "11.8.172.18-pgo" ]; then 
  node $GITHUB_WORKSPACE/node-script/do-gitpatch.js -p $GITHUB_WORKSPACE/patches/remove_uchar_include_v11.8.172.patch
  node $GITHUB_WORKSPACE/node-script/use_libcxx.js .
  export LD_LIBRARY_PATH=$HOME/customclang/lib:$LD_LIBRARY_PATH
  node -e "const fs = require('fs'); fs.writeFileSync('./build/config/compiler/BUILD.gn', fs.readFileSync('./build/config/compiler/BUILD.gn', 'utf-8').replace('use_ghash = true', 'use_ghash = true\n  use_cxx17 = true'));"
fi

echo "=====[ add ArrayBuffer_New_Without_Stl ]====="
node $GITHUB_WORKSPACE/node-script/add_arraybuffer_new_without_stl.js .

node $GITHUB_WORKSPACE/node-script/patchs.js . $VERSION

GN_ARGS="is_debug=false v8_enable_i18n_support=false v8_use_snapshot=true v8_use_external_startup_data=false v8_static_library=true libcxx_abi_unstable=false v8_enable_pointer_compression=true v8_enable_sandbox=false use_custom_libcxx=false is_clang=true clang_use_chrome_plugins=false use_sysroot=false use_glib=false clang_base_path=\"$HOME/customclang\" v8_enable_maglev=false"
if [ "$FULL_SYMBOLE" == "true" ]; then
  GN_ARGS=$GN_ARGS" strip_debug_info=false symbol_level=2"
else
  GN_ARGS=$GN_ARGS" strip_debug_info=true symbol_level=0"
fi
echo "=====[ Building V8 ]====="
echo $GN_ARGS
gn gen out.gn/x64.release --args="$GN_ARGS"


ninja -C out.gn/x64.release -t clean
ninja -v -C out.gn/x64.release wee8

mkdir -p output/v8/Lib/Linux
cp out.gn/x64.release/obj/libwee8.a output/v8/Lib/Linux/
mkdir -p output/v8/Bin/Linux
find out.gn/ -type f -name v8cc -exec cp "{}" output/v8/Bin/Linux \;
find out.gn/ -type f -name mksnapshot -exec cp "{}" output/v8/Bin/Linux \;

