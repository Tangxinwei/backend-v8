#!/bin/bash

VERSION=$1
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
        zip
        
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
echo "=====[ Getting Depot Tools ]====="	
git clone -q https://chromium.googlesource.com/chromium/tools/depot_tools.git
if [ "$VERSION" != "10.6.194" ] && [ "$VERSION" != "11.8.172" ] && [ "$VERSION" != "11.8.172.18" ] && [ "$VERSION" != "11.8.172.18-pgo" ]; then 
    cd depot_tools
    git reset --hard 8d16d4a
    cd ..
fi
export DEPOT_TOOLS_UPDATE=0
export PATH=$(pwd)/depot_tools:$PATH
gclient


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

if [ "$VERSION" == "11.8.172" ] || [ "$VERSION" == "11.8.172.18" ] || [ "$VERSION" == "11.8.172.18-pgo" ]; then 
    cd third_party/android_toolchain
    wget https://dl.google.com/android/repository/android-ndk-r23-linux.zip
    unzip android-ndk-r23-linux.zip -d .
    node -e "const fs = require('fs'); fs.writeFileSync('./build/config/android/config.gni', fs.readFileSync('./build/config/android/config.gni', 'utf-8').replace('//third_party/android_toolchain/ndk', '//third_party/android_toolchain/android-ndk-r23'));"
    node -e "const fs = require('fs'); fs.writeFileSync('./build/config/android/config.gni', fs.readFileSync('./build/config/android/config.gni', 'utf-8').replace('r25c', 'r23'));"
    node -e "const fs = require('fs'); fs.writeFileSync('./build/config/android/config.gni', fs.readFileSync('./build/config/android/config.gni', 'utf-8').replace('default_android_ndk_major_version = 25', 'default_android_ndk_major_version = 23'));"
    node -e "const fs = require('fs'); fs.writeFileSync('./build/config/compiler/BUILD.gn', fs.readFileSync('./build/config/compiler/BUILD.gn', 'utf-8').replace('use_ghash = true', 'use_ghash = true\n  use_cxx17 = true'));"
    cd ~/v8/v8
fi

# echo "=====[ Patching V8 ]====="
# git apply --cached $GITHUB_WORKSPACE/patches/builtins-puerts.patches
# git checkout -- .

if [ "$VERSION" == "11.8.172" ] || [ "$VERSION" == "11.8.172.18" ] || [ "$VERSION" == "11.8.172.18-pgo" ]; then
  node $GITHUB_WORKSPACE/node-script/do-gitpatch.js -p $GITHUB_WORKSPACE/patches/remove_uchar_include_v11.8.172.patch
  node -e "const fs = require('fs'); fs.writeFileSync('./build/config/compiler/BUILD.gn', fs.readFileSync('./build/config/compiler/BUILD.gn', 'utf-8').replace('fortify_level = \"2\"', 'fortify_level = \"0\"'));"
fi

echo "=====[ add ArrayBuffer_New_Without_Stl ]====="
node $GITHUB_WORKSPACE/node-script/add_arraybuffer_new_without_stl.js .

node $GITHUB_WORKSPACE/node-script/patchs.js . $VERSION

echo "=====[ Building V8 ]=====" 
gn gen out.gn/arm64.release --args="target_os=\"android\" target_cpu=\"arm64\" is_debug=false v8_enable_i18n_support=false v8_target_cpu=\"arm64\" use_goma=false v8_use_snapshot=true v8_use_external_startup_data=false v8_static_library=true strip_debug_info=true symbol_level=0 use_custom_libcxx=false use_custom_libcxx_for_host=true v8_enable_pointer_compression=true v8_enable_sandbox=false v8_enable_maglev=false"

ninja -C out.gn/arm64.release -t clean
ninja -v -C out.gn/arm64.release wee8
if [ "$VERSION" == "9.4.146.24" ]; then 
  third_party/android_ndk/toolchains/aarch64-linux-android-4.9/prebuilt/linux-x86_64/aarch64-linux-android/bin/strip -g -S -d --strip-debug --verbose out.gn/arm64.release/obj/libwee8.a
fi

mkdir -p output/v8/Lib/Android/arm64-v8a
cp out.gn/arm64.release/obj/libwee8.a output/v8/Lib/Android/arm64-v8a/
mkdir -p output/v8/Bin/Android/arm64-v8a
find out.gn/ -type f -name v8cc -exec cp "{}" output/v8/Bin/Android/arm64-v8a \;
find out.gn/ -type f -name mksnapshot -exec cp "{}" output/v8/Bin/Android/arm64-v8a \;
