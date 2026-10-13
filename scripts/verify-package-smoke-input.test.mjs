import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import { test } from 'node:test';
import { verifyRun, verifyArtifact } from './verify-package-smoke-input.mjs';

const expected = { run: '123', repository: 'AgentConnect/awiki-me', app: 'a'.repeat(40), core: 'b'.repeat(40), target: 'macos-arm64' };
const run = { id: 123, repository: { full_name: expected.repository }, path: '.github/workflows/package-app.yml', event: 'workflow_dispatch', status: 'completed', conclusion: 'success' };
const bytes = Buffer.from('exact package bytes');
const artifact = { filename: 'AWiki-Me.dmg', sizeBytes: bytes.length, sha256: crypto.createHash('sha256').update(bytes).digest('hex') };
const manifest = { sourceRefs: { app: expected.app, imCore: expected.core }, artifacts: { 'macos-arm64': artifact } };

test('accepts an explicitly pinned passed package run and exact bytes', () => {
  verifyRun(run, expected);
  assert.equal(verifyArtifact(manifest, expected, () => bytes).sha256, artifact.sha256);
});

test('rejects a different run, repository, workflow, event or incomplete result', () => {
  for (const change of [{ id: 124 }, { repository: { full_name: 'other/repo' } }, { path: '.github/workflows/ci.yml' }, { event: 'pull_request' }, { status: 'in_progress' }, { conclusion: 'failure' }]) {
    assert.throws(() => verifyRun({ ...run, ...change }, expected));
  }
  for (const change of [{ run: '../123' }, { app: 'main' }, { core: 'b'.repeat(7) }]) {
    assert.throws(() => verifyRun(run, { ...expected, ...change }));
  }
});

test('rejects source or target mismatch before reading a package', () => {
  for (const change of [{ app: 'c'.repeat(40) }, { core: 'c'.repeat(40) }, { target: 'missing' }]) {
    assert.throws(() => verifyArtifact(manifest, { ...expected, ...change }, () => assert.fail('Must not read')));
  }
});

test('rejects paths, corrupt metadata and altered bytes', () => {
  for (const change of [{ filename: '../evil.dmg' }, { filename: 'dir/evil.dmg' }, { filename: 'dir\\evil.dmg' }, { sizeBytes: -1 }, { sha256: 'invalid' }, { sizeBytes: bytes.length + 1 }, { sha256: '0'.repeat(64) }]) {
    const candidate = { ...manifest, artifacts: { 'macos-arm64': { ...artifact, ...change } } };
    assert.throws(() => verifyArtifact(candidate, expected, () => bytes));
  }
});
