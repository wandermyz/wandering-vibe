import { mkdir, mkdtemp, writeFile } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import type { BuildMeta } from '../src/catalog.js';
import { buildDir, iconFile } from '../src/catalog.js';
import { parseConfig, type Config } from '../src/config.js';

export async function tempConfig(overrides: Record<string, unknown> = {}): Promise<Config> {
  const dir = await mkdtemp(path.join(os.tmpdir(), 'ios-dist-test-'));
  return parseConfig({ port: 0, ...overrides }, path.join(dir, 'config.json'));
}

export function meta(partial: Partial<BuildMeta> = {}): BuildMeta {
  return {
    bundleId: 'com.example.notes',
    name: 'Notes',
    version: '1.0',
    build: '20261008.120000',
    size: 2048,
    sha256: 'a'.repeat(64),
    publishedAt: '2026-10-08T12:00:00.000Z',
    profile: { name: 'Notes AdHoc', method: 'ad-hoc', expiresAt: '2027-10-01T00:00:00Z', deviceCount: 2 },
    ...partial,
  };
}

/** Writes a fake published build (meta.json + an IPA of `ipaBytes`). */
export async function addBuild(config: Config, m: BuildMeta, ipaBytes = 'PK-fake-ipa-content'): Promise<void> {
  const dir = buildDir(config.dataDir, m.bundleId, m.build);
  await mkdir(dir, { recursive: true });
  await writeFile(path.join(dir, 'app.ipa'), ipaBytes);
  await writeFile(path.join(dir, 'meta.json'), JSON.stringify(m));
}

export async function addIcon(config: Config, bundleId: string): Promise<void> {
  await writeFile(iconFile(config.dataDir, bundleId), 'png');
}
