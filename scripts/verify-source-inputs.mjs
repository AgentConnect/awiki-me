import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { pathToFileURL } from 'node:url';

const repositories = {
  anp: 'agent-network-protocol/anp',
  'anp-identity': 'agent-network-protocol/anp-identity',
  'awiki-im-core': 'AgentConnect/awiki-cli-rs2',
};

export function validateManifest(manifest) {
  assert.equal(manifest.schema_version, 1);
  assert.deepEqual(Object.keys(manifest.dependencies ?? {}).sort(), Object.keys(repositories).sort());
  for (const [name, repository] of Object.entries(repositories)) {
    const entry = manifest.dependencies[name];
    assert.deepEqual(Object.keys(entry).sort(), ['commit', 'pull_request', 'repository']);
    assert.equal(entry.repository, `https://github.com/${repository}.git`);
    assert.match(entry.commit, /^[0-9a-f]{40}$/);
    const prefix = `https://github.com/${repository}/pull/`;
    assert.ok(entry.pull_request.startsWith(prefix), `${name}: PR repository mismatch`);
    assert.match(entry.pull_request.slice(prefix.length), /^[1-9][0-9]*$/);
  }
  return manifest.dependencies;
}

export function verifyCoreCheckout(appManifest, coreManifest, actualHead) {
  const app = validateManifest(appManifest);
  const core = validateManifest(coreManifest);
  assert.equal(actualHead, app['awiki-im-core'].commit, 'Core consumer checkout mismatch');
  // Core's own SDK pin can precede its consumer manifest commit. ANP and
  // Identity must be the same reviewed sources on both sides of that boundary.
  for (const name of ['anp', 'anp-identity']) {
    assert.deepEqual(core[name], app[name], `${name}: App/Core source mismatch`);
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href) {
  const [appRoot = '.', coreRoot] = process.argv.slice(2);
  const read = root => JSON.parse(fs.readFileSync(path.join(root, 'dependencies.source.json'), 'utf8'));
  const app = read(appRoot);
  const sources = validateManifest(app);
  if (coreRoot !== undefined) {
    verifyCoreCheckout(app, read(coreRoot), execFileSync('git', ['-C', coreRoot, 'rev-parse', 'HEAD'], { encoding: 'utf8' }).trim());
  }
  console.log(`commit=${sources['awiki-im-core'].commit}`);
}
