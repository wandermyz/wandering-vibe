import { createWriteStream, existsSync } from 'node:fs';
import { cp, mkdir, readdir, rm, writeFile } from 'node:fs/promises';
import path from 'node:path';
import type { Config, ProjectConfig } from './config.js';
import { run, runStreaming, tryRun } from './exec.js';
import { ingestIpa, type IngestResult } from './ingest.js';
import { findAppIconSource } from './ipa.js';
import { toPlist } from './plist.js';
import { makeBuildNumber } from './version.js';

export interface PublishOptions {
  notes?: string;
  /** Overrides config.exportMethod (e.g. "debugging" while only a free team is available). */
  method?: string;
  buildNumber?: string;
  /**
   * Skip code signing and package the .app by hand. The IPA won't install on a device, but it
   * exercises the rest of the pipeline before signing is set up.
   */
  unsigned?: boolean;
  log?: (line: string) => void;
}

function authArgs(config: Config): string[] {
  const key = config.ascApiKey;
  if (!key) return [];
  return [
    '-authenticationKeyPath', key.keyPath,
    '-authenticationKeyID', key.keyId,
    '-authenticationKeyIssuerID', key.issuerId,
  ];
}

export function archiveArgs(
  config: Config,
  project: ProjectConfig,
  archivePath: string,
  buildNumber: string,
  unsigned = false,
): string[] {
  return [
    ...(project.workspace ? ['-workspace', project.workspace] : ['-project', project.project ?? '']),
    '-scheme', project.scheme,
    '-configuration', project.configuration,
    '-destination', 'generic/platform=iOS',
    '-archivePath', archivePath,
    '-allowProvisioningUpdates',
    ...authArgs(config),
    'archive',
    // Build settings on the command line override the project without editing it.
    `CURRENT_PROJECT_VERSION=${buildNumber}`,
    ...(config.teamId ? [`DEVELOPMENT_TEAM=${config.teamId}`] : []),
    ...(unsigned ? ['CODE_SIGNING_ALLOWED=NO', 'CODE_SIGNING_REQUIRED=NO', 'CODE_SIGN_IDENTITY='] : []),
  ];
}

export function exportArgs(config: Config, archivePath: string, optionsPlist: string, exportPath: string): string[] {
  return [
    '-exportArchive',
    '-archivePath', archivePath,
    '-exportOptionsPlist', optionsPlist,
    '-exportPath', exportPath,
    '-allowProvisioningUpdates',
    ...authArgs(config),
  ];
}

export function exportOptions(method: string, teamId?: string): string {
  return toPlist({
    method,
    teamID: teamId,
    signingStyle: 'automatic',
    destination: 'export',
    thinning: '<none>',
    stripSwiftSymbols: true,
  });
}

/** Zips <archive>/Products/Applications/*.app as Payload/ — what -exportArchive does, minus signing. */
async function packageUnsigned(archivePath: string, exportPath: string, name: string): Promise<string> {
  const apps = path.join(archivePath, 'Products', 'Applications');
  const app = (await readdir(apps)).find((f) => f.endsWith('.app'));
  if (!app) throw new Error(`no .app found in ${apps}`);
  const payload = path.join(exportPath, 'Payload');
  await mkdir(payload, { recursive: true });
  await cp(path.join(apps, app), path.join(payload, app), { recursive: true, verbatimSymlinks: true });
  const ipa = path.join(exportPath, `${name}.ipa`);
  await run('ditto', ['-c', '-k', '--sequesterRsrc', '--keepParent', payload, ipa]);
  return ipa;
}

/** "abc1234", or "abc1234-dirty" when the project directory has uncommitted changes. */
async function gitCommit(dir: string): Promise<string | undefined> {
  const head = await tryRun('git', ['-C', dir, 'rev-parse', '--short', 'HEAD']);
  if (head.code !== 0) return undefined;
  const dirty = await tryRun('git', ['-C', dir, 'status', '--porcelain', '--', '.']);
  return `${head.stdout.trim()}${dirty.stdout.trim() ? '-dirty' : ''}`;
}

// Echo only the lines worth seeing live; everything goes to the log file.
const INTERESTING = /error:|warning: .*(sign|provision)|\*\* .* \*\*|Signing Identity|Provisioning Profile/i;

async function xcodebuild(args: string[], logFile: string, log: (line: string) => void): Promise<void> {
  const out = createWriteStream(logFile, { flags: 'a' });
  out.write(`$ xcodebuild ${args.join(' ')}\n`);
  const tail: string[] = [];
  const code = await runStreaming('xcodebuild', args, (line) => {
    out.write(`${line}\n`);
    tail.push(line);
    if (tail.length > 30) tail.shift();
    if (INTERESTING.test(line)) log(`  ${line.trim()}`);
  });
  await new Promise((resolve) => out.end(resolve));
  if (code !== 0) {
    const errors = tail.filter((l) => /error/i.test(l));
    // error: lines were already echoed live; otherwise show the tail for context.
    const context = errors.length ? '' : `\n${tail.slice(-10).join('\n')}`;
    throw new Error(`xcodebuild ${args.includes('archive') ? 'archive' : 'export'} failed (exit ${code}). Full log: ${logFile}${context}`);
  }
}

/** Archives, exports and ingests a configured Xcode project. */
export async function publishProject(config: Config, name: string, opts: PublishOptions = {}): Promise<IngestResult> {
  const project = config.projects[name];
  if (!project) {
    const known = Object.keys(config.projects).join(', ') || '(none)';
    throw new Error(`unknown project "${name}" — configured projects: ${known}. Add it to ${config.configPath}`);
  }
  const projectPath = project.workspace ?? project.project ?? '';
  if (!existsSync(projectPath)) throw new Error(`${projectPath} does not exist`);
  const log = opts.log ?? ((line: string) => console.log(line));
  const method = opts.method ?? config.exportMethod;
  const buildNumber = opts.buildNumber ?? makeBuildNumber();

  const work = path.join(config.dataDir, 'work', `${name}-${buildNumber}`);
  const logDir = path.join(config.dataDir, 'logs');
  await mkdir(work, { recursive: true });
  await mkdir(logDir, { recursive: true });
  const logFile = path.join(logDir, `publish-${name}-${buildNumber}.log`);
  const archivePath = path.join(work, `${name}.xcarchive`);
  const exportPath = path.join(work, 'export');
  const optionsPlist = path.join(work, 'ExportOptions.plist');

  log(`Archiving ${name} (build ${buildNumber}, ${opts.unsigned ? 'unsigned' : method})…`);
  await xcodebuild(archiveArgs(config, project, archivePath, buildNumber, opts.unsigned), logFile, log);

  let ipa: string;
  if (opts.unsigned) {
    log('Packaging unsigned IPA…');
    ipa = await packageUnsigned(archivePath, exportPath, name);
  } else {
    log('Exporting IPA…');
    await writeFile(optionsPlist, exportOptions(method, config.teamId));
    await xcodebuild(exportArgs(config, archivePath, optionsPlist, exportPath), logFile, log);
    const ipaName = (await readdir(exportPath)).find((f) => f.endsWith('.ipa'));
    if (!ipaName) throw new Error(`export produced no .ipa in ${exportPath}`);
    ipa = path.join(exportPath, ipaName);
  }

  log('Adding to catalog…');
  const projectDir = path.dirname(projectPath);
  const result = await ingestIpa(config, ipa, {
    notes: opts.notes,
    gitCommit: await gitCommit(projectDir),
    iconSource: await findAppIconSource(projectDir),
  });
  // Keep the work dir on failure for debugging; it is only removed after a successful ingest.
  await rm(work, { recursive: true, force: true });
  return result;
}
