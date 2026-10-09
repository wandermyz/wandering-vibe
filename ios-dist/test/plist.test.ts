import { describe, expect, it } from 'vitest';
import { installLink, renderManifest } from '../src/manifest.js';
import { toPlist, xmlEscape } from '../src/plist.js';

describe('toPlist', () => {
  it('renders nested values and skips undefined keys', () => {
    const xml = toPlist({ a: 'x', b: 1, c: true, d: [1.5], e: undefined, f: {} });
    expect(xml).toContain('<key>a</key>\n\t<string>x</string>');
    expect(xml).toContain('<integer>1</integer>');
    expect(xml).toContain('<true/>');
    expect(xml).toContain('<real>1.5</real>');
    expect(xml).toContain('<dict/>');
    expect(xml).not.toContain('<key>e</key>');
    expect(xml.startsWith('<?xml')).toBe(true);
  });
  it('escapes XML special characters', () => {
    expect(xmlEscape(`<a & "b" 'c'>`)).toBe('&lt;a &amp; &quot;b&quot; &apos;c&apos;&gt;');
  });
});

describe('renderManifest', () => {
  it('includes the package, icons and metadata', () => {
    const xml = renderManifest({
      ipaUrl: 'https://h.ts.net/apps/com.x/builds/1/app.ipa',
      displayImageUrl: 'https://h.ts.net/apps/com.x/icon.png',
      fullSizeImageUrl: 'https://h.ts.net/apps/com.x/icon.png',
      bundleId: 'com.x',
      version: '1.2',
      title: 'R&D <App>',
    });
    expect(xml).toContain('<string>software-package</string>');
    expect(xml).toContain('<string>https://h.ts.net/apps/com.x/builds/1/app.ipa</string>');
    expect(xml).toContain('<string>display-image</string>');
    expect(xml).toContain('<key>bundle-identifier</key>\n\t\t\t\t<string>com.x</string>');
    expect(xml).toContain('R&amp;D &lt;App&gt;');
  });
  it('omits icon assets when there is no icon', () => {
    const xml = renderManifest({ ipaUrl: 'https://h/a.ipa', bundleId: 'com.x', version: '1', title: 'X' });
    expect(xml).not.toContain('display-image');
  });
});

describe('installLink', () => {
  it('URL-encodes the manifest URL', () => {
    expect(installLink('https://h.ts.net/a b/manifest.plist?x=1')).toBe(
      'itms-services://?action=download-manifest&url=https%3A%2F%2Fh.ts.net%2Fa%20b%2Fmanifest.plist%3Fx%3D1',
    );
  });
});
