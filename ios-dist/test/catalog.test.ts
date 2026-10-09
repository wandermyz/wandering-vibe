import { existsSync } from 'node:fs';
import { mkdir, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { describe, expect, it } from 'vitest';
import { appDir, buildDir, isValidBuild, isValidBundleId, loadApp, loadCatalog, pruneBuilds } from '../src/catalog.js';
import { addBuild, addIcon, meta, tempConfig } from './helpers.js';

describe('validation', () => {
  it.each(['com.example.app', 'com.wander-myz.od-notes', 'single'])('accepts bundle id %s', (id) => {
    expect(isValidBundleId(id)).toBe(true);
  });
  it.each(['..', 'com..x', '../etc', 'a/b', '', 'com.x.', '%2e%2e'])('rejects bundle id %j', (id) => {
    expect(isValidBundleId(id)).toBe(false);
  });
  it('accepts 1-3 integer components only', () => {
    expect(isValidBuild('1')).toBe(true);
    expect(isValidBuild('20261008.120000')).toBe(true);
    expect(isValidBuild('1.2.3.4')).toBe(false);
    expect(isValidBuild('1.0-beta')).toBe(false);
    expect(isValidBuild('20261008.120000.partial')).toBe(false);
  });
  it('refuses to build paths from invalid ids', () => {
    expect(() => appDir('/d', '../x')).toThrow();
    expect(() => buildDir('/d', 'com.x', '../1')).toThrow();
  });
});

describe('loadCatalog', () => {
  it('returns an empty list for a fresh data dir', async () => {
    const config = await tempConfig();
    expect(await loadCatalog(config.dataDir)).toEqual([]);
  });

  it('groups builds by app, newest build first, apps sorted by name', async () => {
    const config = await tempConfig();
    await addBuild(config, meta({ build: '20261001.100000', version: '1.0' }));
    await addBuild(config, meta({ build: '20261008.100000', version: '1.1' }));
    await addBuild(config, meta({ bundleId: 'com.example.alpha', name: 'Alpha', build: '3' }));
    await addIcon(config, 'com.example.alpha');

    const apps = await loadCatalog(config.dataDir);
    expect(apps.map((a) => a.name)).toEqual(['Alpha', 'Notes']);
    expect(apps[0]?.hasIcon).toBe(true);
    expect(apps[1]?.hasIcon).toBe(false);
    expect(apps[1]?.latest.version).toBe('1.1');
    expect(apps[1]?.builds.map((b) => b.build)).toEqual(['20261008.100000', '20261001.100000']);
  });

  it('ignores staging dirs, corrupt meta and builds without an IPA', async () => {
    const config = await tempConfig();
    await addBuild(config, meta({ build: '1' }));
    const builds = path.join(appDir(config.dataDir, 'com.example.notes'), 'builds');
    await mkdir(path.join(builds, '2.partial'));
    await mkdir(path.join(builds, '3'));
    await writeFile(path.join(builds, '3', 'meta.json'), '{not json');
    await mkdir(path.join(builds, '4'));
    await writeFile(path.join(builds, '4', 'meta.json'), JSON.stringify(meta({ build: '4' })));
    // build number in meta must match its directory
    await mkdir(path.join(builds, '5'));
    await writeFile(path.join(builds, '5', 'meta.json'), JSON.stringify(meta({ build: '6' })));
    await writeFile(path.join(builds, '5', 'app.ipa'), 'x');

    const app = await loadApp(config.dataDir, 'com.example.notes');
    expect(app?.builds.map((b) => b.build)).toEqual(['1']);
  });

  it('returns undefined for unknown or invalid apps', async () => {
    const config = await tempConfig();
    expect(await loadApp(config.dataDir, 'com.example.none')).toBeUndefined();
    expect(await loadApp(config.dataDir, '../../etc')).toBeUndefined();
  });
});

describe('pruneBuilds', () => {
  it('keeps the newest N builds', async () => {
    const config = await tempConfig();
    for (const b of ['1', '2', '3', '10']) await addBuild(config, meta({ build: b }));
    expect(await pruneBuilds(config.dataDir, 'com.example.notes', 2)).toEqual(['2', '1']);
    expect(existsSync(buildDir(config.dataDir, 'com.example.notes', '10'))).toBe(true);
    expect(existsSync(buildDir(config.dataDir, 'com.example.notes', '1'))).toBe(false);
  });
});
