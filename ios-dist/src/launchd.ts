import { existsSync } from 'node:fs';
import { mkdir, readFile, rm, writeFile } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import type { Config } from './config.js';
import { tryRun } from './exec.js';
import { toPlist } from './plist.js';

export interface LaunchAgentSpec {
  label: string;
  nodePath: string;
  cliPath: string;
  configPath: string;
  workingDir: string;
  logFile: string;
  pathEnv: string;
}

export function renderLaunchAgent(spec: LaunchAgentSpec): string {
  return toPlist({
    Label: spec.label,
    ProgramArguments: [spec.nodePath, spec.cliPath, 'serve'],
    WorkingDirectory: spec.workingDir,
    EnvironmentVariables: { IOS_DIST_CONFIG: spec.configPath, PATH: spec.pathEnv },
    RunAtLoad: true,
    KeepAlive: true,
    ThrottleInterval: 10,
    StandardOutPath: spec.logFile,
    StandardErrorPath: spec.logFile,
  });
}

export const launchAgentPath = (label: string) => path.join(os.homedir(), 'Library', 'LaunchAgents', `${label}.plist`);

/** First executable `name` on PATH, keeping symlinks (/opt/homebrew/bin/node survives brew upgrades). */
export function whichSync(name: string, pathEnv = process.env.PATH ?? ''): string | undefined {
  for (const dir of pathEnv.split(':').filter(Boolean)) {
    const candidate = path.join(dir, name);
    if (existsSync(candidate)) return candidate;
  }
  return undefined;
}

export function defaultSpec(config: Config): LaunchAgentSpec {
  const packageRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
  const nodePath = whichSync('node') ?? process.execPath;
  return {
    label: config.launchdLabel,
    nodePath,
    cliPath: path.join(packageRoot, 'dist', 'cli.js'),
    configPath: config.configPath,
    workingDir: packageRoot,
    logFile: path.join(config.dataDir, 'logs', 'server.log'),
    pathEnv: [path.dirname(nodePath), '/usr/bin', '/bin', '/usr/sbin', '/sbin'].join(':'),
  };
}

export interface DaemonStatus {
  installed: boolean;
  loaded: boolean;
  state?: string;
  pid?: number;
  lastExitCode?: string;
  healthy: boolean;
}

/** Manages the server as a per-user LaunchAgent in the gui/<uid> domain. */
export class Daemon {
  readonly spec: LaunchAgentSpec;
  readonly plistPath: string;
  private readonly domain: string;
  private readonly target: string;

  constructor(
    private readonly config: Config,
    spec?: LaunchAgentSpec,
  ) {
    this.spec = spec ?? defaultSpec(config);
    this.plistPath = launchAgentPath(this.spec.label);
    this.domain = `gui/${os.userInfo().uid}`;
    this.target = `${this.domain}/${this.spec.label}`;
  }

  private async launchctl(...args: string[]) {
    return tryRun('launchctl', args);
  }

  async isLoaded(): Promise<boolean> {
    return (await this.launchctl('print', this.target)).code === 0;
  }

  async install(): Promise<void> {
    if (!existsSync(this.spec.cliPath)) throw new Error(`${this.spec.cliPath} not found — run "npm run build" first`);
    await mkdir(path.dirname(this.spec.logFile), { recursive: true });
    await mkdir(path.dirname(this.plistPath), { recursive: true });
    if (await this.isLoaded()) await this.launchctl('bootout', this.target);
    await writeFile(this.plistPath, renderLaunchAgent(this.spec));
    await this.bootstrap();
  }

  async uninstall(): Promise<void> {
    if (await this.isLoaded()) await this.launchctl('bootout', this.target);
    await rm(this.plistPath, { force: true });
  }

  private async bootstrap(): Promise<void> {
    const r = await this.launchctl('bootstrap', this.domain, this.plistPath);
    if (r.code !== 0) throw new Error(`launchctl bootstrap failed: ${r.stderr.trim() || r.stdout.trim()}`);
  }

  async start(): Promise<void> {
    if (!existsSync(this.plistPath)) throw new Error(`not installed — run "ios-dist daemon install" first`);
    if (await this.isLoaded()) {
      await this.launchctl('kickstart', this.target);
    } else {
      await this.bootstrap();
    }
  }

  /** Unloads the agent (KeepAlive would immediately restart a merely killed process). */
  async stop(): Promise<void> {
    if (await this.isLoaded()) {
      const r = await this.launchctl('bootout', this.target);
      if (r.code !== 0) throw new Error(`launchctl bootout failed: ${r.stderr.trim()}`);
    }
  }

  async restart(): Promise<void> {
    if (!(await this.isLoaded())) return this.start();
    const r = await this.launchctl('kickstart', '-k', this.target);
    if (r.code !== 0) throw new Error(`launchctl kickstart failed: ${r.stderr.trim()}`);
  }

  async status(): Promise<DaemonStatus> {
    const printed = await this.launchctl('print', this.target);
    const field = (name: string) => new RegExp(`^\\s*${name} = (.+)$`, 'm').exec(printed.stdout)?.[1]?.trim();
    let healthy = false;
    try {
      const res = await fetch(`http://${this.config.host}:${this.config.port}/healthz`, { signal: AbortSignal.timeout(2000) });
      healthy = res.ok;
    } catch {
      // Not listening.
    }
    const pid = field('pid');
    return {
      installed: existsSync(this.plistPath),
      loaded: printed.code === 0,
      state: field('state'),
      pid: pid ? Number(pid) : undefined,
      lastExitCode: field('last exit code'),
      healthy,
    };
  }

  async readLog(lines = 50): Promise<string> {
    try {
      return (await readFile(this.spec.logFile, 'utf8')).split('\n').slice(-lines - 1).join('\n');
    } catch {
      return '';
    }
  }
}
