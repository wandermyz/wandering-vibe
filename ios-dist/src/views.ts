import type { AppEntry, BuildMeta } from './catalog.js';
import { installLink } from './manifest.js';
import { routes } from './routes.js';

export interface ViewContext {
  baseUrl: string;
  siteTitle: string;
  now: Date;
}

const DAY_MS = 86_400_000;
const EXPIRY_WARNING_DAYS = 30;

export function escapeHtml(s: string): string {
  return s
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

export function formatSize(bytes: number): string {
  if (bytes < 1024 * 1024) return `${Math.max(1, Math.round(bytes / 1024))} KB`;
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
}

function formatDate(iso: string): string {
  return new Date(iso).toLocaleString('en-US', { dateStyle: 'medium', timeStyle: 'short' });
}

export function relativeTime(iso: string, now: Date): string {
  const seconds = Math.round((now.getTime() - Date.parse(iso)) / 1000);
  if (seconds < 60) return 'just now';
  if (seconds < 3600) return `${Math.floor(seconds / 60)} min ago`;
  if (seconds < 86_400) return `${Math.floor(seconds / 3600)} hr ago`;
  const days = Math.floor(seconds / 86_400);
  if (days < 30) return days === 1 ? 'yesterday' : `${days} days ago`;
  return formatDate(iso);
}

export function daysUntil(iso: string, now: Date): number {
  return Math.floor((Date.parse(iso) - now.getTime()) / DAY_MS);
}

function installHref(ctx: ViewContext, b: BuildMeta): string {
  return installLink(ctx.baseUrl + routes.manifest(b.bundleId, b.build));
}

function iconHtml(app: Pick<AppEntry, 'bundleId' | 'name' | 'hasIcon'>, cls: string): string {
  if (app.hasIcon) return `<img class="icon ${cls}" src="${routes.icon(app.bundleId)}" alt="">`;
  const initial = escapeHtml(app.name.trim().charAt(0).toUpperCase() || '?');
  return `<div class="icon ${cls} placeholder" aria-hidden="true">${initial}</div>`;
}

function badges(b: BuildMeta, now: Date): string {
  const out: string[] = [];
  const profile = b.profile;
  if (profile) {
    const cls = profile.method === 'ad-hoc' ? 'ok' : profile.method === 'development' ? 'info' : 'warn';
    out.push(`<span class="badge ${cls}">${escapeHtml(profile.method)}</span>`);
    if (profile.expiresAt) {
      const days = daysUntil(profile.expiresAt, now);
      if (days < 0) out.push('<span class="badge danger">profile expired</span>');
      else if (days <= EXPIRY_WARNING_DAYS) out.push(`<span class="badge warn">expires in ${days}d</span>`);
    }
  } else {
    out.push('<span class="badge danger">unsigned</span>');
  }
  return out.join(' ');
}

/** `latest` buttons get relabeled client-side ("Update" / "Reinstall"); older builds stay "Install". */
function installButton(ctx: ViewContext, b: BuildMeta, opts: { cls?: string; latest?: boolean } = {}): string {
  return (
    `<a class="btn ${opts.cls ?? ''}" href="${escapeHtml(installHref(ctx, b))}" ` +
    `data-bundle="${escapeHtml(b.bundleId)}" data-build="${escapeHtml(b.build)}"` +
    `${opts.latest ? ' data-latest="1"' : ''}>Install</a>`
  );
}

const STYLE = `
:root { color-scheme: light dark; --bg:#f2f2f7; --card:#fff; --text:#000; --muted:#6c6c70; --line:#e5e5ea;
  --accent:#007aff; --accent-soft:#e8f1ff; --ok:#1f8f3a; --warn:#b26a00; --danger:#d70015; --info:#5e5ce6; }
@media (prefers-color-scheme: dark) { :root { --bg:#000; --card:#1c1c1e; --text:#fff; --muted:#98989f; --line:#38383a;
  --accent:#0a84ff; --accent-soft:#0a84ff26; } }
* { box-sizing: border-box; }
body { margin:0; font: 16px/1.4 -apple-system, BlinkMacSystemFont, "SF Pro Text", system-ui, sans-serif;
  background: var(--bg); color: var(--text); -webkit-text-size-adjust: 100%; }
main { max-width: 680px; margin: 0 auto; padding: max(16px, env(safe-area-inset-top)) 16px 48px; }
a { color: var(--accent); text-decoration: none; }
header.top h1 { font-size: 34px; margin: 12px 0 2px; letter-spacing: -0.5px; }
.sub { color: var(--muted); margin: 0 0 16px; font-size: 15px; }
.banner { background: #fff4e5; color: #6b3d00; border-radius: 12px; padding: 10px 14px; font-size: 14px; margin-bottom: 16px; }
@media (prefers-color-scheme: dark) { .banner { background: #3a2a10; color: #ffd58a; } }
.list { list-style: none; margin: 0; padding: 0; background: var(--card); border-radius: 14px; overflow: hidden; }
.list > li { display: flex; align-items: center; gap: 12px; padding: 12px 14px; border-top: 1px solid var(--line); }
.list > li:first-child { border-top: 0; }
.row-link { display: flex; align-items: center; gap: 12px; flex: 1; min-width: 0; color: inherit; }
.icon { width: 60px; height: 60px; border-radius: 13.5px; flex: none; object-fit: cover; border: 0.5px solid var(--line); }
.icon.big { width: 96px; height: 96px; border-radius: 21.5px; }
.placeholder { display: grid; place-items: center; font-weight: 600; font-size: 26px; color: #fff;
  background: linear-gradient(135deg, #5ac8fa, #007aff); }
.icon.big.placeholder { font-size: 42px; }
.info { min-width: 0; }
.info h2 { font-size: 17px; font-weight: 600; margin: 0; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.info p { margin: 2px 0 0; color: var(--muted); font-size: 13px; }
.badge { display: inline-block; font-size: 11px; font-weight: 600; padding: 1px 7px; border-radius: 999px;
  border: 1px solid currentColor; text-transform: uppercase; letter-spacing: 0.3px; }
.badge.ok { color: var(--ok); } .badge.warn { color: var(--warn); } .badge.danger { color: var(--danger); }
.badge.info { color: var(--info); }
.btn { flex: none; display: inline-block; min-width: 76px; text-align: center; font-weight: 700; font-size: 15px;
  padding: 6px 16px; border-radius: 999px; background: var(--accent-soft); color: var(--accent); }
.btn.primary, .btn.update { background: var(--accent); color: #fff; }
.btn.secondary { background: transparent; border: 1px solid var(--line); color: var(--muted); font-weight: 600; }
.empty { background: var(--card); border-radius: 14px; padding: 28px 20px; text-align: center; color: var(--muted); }
code { font: 13px ui-monospace, SFMono-Regular, Menlo, monospace; background: var(--bg); padding: 1px 5px; border-radius: 5px; }
.back { display: inline-block; margin: 6px 0 10px; font-size: 17px; }
.hero { display: flex; gap: 16px; align-items: center; margin-bottom: 18px; }
.hero h1 { font-size: 24px; margin: 0; }
.hero .bundle { color: var(--muted); font-size: 13px; margin: 2px 0 10px; word-break: break-all; }
h3 { font-size: 20px; margin: 26px 0 8px; }
.card { background: var(--card); border-radius: 14px; padding: 14px; }
.notes { white-space: pre-wrap; margin: 0; }
dl.facts { display: grid; grid-template-columns: auto 1fr; gap: 6px 14px; margin: 0; font-size: 14px; }
dl.facts dt { color: var(--muted); } dl.facts dd { margin: 0; word-break: break-all; }
.build-notes { margin: 4px 0 0; font-size: 13px; color: var(--text); white-space: pre-wrap; }
footer { margin-top: 28px; color: var(--muted); font-size: 12px; text-align: center; }
`;

// Safari can't see what is installed, so remember what this device installed from here and
// relabel buttons ("Update" when a newer build exists, "Reinstall" for the same build).
const SCRIPT = `
(function () {
  function cmp(a, b) {
    var pa = a.split('.'), pb = b.split('.');
    for (var i = 0; i < Math.max(pa.length, pb.length); i++) {
      var d = (parseInt(pa[i], 10) || 0) - (parseInt(pb[i], 10) || 0);
      if (d) return d;
    }
    return 0;
  }
  document.querySelectorAll('a.btn[data-bundle]').forEach(function (btn) {
    var key = 'installed:' + btn.dataset.bundle;
    var installed = null;
    try { installed = localStorage.getItem(key); } catch (e) {}
    if (installed && btn.dataset.latest === '1') {
      var c = cmp(btn.dataset.build, installed);
      if (c > 0) { btn.textContent = 'Update'; btn.classList.add('update'); }
      else if (c === 0) { btn.textContent = 'Reinstall'; btn.classList.add('secondary'); }
    }
    btn.addEventListener('click', function () {
      try { localStorage.setItem(key, btn.dataset.build); } catch (e) {}
    });
  });
})();
`;

function layout(ctx: ViewContext, title: string, body: string): string {
  const banner = ctx.baseUrl.startsWith('https://')
    ? ''
    : '<div class="banner">This page is not served over HTTPS, so iOS will refuse to install. ' +
      'Open it through the Tailscale HTTPS address (<code>https://&lt;host&gt;.ts.net</code>).</div>';
  return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<meta name="apple-mobile-web-app-capable" content="yes">
<meta name="apple-mobile-web-app-title" content="${escapeHtml(ctx.siteTitle)}">
<link rel="icon" href="data:,">
<title>${escapeHtml(title)}</title>
<style>${STYLE}</style>
</head>
<body>
<main>
${banner}
${body}
<footer>ios-dist · ${escapeHtml(formatDate(ctx.now.toISOString()))}</footer>
</main>
<script>${SCRIPT}</script>
</body>
</html>
`;
}

export function renderIndex(apps: AppEntry[], ctx: ViewContext): string {
  const count = apps.length === 1 ? '1 app' : `${apps.length} apps`;
  const list = apps.length
    ? `<ul class="list">${apps
        .map((app) => {
          const b = app.latest;
          return `<li>
  <a class="row-link" href="${routes.app(app.bundleId)}">
    ${iconHtml(app, '')}
    <div class="info">
      <h2>${escapeHtml(app.name)}</h2>
      <p>${escapeHtml(b.version)} (${escapeHtml(b.build)}) · ${escapeHtml(relativeTime(b.publishedAt, ctx.now))}</p>
      <p>${formatSize(b.size)} ${badges(b, ctx.now)}</p>
    </div>
  </a>
  ${installButton(ctx, b, { latest: true })}
</li>`;
        })
        .join('\n')}</ul>`
    : '<div class="empty">No apps published yet.<br>Run <code>ios-dist publish &lt;project&gt;</code> on the Mac.</div>';
  return layout(
    ctx,
    ctx.siteTitle,
    `<header class="top"><h1>${escapeHtml(ctx.siteTitle)}</h1><p class="sub">${count}</p></header>\n${list}`,
  );
}

export function renderApp(app: AppEntry, ctx: ViewContext): string {
  const b = app.latest;
  const profile = b.profile;
  const facts: [string, string][] = [
    ['Version', `${b.version} (${b.build})`],
    ['Published', formatDate(b.publishedAt)],
    ['Size', formatSize(b.size)],
  ];
  if (b.minOS) facts.push(['Requires', `iOS ${b.minOS}+`]);
  if (b.gitCommit) facts.push(['Commit', b.gitCommit]);
  if (profile) {
    facts.push(['Signing', `${profile.method}${profile.teamName ? ` · ${profile.teamName}` : ''}`]);
    if (profile.expiresAt) facts.push(['Profile expires', formatDate(profile.expiresAt)]);
    if (profile.deviceCount !== undefined) facts.push(['Devices', String(profile.deviceCount)]);
  }
  facts.push(['SHA-256', `${b.sha256.slice(0, 16)}…`]);

  const history = app.builds
    .map((build, i) => {
      const btn = i === 0 ? installButton(ctx, build, { latest: true }) : installButton(ctx, build, { cls: 'secondary' });
      const notes = build.notes ? `<p class="build-notes">${escapeHtml(build.notes)}</p>` : '';
      return `<li>
  <div class="info" style="flex:1">
    <h2>${escapeHtml(build.version)} (${escapeHtml(build.build)})</h2>
    <p>${escapeHtml(relativeTime(build.publishedAt, ctx.now))} · ${formatSize(build.size)}${
      build.gitCommit ? ` · <code>${escapeHtml(build.gitCommit)}</code>` : ''
    } ${badges(build, ctx.now)}</p>
    ${notes}
  </div>
  ${btn}
</li>`;
    })
    .join('\n');

  const body = `<a class="back" href="${routes.home}">‹ ${escapeHtml(ctx.siteTitle)}</a>
<section class="hero">
  ${iconHtml(app, 'big')}
  <div class="info">
    <h1>${escapeHtml(app.name)}</h1>
    <p class="bundle">${escapeHtml(app.bundleId)}</p>
    ${installButton(ctx, b, { cls: 'primary', latest: true })}
  </div>
</section>
${b.notes ? `<h3>What's New</h3><div class="card"><p class="notes">${escapeHtml(b.notes)}</p></div>` : ''}
<h3>Information</h3>
<div class="card"><dl class="facts">${facts
    .map(([k, v]) => `<dt>${escapeHtml(k)}</dt><dd>${escapeHtml(v)}</dd>`)
    .join('')}</dl></div>
<h3>Builds</h3>
<ul class="list">${history}</ul>`;
  return layout(ctx, `${app.name} · ${ctx.siteTitle}`, body);
}

export function renderNotFound(ctx: ViewContext): string {
  return layout(
    ctx,
    `Not found · ${ctx.siteTitle}`,
    `<a class="back" href="${routes.home}">‹ ${escapeHtml(ctx.siteTitle)}</a><div class="empty">Not found.</div>`,
  );
}
