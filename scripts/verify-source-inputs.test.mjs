import assert from 'node:assert/strict';
import { test } from 'node:test';
import { validateManifest, verifyCoreCheckout } from './verify-source-inputs.mjs';

const refs = { anp: 'agent-network-protocol/anp', 'anp-identity': 'agent-network-protocol/anp-identity', 'awiki-im-core': 'AgentConnect/awiki-cli-rs2' };
const manifest = () => ({ schema_version: 1, dependencies: Object.fromEntries(Object.entries(refs).map(([name, repo]) => [name, { repository: `https://github.com/${repo}.git`, commit: 'a'.repeat(40), pull_request: `https://github.com/${repo}/pull/1` }])) });

test('accepts the complete reviewed graph and distinct consumer/SDK commits', () => {
  const app = manifest();
  const core = manifest();
  core.dependencies['awiki-im-core'].commit = 'b'.repeat(40);
  verifyCoreCheckout(app, core, 'a'.repeat(40));
});

test('rejects missing or extra SDKs, moving refs, wrong repositories and stale cross-repo PRs', () => {
  for (const mutate of [
    m => delete m.dependencies.anp,
    m => { m.dependencies.other = {}; },
    m => { m.dependencies.anp.commit = 'release/0929'; },
    m => { m.dependencies.anp.repository = 'https://other.example/anp.git'; },
    m => { m.dependencies['anp-identity'].pull_request = 'https://github.com/AgentConnect/awiki-cli-rs2/pull/56'; },
  ]) {
    const input = manifest(); mutate(input);
    assert.throws(() => validateManifest(input));
  }
});

test('rejects an older consumer or mismatching nested SDK pins', () => {
  assert.throws(() => verifyCoreCheckout(manifest(), manifest(), 'b'.repeat(40)));
  for (const name of ['anp', 'anp-identity']) {
    const core = manifest(); core.dependencies[name].commit = 'b'.repeat(40);
    assert.throws(() => verifyCoreCheckout(manifest(), core, 'a'.repeat(40)));
  }
});
