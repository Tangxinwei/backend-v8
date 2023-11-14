const fs = require('fs');

var lines = fs.readFileSync(process.argv[2], 'utf-8').split(/[\n\r]/);

for(var i = 0; i < lines.length; i++) {
    if(lines[i].indexOf("stack-protector")>=0){
        lines[i] = ""
    }
}
        
fs.writeFileSync(process.argv[2], lines.join('\n'));
