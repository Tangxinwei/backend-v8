VERSION=$1
ENABLE_FP=$2
FULL_SYMBOLE=$3

[ -z "$GITHUB_WORKSPACE" ] && GITHUB_WORKSPACE="$( cd "$( dirname "$0" )"/.. && pwd )"

cd ~
echo "=====[ Getting Depot Tools ]====="	
git clone -q https://chromium.googlesource.com/chromium/tools/depot_tools.git
cd depot_tools
git reset --hard 8d16d4a
cd ..
export DEPOT_TOOLS_UPDATE=0
export PATH=$(pwd)/depot_tools:$PATH
gclient


mkdir v8
cd v8

echo "=====[ Fetching V8 ]====="
fetch v8
echo "target_os = ['mac-arm64']" >> .gclient
cd ~/v8/v8
git checkout refs/tags/$VERSION
gclient sync

# echo "=====[ Patching V8 ]====="
# git apply --cached $GITHUB_WORKSPACE/patches/builtins-puerts.patches
# git checkout -- .

if [ "$VERSION" == "11.8.172" ] || [ "$VERSION" == "11.8.172.18" ] || [ "$VERSION" == "11.8.172.18-pgo" ]; then
  node $GITHUB_WORKSPACE/node-script/do-gitpatch.js -p $GITHUB_WORKSPACE/patches/remove_uchar_include_v11.8.172.patch
  node -e "const fs = require('fs'); fs.writeFileSync('./build/config/compiler/BUILD.gn', fs.readFileSync('./build/config/compiler/BUILD.gn', 'utf-8').replace('use_ghash = true', 'use_ghash = true\n  use_cxx17 = true'));"
fi

echo "=====[ add ArrayBuffer_New_Without_Stl ]====="
node $GITHUB_WORKSPACE/node-script/add_arraybuffer_new_without_stl.js .

node $GITHUB_WORKSPACE/node-script/patchs.js . $VERSION

if [ "$ENABLE_FP" == "true" ]; then
  node -e "const fs = require('fs'); fs.writeFileSync('./build/config/compiler/compiler.gni', fs.readFileSync('./build/config/compiler/compiler.gni', 'utf-8').replace('can_unwind_with_frame_pointers = enable_frame_pointers', 'enable_frame_pointers = true\n can_unwind_with_frame_pointers = enable_frame_pointers'));"
fi

GN_ARGS="is_debug=false target_cpu=\"arm64\" v8_target_cpu=\"arm64\" v8_enable_i18n_support=false v8_use_snapshot=true v8_use_external_startup_data=false v8_static_library=true libcxx_abi_unstable=false v8_enable_pointer_compression=true v8_enable_sandbox=false use_custom_libcxx=false v8_enable_maglev=false"
if [ "$FULL_SYMBOLE" == "true" ]; then
  GN_ARGS=$GN_ARGS" strip_debug_info=false symbol_level=2"
else
  GN_ARGS=$GN_ARGS" strip_debug_info=true symbol_level=0"
fi
echo "=====[ Building V8 ]====="
echo $GN_ARGS
gn gen out.gn/arm64.release --args="$GN_ARGS"

ninja -C out.gn/arm64.release -t clean
ninja -v -C out.gn/arm64.release wee8

mkdir -p output/v8/Lib/macOS_arm64
cp out.gn/arm64.release/obj/libwee8.a output/v8/Lib/macOS_arm64/
mkdir -p output/v8/Inc/Blob/macOS_arm64
