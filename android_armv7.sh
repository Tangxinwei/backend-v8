#!/bin/bash

VERSION=$1
ENABLE_FP=$2
FULL_SYMBOLE=$3
USE_POINTERCOMPRESS=$4
USE_MMAP=$5
ENABLE_MAGLEV=$6

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
        zip
pip install virtualenv


sudo apt-get update
sudo apt-get install -y libatomic1-i386-cross
sudo rm -rf /var/lib/apt/lists/*
#export LD_LIBRARY_PATH=”LD_LIBRARY_PATH:/usr/i686-linux-gnu/lib/”
echo "/usr/i686-linux-gnu/lib" > i686.conf
sudo mv i686.conf /etc/ld.so.conf.d/
sudo ldconfig

cd ~
echo "=====[ Getting Depot Tools ]====="	
git clone -q https://chromium.googlesource.com/chromium/tools/depot_tools.git
export PATH=$(pwd)/depot_tools:$PATH
gclient
export DEPOT_TOOLS_UPDATE=0


mkdir v8
cd v8

echo "=====[ Fetching V8 ]====="
fetch v8
echo "target_os = ['android']" >> .gclient
cd ~/v8/v8
./build/install-build-deps-android.sh
git checkout refs/tags/$VERSION

echo "=====[ fix DEPS ]===="
node -e "const fs = require('fs'); fs.writeFileSync('./DEPS', fs.readFileSync('./DEPS', 'utf-8').replace(\"Var('chromium_url') + '/external/github.com/kennethreitz/requests.git'\", \"'https://github.com/kennethreitz/requests'\"));"

gclient sync


node -e "const fs = require('fs'); fs.writeFileSync('./build/config/compiler/BUILD.gn', fs.readFileSync('./build/config/compiler/BUILD.gn', 'utf-8').replace('fortify_level = \"2\"', 'fortify_level = \"0\"'));"

echo "=====[ add ArrayBuffer_New_Without_Stl ]====="
node $GITHUB_WORKSPACE/node-script/add_arraybuffer_new_without_stl.js .

node $GITHUB_WORKSPACE/node-script/patchs.js . $VERSION

if [ "$ENABLE_FP" == "true" ]; then
  node -e "const fs = require('fs'); fs.writeFileSync('./build/config/compiler/compiler.gni', fs.readFileSync('./build/config/compiler/compiler.gni', 'utf-8').replace('can_unwind_with_frame_pointers = enable_frame_pointers', 'enable_frame_pointers = true\n can_unwind_with_frame_pointers = enable_frame_pointers'));"
fi

git add -A
git -c user.name="s" -c user.email="s@s.com" commit -m 'test'

if [ "$USE_MMAP" == "true" ]; then
  node $GITHUB_WORKSPACE/node-script/do-gitpatch-commit.js -p $GITHUB_WORKSPACE/patches/use_mmap_12.patch
fi

GN_ARGS="target_os=\"android\" target_cpu=\"arm\" is_debug=false v8_enable_i18n_support=false v8_target_cpu=\"arm\" use_goma=false v8_use_snapshot=true v8_use_external_startup_data=false v8_static_library=true use_custom_libcxx=false use_custom_libcxx_for_host=true v8_enable_sandbox=false"

if [ "$FULL_SYMBOLE" == "true" ]; then
  GN_ARGS=$GN_ARGS" strip_debug_info=false symbol_level=2"
else
  GN_ARGS=$GN_ARGS" strip_debug_info=true symbol_level=0"
fi

if [ "$USE_POINTERCOMPRESS" == "true" ]; then
  GN_ARGS=$GN_ARGS" v8_enable_pointer_compression=false"
else
  GN_ARGS=$GN_ARGS" v8_enable_pointer_compression=false"
fi

if [ "$ENABLE_MAGLEV" == "true" ]; then
  GN_ARGS=$GN_ARGS" v8_enable_maglev=true"
else
  GN_ARGS=$GN_ARGS" v8_enable_maglev=false"
fi

echo "=====[ Building V8 ]====="
echo $GN_ARGS
gn gen out.gn/arm.release --args="$GN_ARGS"

ninja -C out.gn/arm.release -t clean
ninja -v -C out.gn/arm.release wee8

mkdir -p output/v8/Lib/Android/armeabi-v7a
cp out.gn/arm.release/obj/libwee8.a output/v8/Lib/Android/armeabi-v7a/
mkdir -p output/v8/Bin/Android/armeabi-v7a
find out.gn/ -type f -name v8cc -exec cp "{}" output/v8/Bin/Android/armeabi-v7a \;
find out.gn/ -type f -name mksnapshot -exec cp "{}" output/v8/Bin/Android/armeabi-v7a \;
