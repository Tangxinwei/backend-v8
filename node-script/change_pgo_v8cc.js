const fs = require('fs');
const path = require('path')

const v8_path = path.resolve(process.argv[2]);
const v8_version = process.argv[3];
const target_cpu = (process.argv[4] == 'arm' ? 'arm' : 'arm64');

const filepath = path.join(v8_path, 'BUILD.gn')
console.log(`change ${target_cpu} v8cc to ${filepath} ...`);
let context = fs.readFileSync(filepath, 'utf-8');
    
const run_mksnapshot_start = context.indexOf('template("run_mksnapshot") {')
const run_mksnapshot_end = context.indexOf('run_mksnapshot("default") {')

let new_context = context.slice(0, run_mksnapshot_start) + context.slice(run_mksnapshot_start, run_mksnapshot_end).replace("$current_cpu", target_cpu) + context.slice(run_mksnapshot_end)

fs.writeFileSync(filepath, new_context);


