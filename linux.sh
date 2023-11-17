VERSION=$1
[ -z "$GITHUB_WORKSPACE" ] && GITHUB_WORKSPACE="$( cd "$( dirname "$0" )"/.. && pwd )"

cd ~
echo "=====[ Getting Depot Tools ]====="	
git clone -q https://chromium.googlesource.com/chromium/tools/depot_tools.git
cd depot_tools
git reset --hard 8d16d4a
cd ..
export DEPOT_TOOLS_UPDATE=0
export PATH=$(pwd)/depot_tools:$(pwd)/depot_tools/.cipd_bin/2.7/bin:$PATH
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

case "$VERSION" in
11*)
    node $GITHUB_WORKSPACE/node-script/do-gitpatch.js -p $GITHUB_WORKSPACE/patches/export_contextual.patch
    node $GITHUB_WORKSPACE/node-script/add_usecxx17.js ./build/config/compiler/BUILD.gn
    mv $GITHUB_WORKSPACE/node-script/update.py ./tools/clang/scripts/update.py
    ;;
esac

echo "=====[ add ArrayBuffer_New_Without_Stl ]====="
node $GITHUB_WORKSPACE/node-script/add_arraybuffer_new_without_stl.js .

echo "=====[ clang version ]====="
clang --version

echo "=====[ Building V8 ]====="
python3 ./tools/dev/v8gen.py x64.release -vv -- '
is_debug = false
v8_enable_i18n_support= false
v8_use_snapshot = true
v8_use_external_startup_data = false
v8_static_library = true
strip_debug_info = true
symbol_level=0
libcxx_abi_unstable = false
v8_enable_pointer_compression=true
v8_enable_sandbox=false
use_cxx17=true
clang_version="11"
'

ninja -C out.gn/x64.release -t clean
ninja -C out.gn/x64.release wee8

mkdir -p output/v8/Lib/Linux
cp -r out.gn/x64.release/ output/v8/Lib/Linux/
mkdir -p output/v8/Inc/Blob/Linux

