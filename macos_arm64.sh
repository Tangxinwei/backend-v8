VERSION=$1
ENABLE_FP=$2
FULL_SYMBOLE=$3
USE_POINTERCOMPRESS=$4
USE_MMAP=$5
ENABLE_MAGLEV=$6

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
echo "target_os = ['mac-arm64']" >> .gclient
cd ~/v8/v8
git checkout refs/tags/$VERSION
gclient sync


echo "=====[ add ArrayBuffer_New_Without_Stl ]====="
node $GITHUB_WORKSPACE/node-script/add_arraybuffer_new_without_stl.js .

node $GITHUB_WORKSPACE/node-script/patchs.js . $VERSION

if [ "$ENABLE_FP" == "true" ]; then
  node -e "const fs = require('fs'); fs.writeFileSync('./build/config/compiler/compiler.gni', fs.readFileSync('./build/config/compiler/compiler.gni', 'utf-8').replace('can_unwind_with_frame_pointers = enable_frame_pointers', 'enable_frame_pointers = true\n can_unwind_with_frame_pointers = enable_frame_pointers'));"
fi

git add -A
git -c user.name="s" -c user.email="s@s.com" commit -m 'test'

if [ "$USE_MMAP" == "true" ]; then
  node node-script/do-gitpatch-commit.js -p patches/use_mmap.patch
fi

GN_ARGS="is_debug=false target_cpu=\"arm64\" v8_target_cpu=\"arm64\" v8_enable_i18n_support=false v8_use_snapshot=true v8_use_external_startup_data=false v8_static_library=true libcxx_abi_unstable=false v8_enable_sandbox=false use_custom_libcxx=false"

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

echo "=====[ Building V8 ]====="
echo $GN_ARGS
gn gen out.gn/arm64.release --args="$GN_ARGS"

ninja -C out.gn/arm64.release -t clean
ninja -v -C out.gn/arm64.release wee8

mkdir -p output/v8/Lib/macOS_arm64
cp out.gn/arm64.release/obj/libwee8.a output/v8/Lib/macOS_arm64/
mkdir -p output/v8/Inc/Blob/macOS_arm64
