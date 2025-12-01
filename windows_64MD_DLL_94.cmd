set VERSION=%1
set ENABLE_FP=%2
set FULL_SYMBOLE=%3
set USE_POINTERCOMPRESS=%4
set USE_MMAP=%5
set ENABLE_MAGLEV=%6

cd /d %USERPROFILE%
echo =====[ Getting Depot Tools ]=====
powershell -command "Invoke-WebRequest https://storage.googleapis.com/chrome-infra/depot_tools.zip -O depot_tools.zip"
7z x depot_tools.zip -o*
set PATH=%CD%\depot_tools;%PATH%
set GYP_MSVS_VERSION=2019
set DEPOT_TOOLS_WIN_TOOLCHAIN=0
call gclient

set DEPOT_TOOLS_UPDATE=0

mkdir v8
cd v8

echo =====[ Fetching V8 ]=====
call fetch v8
cd v8
call git checkout refs/tags/%VERSION%
call gclient sync

echo =====[ Make dynamic_crt ]=====
node %GITHUB_WORKSPACE%\node-script\rep.js  build\config\win\BUILD.gn


echo =====[ add ArrayBuffer_New_Without_Stl ]=====
node %GITHUB_WORKSPACE%\node-script\add_arraybuffer_new_without_stl.js .

node %GITHUB_WORKSPACE%\node-script\patchs.js . %VERSION%

if "%ENABLE_FP%"=="true" (
    node -e "const fs = require('fs'); fs.writeFileSync('./build/config/compiler/compiler.gni', fs.readFileSync('./build/config/compiler/compiler.gni', 'utf-8').replace('can_unwind_with_frame_pointers = enable_frame_pointers', 'enable_frame_pointers = true\n can_unwind_with_frame_pointers = enable_frame_pointers'));"
)

git add -A
call git -c user.name="s" -c user.email="s@s.com" commit -m 'test'

set GN_ARGS=target_os=""win"" target_cpu=""x64"" v8_use_external_startup_data=false v8_enable_i18n_support=false is_debug=false is_clang=true is_component_build=true v8_enable_sandbox=false use_custom_libcxx=true

if "%FULL_SYMBOLE%"=="true" (
    set GN_ARGS=%GN_ARGS% strip_debug_info=false symbol_level=2
) else if "%FULL_SYMBOLE%"=="false" (
    set GN_ARGS=%GN_ARGS% strip_debug_info=true symbol_level=0
)

if "%USE_POINTERCOMPRESS%"=="true" (
    set GN_ARGS=%GN_ARGS% v8_enable_pointer_compression=true
) else if "%USE_POINTERCOMPRESS%"=="false" (
    set GN_ARGS=%GN_ARGS% v8_enable_pointer_compression=false
)

if "%ENABLE_MAGLEV%"=="true" (
    set GN_ARGS=%GN_ARGS% v8_enable_maglev=true
) else if "%ENABLE_MAGLEV%"=="false" (
    set GN_ARGS=%GN_ARGS% v8_enable_maglev=false
)

echo =====[ Building V8 ]=====
echo %GN_ARGS%
call gn gen out.gn\x64.release -args="%GN_ARGS%"


call ninja -C out.gn\x64.release -t clean
call ninja -v -C out.gn\x64.release v8

md output\v8\Lib\Win64DLL
copy /Y out.gn\x64.release\v8.dll.lib output\v8\Lib\Win64DLL\
copy /Y out.gn\x64.release\v8_libplatform.dll.lib output\v8\Lib\Win64DLL\
copy /Y out.gn\x64.release\v8.dll output\v8\Lib\Win64DLL\
copy /Y out.gn\x64.release\v8_libbase.dll output\v8\Lib\Win64DLL\
copy /Y out.gn\x64.release\v8_libplatform.dll output\v8\Lib\Win64DLL\
copy /Y out.gn\x64.release\v8.dll.pdb output\v8\Lib\Win64DLL\
copy /Y out.gn\x64.release\v8_libbase.dll.pdb output\v8\Lib\Win64DLL\
copy /Y out.gn\x64.release\v8_libplatform.dll.pdb output\v8\Lib\Win64DLL\

copy /Y out.gn\x64.release\third_party_zlib.dll output\v8\Lib\Win64DLL\
copy /Y out.gn\x64.release\third_party_zlib.dll.pdb output\v8\Lib\Win64DLL\
