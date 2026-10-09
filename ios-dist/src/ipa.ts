import { copyFile, readdir, stat, writeFile } from 'node:fs/promises';
import path from 'node:path';
import type { DistributionMethod, ProfileInfo } from './catalog.js';
import { run, runBuffer, tryRun } from './exec.js';

export interface IpaInfo {
  appRoot: string;
  bundleId: string;
  name: string;
  version: string;
  build: string;
  minOS?: string;
  profile?: ProfileInfo;
  iconEntries: string[];
}

/** Returns the single "Payload/<Name>.app/" prefix inside an IPA. */
export function findAppRoot(entries: string[]): string {
  const roots = new Set<string>();
  for (const e of entries) {
    const m = /^(Payload\/[^/]+\.app\/)/.exec(e);
    if (m?.[1]) roots.add(m[1]);
  }
  const [root] = roots;
  if (roots.size !== 1 || !root) throw new Error(`expected exactly one Payload/*.app in the IPA, found ${roots.size}`);
  return root;
}

export function detectMethod(p: { provisionsAllDevices: boolean; deviceCount: number; getTaskAllow: boolean }): DistributionMethod {
  if (p.provisionsAllDevices) return 'enterprise';
  if (p.deviceCount > 0) return p.getTaskAllow ? 'development' : 'ad-hoc';
  return 'app-store';
}

/** Pixel size encoded in compiled icon names, e.g. "AppIcon60x60@3x.png" -> 180. */
export function iconPixelSize(fileName: string): number {
  const m = /(\d+(?:\.\d+)?)x\1(?:@(\d)x)?/.exec(fileName);
  if (!m?.[1]) return 0;
  return Number(m[1]) * Number(m[2] ?? 1);
}

/** App icon PNGs at the top level of the .app bundle, largest first. */
export function pickIconEntries(entries: string[], appRoot: string): string[] {
  return entries
    .filter((e) => e.startsWith(appRoot) && /^AppIcon[^/]*\.png$/i.test(e.slice(appRoot.length)))
    .sort((a, b) => iconPixelSize(path.basename(b)) - iconPixelSize(path.basename(a)));
}

async function plistGet(file: string, keyPath: string, format: 'raw' | 'json'): Promise<string | undefined> {
  const r = await tryRun('plutil', ['-extract', keyPath, format, '-o', '-', file]);
  return r.code === 0 ? r.stdout.trim() : undefined;
}

async function extractEntry(ipa: string, entry: string, dest: string): Promise<void> {
  await writeFile(dest, await runBuffer('unzip', ['-p', ipa, entry]));
}

async function readProfile(ipa: string, entry: string, workDir: string): Promise<ProfileInfo> {
  const raw = path.join(workDir, 'embedded.mobileprovision');
  const decoded = path.join(workDir, 'profile.plist');
  await extractEntry(ipa, entry, raw);
  await run('security', ['cms', '-D', '-i', raw, '-o', decoded]);
  const get = (k: string, f: 'raw' | 'json' = 'raw') => plistGet(decoded, k, f);
  const teamIds = await get('TeamIdentifier', 'json');
  const devices = await get('ProvisionedDevices', 'json');
  const deviceCount = devices ? (JSON.parse(devices) as unknown[]).length : 0;
  return {
    name: (await get('Name')) ?? 'unknown',
    teamId: teamIds ? (JSON.parse(teamIds) as string[])[0] : undefined,
    teamName: await get('TeamName'),
    expiresAt: await get('ExpirationDate'),
    method: detectMethod({
      provisionsAllDevices: (await get('ProvisionsAllDevices')) === 'true',
      deviceCount,
      getTaskAllow: (await get('Entitlements.get-task-allow')) === 'true',
    }),
    deviceCount,
  };
}

export async function inspectIpa(ipa: string, workDir: string): Promise<IpaInfo> {
  const entries = (await run('unzip', ['-Z1', ipa])).split('\n').filter(Boolean);
  const appRoot = findAppRoot(entries);
  const infoPlist = path.join(workDir, 'Info.plist');
  await extractEntry(ipa, `${appRoot}Info.plist`, infoPlist);
  const get = (k: string) => plistGet(infoPlist, k, 'raw');

  const bundleId = await get('CFBundleIdentifier');
  const build = await get('CFBundleVersion');
  if (!bundleId || !build) throw new Error('Info.plist is missing CFBundleIdentifier or CFBundleVersion');
  const profileEntry = `${appRoot}embedded.mobileprovision`;

  return {
    appRoot,
    bundleId,
    build,
    version: (await get('CFBundleShortVersionString')) ?? build,
    name: (await get('CFBundleDisplayName')) ?? (await get('CFBundleName')) ?? bundleId,
    minOS: await get('MinimumOSVersion'),
    profile: entries.includes(profileEntry) ? await readProfile(ipa, profileEntry, workDir) : undefined,
    iconEntries: pickIconEntries(entries, appRoot),
  };
}

/**
 * Pulls the biggest app icon out of the IPA into `dest` as a normal PNG. Xcode stores icons
 * in Apple's CgBI PNG variant that browsers can't decode, so it is converted back first.
 */
export async function extractIcon(ipa: string, info: IpaInfo, workDir: string, dest: string): Promise<boolean> {
  const entry = info.iconEntries[0];
  if (!entry) return false;
  const crushed = path.join(workDir, 'icon-cgbi.png');
  await extractEntry(ipa, entry, crushed);
  const reverted = await tryRun('xcrun', ['pngcrush', '-q', '-revert-iphone-optimizations', crushed, dest]);
  if (reverted.code !== 0) await copyFile(crushed, dest);
  return true;
}

/** Writes a square PNG of at most `size` px from any image sips can read. */
export async function resizeIcon(src: string, dest: string, size = 256): Promise<void> {
  await run('sips', ['-s', 'format', 'png', '-Z', String(size), src, '--out', dest]);
}

/**
 * Finds the source 1024px icon in an Xcode project's AppIcon.appiconset — much sharper
 * than the 120/180px icons compiled into the IPA.
 */
export async function findAppIconSource(projectDir: string, maxDepth = 5): Promise<string | undefined> {
  const skip = new Set(['node_modules', 'build', 'DerivedData', '.git', 'Pods']);
  async function walk(dir: string, depth: number): Promise<string | undefined> {
    let entries;
    try {
      entries = await readdir(dir, { withFileTypes: true });
    } catch {
      return undefined;
    }
    for (const e of entries) {
      if (!e.isDirectory() || skip.has(e.name)) continue;
      const full = path.join(dir, e.name);
      if (e.name === 'AppIcon.appiconset') {
        const pngs = (await readdir(full)).filter((f) => f.toLowerCase().endsWith('.png'));
        const sized = await Promise.all(pngs.map(async (f) => ({ f, size: (await stat(path.join(full, f))).size })));
        const best = sized.sort((a, b) => b.size - a.size)[0];
        if (best) return path.join(full, best.f);
      } else if (depth < maxDepth) {
        const found = await walk(full, depth + 1);
        if (found) return found;
      }
    }
    return undefined;
  }
  return walk(projectDir, 0);
}
