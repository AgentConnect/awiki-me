import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';

export function verifyRun(run, expected) {
  for (const sha of [expected.app, expected.core]) {
    assert.match(sha ?? '', /^[a-f0-9]{40}$/, 'Expected full source SHA');
  }
  assert.match(expected.run ?? '', /^[1-9][0-9]*$/, 'Expected numeric run ID');
  assert.equal(String(run.id), expected.run, 'Run ID mismatch');
  assert.equal(run.repository?.full_name, expected.repository, 'Repository mismatch');
  assert.equal(run.path, '.github/workflows/package-app.yml', 'Wrong packaging workflow');
  assert.equal(run.event, 'workflow_dispatch', 'Expected manually requested packaging');
  assert.equal(run.status, 'completed', 'Packaging is incomplete');
  assert.equal(run.conclusion, 'success', 'Packaging did not pass');
}

export function verifyArtifact(manifest, expected, readArtifact) {
  assert.equal(manifest.sourceRefs?.app, expected.app, 'App source mismatch');
  assert.equal(manifest.sourceRefs?.imCore, expected.core, 'Core source mismatch');
  const artifact = manifest.artifacts?.[expected.target];
  assert.ok(artifact, 'Target is absent from manifest');
  assert.match(artifact.filename ?? '', /^[A-Za-z0-9][A-Za-z0-9._+-]*$/, 'Unsafe filename');
  assert.ok(Number.isSafeInteger(artifact.sizeBytes) && artifact.sizeBytes > 0, 'Invalid size');
  assert.match(artifact.sha256 ?? '', /^[a-f0-9]{64}$/, 'Invalid digest');
  const bytes = readArtifact(artifact.filename);
  assert.equal(bytes.length, artifact.sizeBytes, 'Package size mismatch');
  assert.equal(crypto.createHash('sha256').update(bytes).digest('hex'), artifact.sha256, 'Package digest mismatch');
  return { target: expected.target, sha256: artifact.sha256, sizeBytes: artifact.sizeBytes };
}

if (process.argv[1] && import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href) {
  const expected = {
    run: process.env.PACKAGE_RUN,
    repository: process.env.GITHUB_REPOSITORY,
    app: process.env.PACKAGE_APP_SHA,
    core: process.env.PACKAGE_CORE_SHA,
    target: process.env.PACKAGE_TARGET,
  };
  verifyRun(JSON.parse(fs.readFileSync('package-run.json', 'utf8')), expected);
  if (process.argv[2] !== '--run-only') {
    const root = path.resolve('package-smoke-input');
    const receipt = verifyArtifact(JSON.parse(fs.readFileSync(path.join(root, 'package-manifest.json'), 'utf8')), expected, filename => {
      const file = path.join(root, filename);
      assert.equal(fs.lstatSync(file).isSymbolicLink(), false, 'Package must not be a symlink');
      return fs.readFileSync(file);
    });
    console.log(JSON.stringify(receipt));
  }
}
