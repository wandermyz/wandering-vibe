import { describe, expect, it } from 'vitest';
import { daysUntil, escapeHtml, formatSize, relativeTime, renderIndex } from '../src/views.js';
import { meta } from './helpers.js';

const now = new Date('2026-10-08T12:00:00Z');
const ctx = { baseUrl: 'https://h.ts.net', siteTitle: 'My <Apps>', now };

describe('formatting helpers', () => {
  it('escapes HTML', () => {
    expect(escapeHtml(`<a href="x">'&'</a>`)).toBe('&lt;a href=&quot;x&quot;&gt;&#39;&amp;&#39;&lt;/a&gt;');
  });
  it('formats sizes', () => {
    expect(formatSize(500)).toBe('1 KB');
    expect(formatSize(5 * 1024 * 1024 + 300_000)).toBe('5.3 MB');
  });
  it('formats relative times', () => {
    expect(relativeTime('2026-10-08T11:59:30Z', now)).toBe('just now');
    expect(relativeTime('2026-10-08T11:15:00Z', now)).toBe('45 min ago');
    expect(relativeTime('2026-10-08T09:00:00Z', now)).toBe('3 hr ago');
    expect(relativeTime('2026-10-07T09:00:00Z', now)).toBe('yesterday');
    expect(relativeTime('2026-10-01T09:00:00Z', now)).toBe('7 days ago');
  });
  it('counts days until expiry', () => {
    expect(daysUntil('2026-10-18T12:00:00Z', now)).toBe(10);
    expect(daysUntil('2026-10-07T12:00:00Z', now)).toBe(-1);
  });
});

describe('renderIndex', () => {
  it('flags expiring profiles and development builds', () => {
    const html = renderIndex(
      [
        {
          bundleId: 'com.example.notes',
          name: 'Notes',
          hasIcon: false,
          latest: meta({ profile: { name: 'p', method: 'development', expiresAt: '2026-10-15T00:00:00Z' } }),
          builds: [],
        },
      ],
      ctx,
    );
    expect(html).toContain('expires in 6d');
    expect(html).toContain('>development<');
    expect(html).toContain('My &lt;Apps&gt;');
    expect(html).toContain('placeholder');
    expect(html).toContain('data-latest="1"');
  });
  it('flags expired profiles', () => {
    const html = renderIndex(
      [
        {
          bundleId: 'com.example.notes',
          name: 'Notes',
          hasIcon: true,
          latest: meta({ profile: { name: 'p', method: 'ad-hoc', expiresAt: '2026-01-01T00:00:00Z' } }),
          builds: [],
        },
      ],
      ctx,
    );
    expect(html).toContain('profile expired');
    expect(html).toContain('src="/apps/com.example.notes/icon.png"');
  });
});
