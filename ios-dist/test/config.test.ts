import os from 'node:os';
import path from 'node:path';
import { describe, expect, it } from 'vitest';
import { ConfigError, expandHome, parseConfig, resolveConfigPath } from '../src/config.js';

const CFG = '/etc/ios-dist/config.json';

describe('parseConfig', () => {
  it('applies defaults', () => {
    const c = parseConfig({}, CFG);
    expect(c).toMatchObject({
      dataDir: '/etc/ios-dist',
      host: '127.0.0.1',
      port: 8740,
      keepBuilds: 5,
      exportMethod: 'release-testing',
      allowedLogins: [],
      projects: {},
    });
    expect(c.teamId).toBeUndefined();
  });

  it('resolves project paths relative to the config and expands ~', () => {
    const c = parseConfig(
      {
        projects: {
          a: { project: 'apps/A.xcodeproj', scheme: 'A' },
          b: { workspace: '~/B.xcworkspace', scheme: 'B', configuration: 'Debug' },
        },
      },
      CFG,
    );
    expect(c.projects.a).toEqual({ project: '/etc/ios-dist/apps/A.xcodeproj', workspace: undefined, scheme: 'A', configuration: 'Release' });
    expect(c.projects.b?.workspace).toBe(path.join(os.homedir(), 'B.xcworkspace'));
  });

  it.each([
    [{ teamId: 'nope' }, /teamId/],
    [{ port: 70000 }, /port/],
    [{ allowedLogins: 'me' }, /allowedLogins/],
    [{ publicBaseUrl: 'ftp://x' }, /publicBaseUrl/],
    [{ projects: { a: { scheme: 'A' } } }, /exactly one/],
    [{ projects: { a: { project: 'x', workspace: 'y', scheme: 'A' } } }, /exactly one/],
    [{ projects: { a: { project: 'x' } } }, /scheme is required/],
    [{ ascApiKey: { keyId: 'k' } }, /keyPath is required/],
    [[], /JSON object/],
  ])('rejects invalid config %j', (raw, msg) => {
    expect(() => parseConfig(raw, CFG)).toThrow(ConfigError);
    expect(() => parseConfig(raw, CFG)).toThrow(msg);
  });

  it('strips a trailing slash from publicBaseUrl', () => {
    expect(parseConfig({ publicBaseUrl: 'https://h.ts.net/' }, CFG).publicBaseUrl).toBe('https://h.ts.net');
  });
});

describe('paths', () => {
  it('expands ~', () => {
    expect(expandHome('~/x')).toBe(path.join(os.homedir(), 'x'));
    expect(expandHome('/abs')).toBe('/abs');
  });
  it('honours IOS_DIST_CONFIG', () => {
    expect(resolveConfigPath({ IOS_DIST_CONFIG: '/tmp/c.json' })).toBe('/tmp/c.json');
    expect(resolveConfigPath({})).toBe(path.join(os.homedir(), '.ios-dist', 'config.json'));
  });
});
