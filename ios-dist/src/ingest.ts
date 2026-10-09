import { createHash } from 'node:crypto';
import { createReadStream, existsSync } from 'node:fs';
import { copyFile, mkdir, mkdtemp, rename, rm, stat, writeFile } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { appDir, buildDir, iconFile, isValidBuild, isValidBundleId, pruneBuilds, type BuildMeta } from './catalog.js';
import type { Config } from './config.js';
import { extractIcon, inspectIpa, resizeIcon } from './ipa.js';

export interface IngestOptions {
  notes?: string;
  gitCommit?: string;
  /** High-resolution icon (e.g. the 1024px asset catalog PNG); falls back to the IPA's own icon. */
  iconSource?: string;
  /** Replace an existing build with the same number. */
  force?: boolean;
  now?: Date;
}

export interface IngestResult {
  meta: BuildMeta;
  pruned: string[];
}

async function sha256(file: string): Promise<string> {
  const hash = createHash('sha256');
  for await (const chunk of createReadStream(file)) hash.update(chunk as Buffer);
  return hash.digest('hex');
}

/** Copies an IPA into the catalog: <dataDir>/apps/<bundleId>/builds/<build>/{app.ipa,meta.json}. */
export async function ingestIpa(config: Config, ipa: string, opts: IngestOptions = {}): Promise<IngestResult> {
  const work = await mkdtemp(path.join(os.tmpdir(), 'ios-dist-ingest-'));
  try {
    const info = await inspectIpa(ipa, work);
    if (!isValidBundleId(info.bundleId)) throw new Error(`unsupported bundle id: ${info.bundleId}`);
    if (!isValidBuild(info.build)) {
      throw new Error(`CFBundleVersion "${info.build}" must be 1-3 dot-separated integers`);
    }

    const dest = buildDir(config.dataDir, info.bundleId, info.build);
    if (existsSync(dest)) {
      if (!opts.force) throw new Error(`${info.bundleId} build ${info.build} already exists (use --force to replace)`);
      await rm(dest, { recursive: true, force: true });
    }
    // Stage under a name the catalog ignores, then rename so a build appears atomically.
    const staging = `${dest}.partial`;
    await rm(staging, { recursive: true, force: true });
    await mkdir(staging, { recursive: true });
    const stagedIpa = path.join(staging, 'app.ipa');
    await copyFile(ipa, stagedIpa);

    const meta: BuildMeta = {
      bundleId: info.bundleId,
      name: info.name,
      version: info.version,
      build: info.build,
      minOS: info.minOS,
      size: (await stat(stagedIpa)).size,
      sha256: await sha256(stagedIpa),
      publishedAt: (opts.now ?? new Date()).toISOString(),
      notes: opts.notes?.trim() || undefined,
      gitCommit: opts.gitCommit,
      profile: info.profile,
    };
    await writeFile(path.join(staging, 'meta.json'), `${JSON.stringify(meta, null, 2)}\n`);
    await rename(staging, dest);

    await mkdir(appDir(config.dataDir, info.bundleId), { recursive: true });
    const icon = iconFile(config.dataDir, info.bundleId);
    try {
      if (opts.iconSource) {
        await resizeIcon(opts.iconSource, icon);
      } else {
        const raw = path.join(work, 'icon.png');
        if (await extractIcon(ipa, info, work, raw)) await resizeIcon(raw, icon);
      }
    } catch (err) {
      console.warn(`warning: could not extract app icon: ${(err as Error).message}`);
    }

    const pruned = await pruneBuilds(config.dataDir, info.bundleId, config.keepBuilds);
    return { meta, pruned };
  } finally {
    await rm(work, { recursive: true, force: true });
  }
}
