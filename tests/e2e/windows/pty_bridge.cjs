'use strict';

// Transport only. The existing CLI owns SAS display, user confirmation and auth.
// No transcript is persisted here; the owning Dart scenario scrubs its buffers.
const pty = require('node-pty');

if (process.platform !== 'win32') {
  process.stderr.write('The Windows E2E terminal requires native Windows.\n');
  process.exit(2);
}
if (process.argv[2] === '--check') {
  process.stdout.write(JSON.stringify({ available: true, platform: 'windows' }) + '\n');
  process.exit(0);
}
const [executable, ...arguments_] = process.argv.slice(2);
if (!executable || executable !== executable.trim()) {
  process.stderr.write('A structured Windows executable and argv are required.\n');
  process.exit(2);
}

let terminal;
try {
  terminal = pty.spawn(executable, arguments_, {
    name: 'xterm-256color',
    cols: 160,
    rows: 40,
    cwd: process.cwd(),
    env: process.env,
    useConpty: true,
  });
} catch {
  // Do not echo argv or an exception that could contain protected fixture data.
  process.stderr.write('The Windows E2E terminal could not start its CLI.\n');
  process.exit(2);
}
process.stdin.setEncoding('utf8');
process.stdin.on('data', data => terminal.write(data.replace(/\r?\n/g, '\r')));
terminal.onData(data => process.stdout.write(data));
terminal.onExit(({ exitCode }) => {
  process.stdin.pause();
  process.exitCode = exitCode;
  // Drain the ConPTY output before completing the transport process.
  process.stdout.write('', () => process.exit(exitCode));
});
for (const signal of ['SIGINT', 'SIGTERM']) {
  process.on(signal, () => terminal.kill());
}
