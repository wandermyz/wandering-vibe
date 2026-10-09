import type { Config } from './config.js';
import { tryRun } from './exec.js';

/** `tailscale serve` terminates HTTPS with a real *.ts.net certificate and proxies to us, tailnet-only. */
export function serveArgs(config: Config, enable: boolean): string[] {
  const https = `--https=${config.tailscaleHttpsPort}`;
  return enable ? ['serve', '--bg', https, `http://127.0.0.1:${config.port}`] : ['serve', https, 'off'];
}

async function tailscale(args: string[]): Promise<string> {
  const r = await tryRun('tailscale', args);
  if (r.code !== 0) throw new Error(`tailscale ${args.join(' ')} failed: ${(r.stderr || r.stdout).trim()}`);
  return r.stdout.trim();
}

export const enableServe = (config: Config) => tailscale(serveArgs(config, true));
export const disableServe = (config: Config) => tailscale(serveArgs(config, false));
export const serveStatus = () => tailscale(['serve', 'status']);

/** "https://<host>.<tailnet>.ts.net[:port]" for this machine, if Tailscale is up. */
export async function tailnetUrl(config: Config): Promise<string | undefined> {
  const r = await tryRun('tailscale', ['status', '--self', '--json']);
  if (r.code !== 0) return undefined;
  const dns = (JSON.parse(r.stdout) as { Self?: { DNSName?: string } }).Self?.DNSName?.replace(/\.$/, '');
  if (!dns) return undefined;
  return `https://${dns}${config.tailscaleHttpsPort === 443 ? '' : `:${config.tailscaleHttpsPort}`}`;
}
