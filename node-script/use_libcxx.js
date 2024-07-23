const fs = require('fs');
const path = require('path')

//toolchain/gcc_toolchain.gni
{
  var file_path = path.join(process.argv[2], "build", "toolchain", 'gcc_toolchain.gni')
  var file_content = fs.readFileSync(file_path, 'utf-8')
  var find_str = '$ld {{ldflags}}${extra_ldflags}'
  var index = file_content.indexOf(find_str)
  if(index <= 0){
    process.exit(-1)
  }else{
    console.log("change //toolchain/gcc_toolchain.gni")
    var before_str = file_content.slice(0, index)
    var after_str = file_content.slice(index + find_str.length)
    fs.writeFileSync(file_path, before_str + find_str + ' -stdlib=libc++ ' + after_str)
  }
}
//config/compiler/build.gn
{
  var file_path = path.join(process.argv[2], "build", "config", 'compiler', 'BUILD.gn')
  var file_content = fs.readFileSync(file_path, 'utf-8')
  var find_str = 'cflags_cc = []'
  var index = file_content.indexOf(find_str)
  if(index <= 0){
    process.exit(-1)
  }else{
    console.log('change //config/compiler/build.gn')
    var before_str = file_content.slice(0, index)
    var after_str = file_content.slice(index + find_str.length)
    fs.writeFileSync(file_path, before_str + find_str + '\n  cflags_cc += [ "-stdlib=libc++", "-D_LIBCPP_AVAILABILITY_HAS_NO_VERBOSE_ABORT=1" ]\n ' + after_str)
  }
}

