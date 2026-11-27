const fs = require('node:fs');
const path = require('node:path');

// npm on Windows puts its shim beside node_modules. Homebrew and npm on Unix
// link the executable to the JavaScript entry point inside firebase-tools.
const searchPaths = [__dirname];
for (const directory of (process.env.PATH || '').split(path.delimiter).filter(Boolean)) {
  const executable = path.join(directory, process.platform === 'win32' ? 'firebase.cmd' : 'firebase');
  if (fs.existsSync(executable)) {
    searchPaths.push(directory, path.dirname(fs.realpathSync(executable)));
  }
}
module.exports = path.dirname(require.resolve('firebase-tools/lib/auth.js', { paths: searchPaths }));
