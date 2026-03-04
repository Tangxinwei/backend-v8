VERSION=$1
ENABLE_FP=$2
FULL_SYMBOLE=$3
USE_POINTERCOMPRESS=$4
USE_MMAP=$5
ENABLE_MAGLEV=$6
V8_ENABLE_PROFILING=$7
V8_PROFILING_LOG_FILE=$8
echo "===== param"
echo $V8_ENABLE_PROFILING
echo $V8_PROFILING_LOG_FILE

[ -z "$GITHUB_WORKSPACE" ] && GITHUB_WORKSPACE="$( cd "$( dirname "$0" )"/.. && pwd )"

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
echo "target_os = ['ios']" >> .gclient
cd ~/v8/v8
git checkout refs/tags/$VERSION
gclient sync

# echo "=====[ Patching V8 ]====="
# git apply --cached $GITHUB_WORKSPACE/patches/builtins-puerts.patches
# git checkout -- .

node $GITHUB_WORKSPACE/node-script/do-gitpatch.js -p $GITHUB_WORKSPACE/patches/enable_wee8_v11.8.172.patch
 

echo "=====[ add ArrayBuffer_New_Without_Stl ]====="
node $GITHUB_WORKSPACE/node-script/add_arraybuffer_new_without_stl.js .

node $GITHUB_WORKSPACE/node-script/patchs.js . $VERSION

echo "use ios 15.0"
node -e "const fs = require('fs'); fs.writeFileSync('./build/config/ios/ios_sdk_overrides.gni', fs.readFileSync('./build/config/ios/ios_sdk_overrides.gni', 'utf-8').replace('ios_deployment_target = \"16.0\"', 'ios_deployment_target = \"15.0\"'));"
node -e "const fs = require('fs'); fs.writeFileSync('./build/toolchain/ios/BUILD.gn', fs.readFileSync('./build/toolchain/ios/BUILD.gn', 'utf-8').replace('ios_deployment_target = \"16.0\"', 'ios_deployment_target = \"15.0\"'));"

if [ "$ENABLE_FP" == "true" ]; then
  node -e "const fs = require('fs'); fs.writeFileSync('./build/config/compiler/compiler.gni', fs.readFileSync('./build/config/compiler/compiler.gni', 'utf-8').replace('can_unwind_with_frame_pointers = enable_frame_pointers', 'enable_frame_pointers = true\n can_unwind_with_frame_pointers = enable_frame_pointers'));"
fi

git add -A
git -c user.name="s" -c user.email="s@s.com" commit -m 'test'

if [ "$USE_MMAP" == "true" ]; then
  node $GITHUB_WORKSPACE/node-script/do-gitpatch-commit.js -p $GITHUB_WORKSPACE/patches/use_mmap_12.patch
fi

GN_ARGS="v8_use_external_startup_data=false v8_use_snapshot=true v8_enable_i18n_support=false is_debug=false v8_static_library=true ios_enable_code_signing=false target_os=\"ios\" target_cpu=\"arm64\" libcxx_abi_unstable=false v8_enable_sandbox=false use_custom_libcxx=false v8_enable_webassembly=false"

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
  GN_ARGS=$GN_ARGS" v8_builtins_profiling_log_file=\""$GITHUB_WORKSPACE"/"$V8_PROFILING_LOG_FILE"/android_result/merged.profile\""
fi

echo "=====[ Building V8 ]====="
echo GN_ARGS
gn gen out.gn/arm64.release --args="$GN_ARGS"

ninja -C out.gn/arm64.release -t clean
mkdir -p output/v8/Lib/iOS/arm64

ninja -v -C out.gn/arm64.release wee8
cp out.gn/arm64.release/obj/libwee8.a output/v8/Lib/iOS/arm64/

mkdir -p output/v8/Bin/iOS/arm64
find out.gn/ -type f -name v8cc -exec cp "{}" output/v8/Bin/iOS/arm64 \;
find out.gn/ -type f -name mksnapshot -exec cp "{}" output/v8/Bin/iOS/arm64 \;