import { existsSync, readFileSync } from 'node:fs';
import os from 'node:os';
import path from 'node:path';

export interface ProjectConfig {
  /** Absolute path to an .xcodeproj (exactly one of project/workspace is set). */
  project?: string;
  /** Absolute path to an .xcworkspace. */
  workspace?: string;
  scheme: string;
  configuration: string;
}

/** App Store Connect API key, used by xcodebuild for unattended signing. */
export interface AscApiKey {
  keyPath: string;
  keyId: string;
  issuerId: string;
}

export interface Config {
  configPath: string;
  /** Where IPAs, icons, logs and build work dirs live. Never inside the repo. */
  dataDir: string;
  host: string;
  port: number;
  /** Absolute base URL used in manifests; derived from request headers when unset. */
  publicBaseUrl?: string;
  siteTitle: string;
  keepBuilds: number;
  /** Tailscale logins allowed to use the site; empty = anyone on the tailnet. */
  allowedLogins: string[];
  teamId?: string;
  exportMethod: string;
  ascApiKey?: AscApiKey;
  launchdLabel: string;
  tailscaleHttpsPort: number;
  projects: Record<string, ProjectConfig>;
}

export class ConfigError extends Error {}

export const DEFAULT_HOME = path.join(os.homedir(), '.ios-dist');

export function expandHome(p: string): string {
  if (p === '~') return os.homedir();
  if (p.startsWith('~/')) return path.join(os.homedir(), p.slice(2));
  return p;
}

export function resolveConfigPath(env: NodeJS.ProcessEnv = process.env): string {
  const override = env.IOS_DIST_CONFIG;
  return override ? path.resolve(expandHome(override)) : path.join(DEFAULT_HOME, 'config.json');
}

type Raw = Record<string, unknown>;

function isObject(v: unknown): v is Raw {
  return typeof v === 'object' && v !== null && !Array.isArray(v);
}

function optString(raw: Raw, key: string, where: string): string | undefined {
  const v = raw[key];
  if (v === undefined || v === null || v === '') return undefined;
  if (typeof v !== 'string') throw new ConfigError(`${where}.${key} must be a string`);
  return v;
}

function reqString(raw: Raw, key: string, where: string): string {
  const v = optString(raw, key, where);
  if (v === undefined) throw new ConfigError(`${where}.${key} is required`);
  return v;
}

function optInt(raw: Raw, key: string, where: string, min: number, max: number): number | undefined {
  const v = raw[key];
  if (v === undefined || v === null) return undefined;
  if (typeof v !== 'number' || !Number.isInteger(v) || v < min || v > max) {
    throw new ConfigError(`${where}.${key} must be an integer between ${min} and ${max}`);
  }
  return v;
}

export function parseConfig(raw: unknown, configPath: string): Config {
  if (!isObject(raw)) throw new ConfigError('config must be a JSON object');
  const where = 'config';
  const baseDir = path.dirname(configPath);
  const resolvePath = (p: string) => path.resolve(baseDir, expandHome(p));

  const allowedLogins = raw.allowedLogins ?? [];
  if (!Array.isArray(allowedLogins) || !allowedLogins.every((x) => typeof x === 'string')) {
    throw new ConfigError(`${where}.allowedLogins must be an array of strings`);
  }

  const teamId = optString(raw, 'teamId', where);
  if (teamId && !/^[A-Z0-9]{10}$/.test(teamId)) {
    throw new ConfigError(`${where}.teamId must be a 10-character Apple team ID`);
  }

  const publicBaseUrl = optString(raw, 'publicBaseUrl', where)?.replace(/\/+$/, '');
  if (publicBaseUrl && !/^https?:\/\/[^/]+/.test(publicBaseUrl)) {
    throw new ConfigError(`${where}.publicBaseUrl must be an http(s) URL`);
  }

  let ascApiKey: AscApiKey | undefined;
  if (raw.ascApiKey !== undefined) {
    if (!isObject(raw.ascApiKey)) throw new ConfigError(`${where}.ascApiKey must be an object`);
    const w = `${where}.ascApiKey`;
    ascApiKey = {
      keyPath: resolvePath(reqString(raw.ascApiKey, 'keyPath', w)),
      keyId: reqString(raw.ascApiKey, 'keyId', w),
      issuerId: reqString(raw.ascApiKey, 'issuerId', w),
    };
  }

  const projectsRaw = raw.projects ?? {};
  if (!isObject(projectsRaw)) throw new ConfigError(`${where}.projects must be an object`);
  const projects: Record<string, ProjectConfig> = {};
  for (const [name, p] of Object.entries(projectsRaw)) {
    const w = `${where}.projects.${name}`;
    if (!isObject(p)) throw new ConfigError(`${w} must be an object`);
    const project = optString(p, 'project', w);
    const workspace = optString(p, 'workspace', w);
    if (!project === !workspace) throw new ConfigError(`${w} needs exactly one of "project" or "workspace"`);
    projects[name] = {
      project: project && resolvePath(project),
      workspace: workspace && resolvePath(workspace),
      scheme: reqString(p, 'scheme', w),
      configuration: optString(p, 'configuration', w) ?? 'Release',
    };
  }

  return {
    configPath,
    dataDir: resolvePath(optString(raw, 'dataDir', where) ?? '.'),
    host: optString(raw, 'host', where) ?? '127.0.0.1',
    port: optInt(raw, 'port', where, 0, 65535) ?? 8740,
    publicBaseUrl,
    siteTitle: optString(raw, 'siteTitle', where) ?? 'My Apps',
    keepBuilds: optInt(raw, 'keepBuilds', where, 1, 1000) ?? 5,
    allowedLogins,
    teamId,
    exportMethod: optString(raw, 'exportMethod', where) ?? 'release-testing',
    ascApiKey,
    launchdLabel: optString(raw, 'launchdLabel', where) ?? 'local.ios-dist',
    tailscaleHttpsPort: optInt(raw, 'tailscaleHttpsPort', where, 1, 65535) ?? 443,
    projects,
  };
}

/** Loads the config file; a missing file yields defaults (data dir = the config's directory). */
export function loadConfig(configPath: string = resolveConfigPath()): Config {
  if (!existsSync(configPath)) return parseConfig({}, configPath);
  let raw: unknown;
  try {
    raw = JSON.parse(readFileSync(configPath, 'utf8'));
  } catch (err) {
    throw new ConfigError(`${configPath}: ${(err as Error).message}`);
  }
  return parseConfig(raw, configPath);
}
