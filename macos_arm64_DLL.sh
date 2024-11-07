VERSION=$1
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
fi

echo "=====[ add ArrayBuffer_New_Without_Stl ]====="
node $GITHUB_WORKSPACE/node-script/add_arraybuffer_new_without_stl.js .

node $GITHUB_WORKSPACE/node-script/patchs.js . $VERSION

echo "=====[ Building V8 ]====="
gn gen out.gn/arm64.release --args="is_debug=false target_cpu=\"arm64\" v8_target_cpu=\"arm64\" v8_enable_i18n_support=false v8_use_snapshot=true v8_use_external_startup_data=false is_component_build=true strip_debug_info=true symbol_level=0 libcxx_abi_unstable=false v8_enable_pointer_compression=true v8_enable_sandbox=false use_custom_libcxx=false v8_enable_maglev=false"

ninja -C out.gn/arm64.release -t clean
ninja -v -C out.gn/arm64.release v8

mkdir -p output/v8/Lib/macOSdylib_arm64
cp out.gn/arm64.release/libv8.dylib output/v8/Lib/macOSdylib_arm64/
cp out.gn/arm64.release/libv8_libplatform.dylib output/v8/Lib/macOSdylib_arm64/
cp out.gn/arm64.release/libv8_libbase.dylib output/v8/Lib/macOSdylib_arm64/
cp out.gn/arm64.release/libchrome_zlib.dylib output/v8/Lib/macOSdylib_arm64/
if [ "$VERSION" == "11.8.172" ] || [ "$VERSION" == "11.8.172.18" ] || [ "$VERSION" == "11.8.172.18-pgo" ]; then
  cp out.gn/arm64.release/libthird_party_abseil-cpp_absl.dylib output/v8/Lib/macOSdylib_arm64/
fi