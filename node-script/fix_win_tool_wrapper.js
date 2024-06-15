const fs = require('fs');

var lines = fs.readFileSync(process.argv[2], 'utf-8').split(/[\n\r]/);
var out = []
for(var i = 0; i < lines.length; i++) {
    out.push(lines[i])
    if(lines[i] == '    for line in link.stdout:')
    {
        out.push('      line = line.decode('utf-8')')
    }else if(lines[i] == '    for line in out.splitlines():'){
        out.push('      line = line.decode('utf-8')')
    }
    lines[i] = lines[i].replace("lib = map(os.path.relpath, lib)", "lib = list(map(os.path.relpath, lib))")
}
        
fs.writeFileSync(process.argv[2], out.join('\n'));
