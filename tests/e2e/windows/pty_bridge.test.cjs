'use strict';

const { test } = require('node:test');
const assert = require('node:assert/strict');
const { spawn, spawnSync } = require('node:child_process');
const { join } = require('node:path');

test('ConPTY exposes a real terminal and preserves structured Windows argv',
  { skip: process.platform !== 'win32', timeout: 20000 }, async t => {
    const expected = ['a b', 'c"d', 'x&y', 'last\\'];
    const childScript = [
      "const readline = require('node:readline');",
      "console.log('AWIKI_PTY_PROBE:' + JSON.stringify({tty:!!process.stdin.isTTY,args:process.argv.slice(1)}));",
      "readline.createInterface({input:process.stdin}).once('line', value => {",
      "console.log('AWIKI_PTY_INPUT:' + value); process.exit(0); });",
    ].join('');
    const child = spawn(process.execPath,
      [join(__dirname, 'pty_bridge.cjs'), process.execPath, '-e', childScript, ...expected],
      { stdio: ['pipe', 'pipe', 'pipe'], windowsHide: true });
    t.after(() => {
      if (child.pid && child.exitCode === null) {
        spawnSync('taskkill.exe', ['/PID', String(child.pid), '/T', '/F'],
          { stdio: 'ignore', windowsHide: true });
      }
    });
    let output = '';
    let errors = '';
    child.stdout.setEncoding('utf8');
    child.stderr.setEncoding('utf8');
    child.stdout.on('data', data => { output += data; });
    child.stderr.on('data', data => { errors += data; });
    const exit = new Promise((resolve, reject) => {
      child.once('error', reject);
      child.once('close', resolve);
    });
    child.stdin.write('fixture-input\n');
    assert.equal(await exit, 0, errors);
    const clean = output.replace(/\x1b\[[0-?]*[ -/]*[@-~]/g, '');
    const marker = clean.match(/AWIKI_PTY_PROBE:(\{[^\r\n]*\})/);
    assert.ok(marker, 'The native child must report its terminal evidence.');
    assert.deepEqual(JSON.parse(marker[1]), { tty: true, args: expected });
    assert.match(clean, /AWIKI_PTY_INPUT:fixture-input/);
  });
