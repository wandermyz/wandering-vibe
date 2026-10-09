import { createReadStream } from 'node:fs';
import { stat } from 'node:fs/promises';
import http from 'node:http';
import { pipeline } from 'node:stream/promises';
import { iconFile, ipaFile, isValidBuild, isValidBundleId, loadApp, loadCatalog, type AppEntry, type BuildMeta } from './catalog.js';
import type { Config } from './config.js';
import { installLink, renderManifest } from './manifest.js';
import { routes } from './routes.js';
import { renderApp, renderIndex, renderNotFound, type ViewContext } from './views.js';

export interface HandlerOptions {
  now?: () => Date;
  log?: (line: string) => void;
}

type Headers = Record<string, string | number>;

function firstHeader(v: string | string[] | undefined): string | undefined {
  const raw = Array.isArray(v) ? v[0] : v;
  return raw?.split(',')[0]?.trim() || undefined;
}

/**
 * Absolute base URL for manifests and install links. Behind `tailscale serve` the request arrives
 * as plain HTTP on localhost, but the device reached us via https://<host>.ts.net.
 */
export function resolveBaseUrl(
  config: Pick<Config, 'publicBaseUrl' | 'host' | 'port'>,
  headers: http.IncomingHttpHeaders,
): string {
  if (config.publicBaseUrl) return config.publicBaseUrl;
  const host = firstHeader(headers['x-forwarded-host']) ?? firstHeader(headers.host) ?? `${config.host}:${config.port}`;
  const proto = firstHeader(headers['x-forwarded-proto']) ?? (/\.ts\.net(:\d+)?$/i.test(host) ? 'https' : 'http');
  return `${proto}://${host}`;
}

function send(res: http.ServerResponse, status: number, type: string, body: string, headers: Headers = {}): void {
  const buf = Buffer.from(body);
  res.writeHead(status, {
    'Content-Type': type,
    'Content-Length': buf.length,
    'Cache-Control': 'no-store',
    ...headers,
  });
  res.end(res.req.method === 'HEAD' ? undefined : buf);
}

const sendJson = (res: http.ServerResponse, status: number, value: unknown) =>
  send(res, status, 'application/json; charset=utf-8', `${JSON.stringify(value, null, 2)}\n`);

async function serveFile(req: http.IncomingMessage, res: http.ServerResponse, file: string, type: string): Promise<boolean> {
  let size: number;
  let mtime: Date;
  try {
    const st = await stat(file);
    if (!st.isFile()) return false;
    size = st.size;
    mtime = st.mtime;
  } catch {
    return false;
  }
  const headers: Headers = { 'Content-Type': type, 'Accept-Ranges': 'bytes', 'Last-Modified': mtime.toUTCString() };
  let start = 0;
  let end = size - 1;
  const range = req.headers.range;
  if (range) {
    const m = /^bytes=(\d*)-(\d*)$/.exec(range.trim());
    if (m && (m[1] || m[2])) {
      if (m[1]) {
        start = Number(m[1]);
        if (m[2]) end = Math.min(Number(m[2]), size - 1);
      } else {
        start = Math.max(0, size - Number(m[2]));
      }
    }
    if (!m || start > end || start >= size) {
      res.writeHead(416, { 'Content-Range': `bytes */${size}` });
      res.end();
      return true;
    }
    res.writeHead(206, { ...headers, 'Content-Range': `bytes ${start}-${end}/${size}`, 'Content-Length': end - start + 1 });
  } else {
    res.writeHead(200, { ...headers, 'Content-Length': size });
  }
  if (req.method === 'HEAD' || size === 0) {
    res.end();
    return true;
  }
  try {
    await pipeline(createReadStream(file, { start, end }), res);
  } catch {
    // Client went away mid-download; nothing to do.
  }
  return true;
}

function decodeSegment(s: string | undefined): string | undefined {
  if (s === undefined) return undefined;
  try {
    return decodeURIComponent(s);
  } catch {
    return undefined;
  }
}

function apiBuild(baseUrl: string, b: BuildMeta) {
  const manifestUrl = baseUrl + routes.manifest(b.bundleId, b.build);
  return {
    version: b.version,
    build: b.build,
    publishedAt: b.publishedAt,
    size: b.size,
    sha256: b.sha256,
    notes: b.notes,
    gitCommit: b.gitCommit,
    profile: b.profile,
    manifestUrl,
    installUrl: installLink(manifestUrl),
  };
}

function apiApp(baseUrl: string, app: AppEntry) {
  return {
    bundleId: app.bundleId,
    name: app.name,
    iconUrl: app.hasIcon ? baseUrl + routes.icon(app.bundleId) : undefined,
    latest: apiBuild(baseUrl, app.latest),
    builds: app.builds.length,
  };
}

export function createHandler(config: Config, opts: HandlerOptions = {}) {
  const now = opts.now ?? (() => new Date());
  const log = opts.log ?? ((line: string) => console.log(line));

  async function route(req: http.IncomingMessage, res: http.ServerResponse): Promise<void> {
    if (req.method !== 'GET' && req.method !== 'HEAD') {
      return send(res, 405, 'text/plain; charset=utf-8', 'Method Not Allowed\n', { Allow: 'GET, HEAD' });
    }
    const pathname = new URL(req.url ?? '/', 'http://localhost').pathname;
    if (pathname === '/healthz') return sendJson(res, 200, { ok: true });

    if (config.allowedLogins.length > 0) {
      const login = firstHeader(req.headers['tailscale-user-login']);
      if (!login || !config.allowedLogins.includes(login)) {
        return send(res, 403, 'text/plain; charset=utf-8', 'Forbidden\n');
      }
    }

    const baseUrl = resolveBaseUrl(config, req.headers);
    const ctx: ViewContext = { baseUrl, siteTitle: config.siteTitle, now: now() };
    const html = (status: number, body: string) => send(res, status, 'text/html; charset=utf-8', body);
    const notFound = () => html(404, renderNotFound(ctx));

    if (pathname === routes.home) return html(200, renderIndex(await loadCatalog(config.dataDir), ctx));
    if (pathname === routes.apiApps) {
      const apps = await loadCatalog(config.dataDir);
      return sendJson(res, 200, { apps: apps.map((a) => apiApp(baseUrl, a)) });
    }

    const m = /^\/(api\/)?apps\/([^/]+)(?:\/(latest|icon\.png|builds\/([^/]+)\/(manifest\.plist|app\.ipa)))?$/.exec(pathname);
    const bundleId = decodeSegment(m?.[2]);
    if (!m || !bundleId || !isValidBundleId(bundleId)) return notFound();
    const isApi = m[1] !== undefined;
    const sub = m[3];

    if (sub === 'icon.png' && !isApi) {
      if (await serveFile(req, res, iconFile(config.dataDir, bundleId), 'image/png')) return;
      return notFound();
    }

    const app = await loadApp(config.dataDir, bundleId);
    if (!app) return isApi ? sendJson(res, 404, { error: 'not found' }) : notFound();

    if (isApi) {
      if (sub === 'latest') return sendJson(res, 200, { bundleId, name: app.name, ...apiBuild(baseUrl, app.latest) });
      if (sub === undefined) {
        return sendJson(res, 200, { ...apiApp(baseUrl, app), builds: app.builds.map((b) => apiBuild(baseUrl, b)) });
      }
      return sendJson(res, 404, { error: 'not found' });
    }
    if (sub === undefined) return html(200, renderApp(app, ctx));

    const buildNo = decodeSegment(m[4]);
    const build = buildNo && isValidBuild(buildNo) ? app.builds.find((b) => b.build === buildNo) : undefined;
    if (!build) return notFound();

    if (m[5] === 'manifest.plist') {
      const icon = app.hasIcon ? baseUrl + routes.icon(bundleId) : undefined;
      const body = renderManifest({
        ipaUrl: baseUrl + routes.ipa(bundleId, build.build),
        displayImageUrl: icon,
        fullSizeImageUrl: icon,
        bundleId,
        version: build.version,
        title: build.name,
      });
      return send(res, 200, 'application/xml; charset=utf-8', body);
    }
    if (await serveFile(req, res, ipaFile(config.dataDir, bundleId, build.build), 'application/octet-stream')) return;
    return notFound();
  }

  return async (req: http.IncomingMessage, res: http.ServerResponse): Promise<void> => {
    const started = Date.now();
    res.on('finish', () => {
      const who = firstHeader(req.headers['tailscale-user-login']);
      log(`${new Date().toISOString()} ${req.method} ${req.url} ${res.statusCode} ${Date.now() - started}ms${who ? ` ${who}` : ''}`);
    });
    try {
      await route(req, res);
    } catch (err) {
      log(`error handling ${req.method} ${req.url}: ${(err as Error).stack ?? String(err)}`);
      if (!res.headersSent) send(res, 500, 'text/plain; charset=utf-8', 'Internal Server Error\n');
      else res.destroy();
    }
  };
}

export function createServer(config: Config, opts: HandlerOptions = {}): http.Server {
  const handler = createHandler(config, opts);
  return http.createServer((req, res) => void handler(req, res));
}

export async function startServer(config: Config, opts: HandlerOptions = {}): Promise<http.Server> {
  const server = createServer(config, opts);
  await new Promise<void>((resolve, reject) => {
    server.once('error', reject);
    server.listen(config.port, config.host, () => resolve());
  });
  return server;
}
