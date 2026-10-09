import { describe, expect, it } from 'vitest';
import { compareVersions, makeBuildNumber } from '../src/version.js';

describe('compareVersions', () => {
  it('compares numerically, not lexically', () => {
    expect(compareVersions('1.10', '1.9')).toBe(1);
    expect(compareVersions('1.9', '1.10')).toBe(-1);
  });
  it('treats missing components as zero', () => {
    expect(compareVersions('1.0', '1')).toBe(0);
    expect(compareVersions('1.0.1', '1')).toBe(1);
  });
  it('orders timestamp build numbers', () => {
    expect(compareVersions('20261008.090500', '20261008.223015')).toBe(-1);
    expect(compareVersions('20261009.000001', '20261008.235959')).toBe(1);
  });
});

describe('makeBuildNumber', () => {
  it('formats local time as YYYYMMDD.HHmmss', () => {
    expect(makeBuildNumber(new Date(2026, 9, 8, 9, 5, 7))).toBe('20261008.090507');
  });
  it('increases over time', () => {
    const a = makeBuildNumber(new Date(2026, 9, 8, 23, 59, 59));
    const b = makeBuildNumber(new Date(2026, 9, 9, 0, 0, 0));
    expect(compareVersions(b, a)).toBe(1);
  });
});
