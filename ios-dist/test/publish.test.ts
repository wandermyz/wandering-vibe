import { describe, expect, it } from 'vitest';
import { parseConfig } from '../src/config.js';
import { renderLaunchAgent, whichSync } from '../src/launchd.js';
import { archiveArgs, exportArgs, exportOptions } from '../src/publish.js';
import { serveArgs } from '../src/tailscale.js';

const base = parseConfig({}, '/data/config.json');
const project = { project: '/src/App.xcodeproj', scheme: 'App', configuration: 'Release' };

describe('xcodebuild arguments', () => {
  it('archives with a build number override and no team when unset', () => {
    const args = archiveArgs(base, project, '/w/App.xcarchive', '20261008.120000');
    expect(args).toEqual(expect.arrayContaining(['-project', '/src/App.xcodeproj', '-scheme', 'App', 'archive']));
    expect(args).toContain('CURRENT_PROJECT_VERSION=20261008.120000');
    expect(args).toContain('-allowProvisioningUpdates');
    expect(args.some((a) => a.startsWith('DEVELOPMENT_TEAM='))).toBe(false);
  });

  it('disables code signing for unsigned builds', () => {
    const args = archiveArgs(base, project, '/a', '1', true);
    expect(args).toEqual(expect.arrayContaining(['CODE_SIGNING_ALLOWED=NO', 'CODE_SIGNING_REQUIRED=NO']));
  });

  it('uses the workspace, team and API key when configured', () => {
    const config = parseConfig(
      { teamId: 'ABCDE12345', ascApiKey: { keyPath: '/k.p8', keyId: 'K', issuerId: 'I' } },
      '/data/config.json',
    );
    const args = archiveArgs(config, { ...project, project: undefined, workspace: '/src/App.xcworkspace' }, '/a', '1');
    expect(args.slice(0, 2)).toEqual(['-workspace', '/src/App.xcworkspace']);
    expect(args).toContain('DEVELOPMENT_TEAM=ABCDE12345');
    expect(args).toEqual(expect.arrayContaining(['-authenticationKeyPath', '/k.p8', '-authenticationKeyID', 'K']));
    expect(exportArgs(config, '/a', '/o.plist', '/e')).toEqual(expect.arrayContaining(['-exportArchive', '-authenticationKeyIssuerID', 'I']));
  });

  it('renders export options', () => {
    const xml = exportOptions('release-testing', 'ABCDE12345');
    expect(xml).toContain('<key>method</key>\n\t<string>release-testing</string>');
    expect(xml).toContain('<string>ABCDE12345</string>');
    expect(exportOptions('debugging')).not.toContain('teamID');
  });
});

describe('launchd', () => {
  it('renders a KeepAlive LaunchAgent running `serve`', () => {
    const xml = renderLaunchAgent({
      label: 'com.example.ios-dist',
      nodePath: '/opt/homebrew/bin/node',
      cliPath: '/repo/dist/cli.js',
      configPath: '/home/.ios-dist/config.json',
      workingDir: '/repo',
      logFile: '/home/.ios-dist/logs/server.log',
      pathEnv: '/usr/bin:/bin',
    });
    expect(xml).toContain('<string>com.example.ios-dist</string>');
    expect(xml).toMatch(/<string>\/opt\/homebrew\/bin\/node<\/string>\s*<string>\/repo\/dist\/cli.js<\/string>\s*<string>serve<\/string>/);
    expect(xml).toContain('<key>KeepAlive</key>\n\t<true/>');
    expect(xml).toContain('<key>IOS_DIST_CONFIG</key>');
  });

  it('finds executables on PATH', () => {
    expect(whichSync('sh', '/nonexistent:/bin')).toBe('/bin/sh');
    expect(whichSync('definitely-not-a-binary', '/bin')).toBeUndefined();
  });
});

describe('tailscale serve', () => {
  it('proxies HTTPS to the local server', () => {
    expect(serveArgs(base, true)).toEqual(['serve', '--bg', '--https=443', 'http://127.0.0.1:8740']);
    expect(serveArgs(base, false)).toEqual(['serve', '--https=443', 'off']);
  });
});
