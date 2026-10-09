import type { AddressInfo } from 'node:net';
import type http from 'node:http';
import { afterEach, describe, expect, it } from 'vitest';
import type { Config } from '../src/config.js';
import { resolveBaseUrl, startServer } from '../src/server.js';
import { addBuild, addIcon, meta, tempConfig } from './helpers.js';

const BASE = 'https://mini.example.ts.net';
let server: http.Server | undefined;

async function start(config: Config): Promise<string> {
  server = await startServer(config, { log: () => {}, now: () => new Date('2026-10-08T13:00:00Z') });
  return `http://127.0.0.1:${(server.address() as AddressInfo).port}`;
}

afterEach(async () => {
  const s = server;
  server = undefined;
  if (!s) return;
  s.closeAllConnections();
  await new Promise((resolve) => s.close(resolve));
});

async function seeded(overrides: Record<string, unknown> = {}) {
  const config = await tempConfig({ publicBaseUrl: BASE, ...overrides });
  await addBuild(config, meta({ build: '1', version: '1.0', notes: 'first <b>' }), '0123456789');
  await addBuild(config, meta({ build: '2', version: '1.1' }), '0123456789');
  await addIcon(config, 'com.example.notes');
  return { config, url: await start(config) };
}

describe('resolveBaseUrl', () => {
  const cfg = { host: '127.0.0.1', port: 8740 };
  it('prefers the configured public URL', () => {
    expect(resolveBaseUrl({ ...cfg, publicBaseUrl: 'https://x' }, { host: 'y' })).toBe('https://x');
  });
  it('uses forwarded headers', () => {
    expect(resolveBaseUrl(cfg, { 'x-forwarded-host': 'a.b, c', 'x-forwarded-proto': 'https', host: 'z' })).toBe('https://a.b');
  });
  it('assumes https for ts.net hosts and http otherwise', () => {
    expect(resolveBaseUrl(cfg, { host: 'mini.tail1.ts.net' })).toBe('https://mini.tail1.ts.net');
    expect(resolveBaseUrl(cfg, { host: 'localhost:8740' })).toBe('http://localhost:8740');
    expect(resolveBaseUrl(cfg, {})).toBe('http://127.0.0.1:8740');
  });
});

describe('web server', () => {
  it('lists apps with an itms-services install link for the latest build', async () => {
    const { url } = await seeded();
    const res = await fetch(`${url}/`);
    expect(res.status).toBe(200);
    const html = await res.text();
    expect(html).toContain('Notes');
    expect(html).toContain('1.1 (2)');
    expect(html).toContain(
      `itms-services://?action=download-manifest&amp;url=${encodeURIComponent(`${BASE}/apps/com.example.notes/builds/2/manifest.plist`)}`,
    );
    expect(html).not.toContain('not served over HTTPS');
  });

  it('warns when not served over HTTPS', async () => {
    const config = await tempConfig();
    const url = await start(config);
    const html = await (await fetch(`${url}/`)).text();
    expect(html).toContain('not served over HTTPS');
    expect(html).toContain('No apps published yet');
  });

  it('renders the app page with build history and escaped notes', async () => {
    const { url } = await seeded();
    const html = await (await fetch(`${url}/apps/com.example.notes`)).text();
    expect(html).toContain(encodeURIComponent('/builds/1/manifest.plist'));
    expect(html).toContain(encodeURIComponent('/builds/2/manifest.plist'));
    expect(html).toContain('first &lt;b&gt;');
  });

  it('serves a manifest pointing at the IPA and icon', async () => {
    const { url } = await seeded();
    const res = await fetch(`${url}/apps/com.example.notes/builds/1/manifest.plist`);
    expect(res.headers.get('content-type')).toContain('xml');
    const xml = await res.text();
    expect(xml).toContain(`${BASE}/apps/com.example.notes/builds/1/app.ipa`);
    expect(xml).toContain(`${BASE}/apps/com.example.notes/icon.png`);
    expect(xml).toContain('<string>1.0</string>');
  });

  it('serves IPAs with range support', async () => {
    const { url } = await seeded();
    const full = await fetch(`${url}/apps/com.example.notes/builds/2/app.ipa`);
    expect(full.status).toBe(200);
    expect(full.headers.get('accept-ranges')).toBe('bytes');
    expect(await full.text()).toBe('0123456789');

    const part = await fetch(`${url}/apps/com.example.notes/builds/2/app.ipa`, { headers: { range: 'bytes=2-4' } });
    expect(part.status).toBe(206);
    expect(part.headers.get('content-range')).toBe('bytes 2-4/10');
    expect(await part.text()).toBe('234');

    const suffix = await fetch(`${url}/apps/com.example.notes/builds/2/app.ipa`, { headers: { range: 'bytes=-3' } });
    expect(await suffix.text()).toBe('789');

    const bad = await fetch(`${url}/apps/com.example.notes/builds/2/app.ipa`, { headers: { range: 'bytes=50-' } });
    expect(bad.status).toBe(416);
  });

  it('exposes a JSON API for update checks', async () => {
    const { url } = await seeded();
    const latest = (await (await fetch(`${url}/api/apps/com.example.notes/latest`)).json()) as Record<string, unknown>;
    expect(latest).toMatchObject({ bundleId: 'com.example.notes', version: '1.1', build: '2' });
    expect(String(latest.installUrl)).toMatch(/^itms-services:/);

    const list = (await (await fetch(`${url}/api/apps`)).json()) as { apps: unknown[] };
    expect(list.apps).toHaveLength(1);
    expect((await fetch(`${url}/api/apps/com.example.none/latest`)).status).toBe(404);
  });

  it.each([
    '/apps/..%2F..%2Fetc/builds/1/app.ipa',
    '/apps/com.example.notes/builds/..%2F1/app.ipa',
    '/apps/com.example.notes/builds/9/app.ipa',
    '/apps/com.example.notes/builds/1/meta.json',
    '/apps/com.example.none',
    '/nope',
  ])('returns 404 for %s', async (p) => {
    const { url } = await seeded();
    expect((await fetch(url + p)).status).toBe(404);
  });

  it('rejects non-GET methods', async () => {
    const { url } = await seeded();
    expect((await fetch(`${url}/`, { method: 'POST' })).status).toBe(405);
  });

  it('restricts access to allowed Tailscale logins', async () => {
    const { url } = await seeded({ allowedLogins: ['me@example.com'] });
    expect((await fetch(`${url}/`)).status).toBe(403);
    expect((await fetch(`${url}/`, { headers: { 'tailscale-user-login': 'other@example.com' } })).status).toBe(403);
    expect((await fetch(`${url}/`, { headers: { 'tailscale-user-login': 'me@example.com' } })).status).toBe(200);
    expect((await fetch(`${url}/healthz`)).status).toBe(200);
  });
});
