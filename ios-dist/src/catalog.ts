import { existsSync } from 'node:fs';
import { readFile, readdir, rm } from 'node:fs/promises';
import path from 'node:path';
import { compareVersions } from './version.js';

export type DistributionMethod = 'ad-hoc' | 'development' | 'enterprise' | 'app-store' | 'unknown';

export interface ProfileInfo {
  name: string;
  teamId?: string;
  teamName?: string;
  expiresAt?: string;
  method: DistributionMethod;
  deviceCount?: number;
}

export interface BuildMeta {
  bundleId: string;
  name: string;
  version: string;
  build: string;
  minOS?: string;
  size: number;
  sha256: string;
  publishedAt: string;
  notes?: string;
  gitCommit?: string;
  profile?: ProfileInfo;
}

export interface AppEntry {
  bundleId: string;
  name: string;
  hasIcon: boolean;
  latest: BuildMeta;
  /** Newest first. */
  builds: BuildMeta[];
}

// Path segments come straight from URLs, so these patterns are also the path-traversal guard.
export function isValidBundleId(s: string): boolean {
  return /^[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)*$/.test(s);
}

export function isValidBuild(s: string): boolean {
  return /^\d+(\.\d+){0,2}$/.test(s);
}

function assertIds(bundleId: string, build?: string): void {
  if (!isValidBundleId(bundleId)) throw new Error(`invalid bundle id: ${bundleId}`);
  if (build !== undefined && !isValidBuild(build)) throw new Error(`invalid build number: ${build}`);
}

export function appDir(dataDir: string, bundleId: string): string {
  assertIds(bundleId);
  return path.join(dataDir, 'apps', bundleId);
}

export function buildDir(dataDir: string, bundleId: string, build: string): string {
  assertIds(bundleId, build);
  return path.join(appDir(dataDir, bundleId), 'builds', build);
}

export const ipaFile = (dataDir: string, bundleId: string, build: string) =>
  path.join(buildDir(dataDir, bundleId, build), 'app.ipa');

export const metaFile = (dataDir: string, bundleId: string, build: string) =>
  path.join(buildDir(dataDir, bundleId, build), 'meta.json');

export const iconFile = (dataDir: string, bundleId: string) => path.join(appDir(dataDir, bundleId), 'icon.png');

function isBuildMeta(v: unknown): v is BuildMeta {
  if (typeof v !== 'object' || v === null) return false;
  const m = v as Record<string, unknown>;
  return (
    typeof m.bundleId === 'string' &&
    typeof m.name === 'string' &&
    typeof m.version === 'string' &&
    typeof m.build === 'string' &&
    typeof m.size === 'number' &&
    typeof m.sha256 === 'string' &&
    typeof m.publishedAt === 'string'
  );
}

async function readMeta(file: string): Promise<BuildMeta | undefined> {
  try {
    const parsed: unknown = JSON.parse(await readFile(file, 'utf8'));
    return isBuildMeta(parsed) ? parsed : undefined;
  } catch {
    return undefined;
  }
}

export async function loadApp(dataDir: string, bundleId: string): Promise<AppEntry | undefined> {
  if (!isValidBundleId(bundleId)) return undefined;
  let names: string[];
  try {
    names = await readdir(path.join(appDir(dataDir, bundleId), 'builds'));
  } catch {
    return undefined;
  }
  // Staging dirs ("<build>.partial") fail isValidBuild, so half-ingested builds never show up.
  const metas = await Promise.all(
    names.filter(isValidBuild).map(async (build) => {
      const meta = await readMeta(metaFile(dataDir, bundleId, build));
      if (!meta || meta.bundleId !== bundleId || meta.build !== build) return undefined;
      if (!existsSync(ipaFile(dataDir, bundleId, build))) return undefined;
      return meta;
    }),
  );
  const builds = metas.filter((m): m is BuildMeta => m !== undefined).sort((a, b) => compareVersions(b.build, a.build));
  const latest = builds[0];
  if (!latest) return undefined;
  return {
    bundleId,
    name: latest.name,
    hasIcon: existsSync(iconFile(dataDir, bundleId)),
    latest,
    builds,
  };
}

export async function loadCatalog(dataDir: string): Promise<AppEntry[]> {
  let ids: string[];
  try {
    ids = await readdir(path.join(dataDir, 'apps'));
  } catch {
    return [];
  }
  const apps = await Promise.all(ids.filter(isValidBundleId).map((id) => loadApp(dataDir, id)));
  return apps
    .filter((a): a is AppEntry => a !== undefined)
    .sort((a, b) => a.name.localeCompare(b.name, undefined, { sensitivity: 'base' }));
}

/** Deletes all but the newest `keep` builds. Returns the removed build numbers. */
export async function pruneBuilds(dataDir: string, bundleId: string, keep: number): Promise<string[]> {
  const app = await loadApp(dataDir, bundleId);
  if (!app) return [];
  const stale = app.builds.slice(keep).map((b) => b.build);
  for (const build of stale) {
    await rm(buildDir(dataDir, bundleId, build), { recursive: true, force: true });
  }
  return stale;
}
