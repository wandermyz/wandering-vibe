import { describe, expect, it } from 'vitest';
import { detectMethod, findAppRoot, iconPixelSize, pickIconEntries } from '../src/ipa.js';

describe('findAppRoot', () => {
  it('finds the single app bundle', () => {
    expect(findAppRoot(['Payload/', 'Payload/My App.app/', 'Payload/My App.app/Info.plist'])).toBe('Payload/My App.app/');
  });
  it('rejects IPAs without exactly one app', () => {
    expect(() => findAppRoot(['foo.txt'])).toThrow(/found 0/);
    expect(() => findAppRoot(['Payload/A.app/x', 'Payload/B.app/y'])).toThrow(/found 2/);
  });
  it('ignores nested app bundles (e.g. watch apps)', () => {
    expect(findAppRoot(['Payload/A.app/Info.plist', 'Payload/A.app/Watch/W.app/Info.plist'])).toBe('Payload/A.app/');
  });
});

describe('detectMethod', () => {
  it.each([
    [{ provisionsAllDevices: true, deviceCount: 0, getTaskAllow: false }, 'enterprise'],
    [{ provisionsAllDevices: false, deviceCount: 3, getTaskAllow: true }, 'development'],
    [{ provisionsAllDevices: false, deviceCount: 3, getTaskAllow: false }, 'ad-hoc'],
    [{ provisionsAllDevices: false, deviceCount: 0, getTaskAllow: false }, 'app-store'],
  ] as const)('%j -> %s', (input, expected) => {
    expect(detectMethod(input)).toBe(expected);
  });
});

describe('icons', () => {
  it('computes pixel sizes from compiled icon names', () => {
    expect(iconPixelSize('AppIcon60x60@3x.png')).toBe(180);
    expect(iconPixelSize('AppIcon76x76@2x~ipad.png')).toBe(152);
    expect(iconPixelSize('AppIcon83.5x83.5@2x~ipad.png')).toBe(167);
    expect(iconPixelSize('AppIcon.png')).toBe(0);
  });
  it('picks top-level AppIcon PNGs, largest first', () => {
    const root = 'Payload/A.app/';
    const entries = [
      `${root}AppIcon60x60@2x.png`,
      `${root}AppIcon76x76@2x~ipad.png`,
      `${root}AppIcon60x60@3x.png`,
      `${root}Assets.car`,
      `${root}PlugIns/Ext.appex/AppIcon60x60@3x.png`,
    ];
    expect(pickIconEntries(entries, root)).toEqual([
      `${root}AppIcon60x60@3x.png`,
      `${root}AppIcon76x76@2x~ipad.png`,
      `${root}AppIcon60x60@2x.png`,
    ]);
  });
});
