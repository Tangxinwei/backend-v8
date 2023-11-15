const fs = require('fs');

var lines = fs.readFileSync(process.argv[2], 'utf-8').split(/[\n\r]/);

for(var i = 0; i < lines.length; i++) {
    //lines[i] = lines[i].replace("-fstack-protector", "-fno-stack-protector");
    lines[i] = lines[i].replace(`fortify_level = "2"`, `fortify_level = "0"`);
}

console.log(`write to file ${process.argv[2]}`)
console.log(lines.join('\n'))
fs.writeFileSync(process.argv[2], lines.join('\n'));
