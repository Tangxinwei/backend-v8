const fs = require('fs');

var lines = fs.readFileSync(process.argv[2], 'utf-8').split(/[\n\r]/);

lines[0] = 'use_cxx17=true'

console.log(`write to file ${process.argv[2]}`)
fs.writeFileSync(process.argv[2], lines.join('\n'));
