#!/usr/bin/env node
import { existsSync } from 'node:fs';
import { chmod, copyFile, mkdir } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { parseArgs } from 'node:util';
import { loadCatalog } from './catalog.js';
import { loadConfig, resolveConfigPath, type Config } from './config.js';
import { ingestIpa, type IngestResult } from './ingest.js';
import { Daemon } from './launchd.js';
import { publishProject } from './publish.js';
import { startServer } from './server.js';
import { disableServe, enableServe, serveStatus, tailnetUrl } from './tailscale.js';

const USAGE = `ios-dist — self-hosted iOS app distribution

Usage:
  ios-dist init                         Create the config file from config.example.json
  ios-dist config                       Show the resolved config
  ios-dist serve                        Run the web server in the foreground
  ios-dist publish <project> [--notes <text>] [--method <export-method>] [--unsigned]
                                        Archive + export + add a configured Xcode project
                                        (--unsigned: skip signing to test the pipeline; won't install)
  ios-dist ingest <file.ipa> [--notes <text>] [--icon <png>] [--force]
                                        Add an already-built IPA to the catalog
  ios-dist list                         List published apps and builds
  ios-dist daemon <install|uninstall|start|stop|restart|status|logs> [-f]
                                        Manage the LaunchAgent that runs the server
  ios-dist tailscale <enable|disable|status>
                                        Expose the server on the tailnet over HTTPS

Config: $IOS_DIST_CONFIG or ~/.ios-dist/config.json`;

const packageRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');

function printIngest({ meta, pruned }: IngestResult): void {
  console.log(`Published ${meta.name} ${meta.version} (${meta.build}) [${meta.bundleId}]`);
  if (meta.profile) {
    console.log(`  signing: ${meta.profile.method}, profile "${meta.profile.name}", expires ${meta.profile.expiresAt ?? '?'}`);
  } else {
    console.log('  warning: no embedded.mobileprovision — this IPA will not install on a device');
  }
  if (pruned.length) console.log(`  pruned old builds: ${pruned.join(', ')}`);
}

async function daemonCommand(config: Config, action: string | undefined, follow: boolean): Promise<void> {
  const daemon = new Daemon(config);
  switch (action) {
    case 'install':
      await daemon.install();
      console.log(`Installed ${daemon.plistPath}\nServer: http://${config.host}:${config.port} (logs: ${daemon.spec.logFile})`);
      return;
    case 'uninstall':
      await daemon.uninstall();
      console.log(`Removed ${daemon.plistPath}`);
      return;
    case 'start':
      await daemon.start();
      console.log('Started');
      return;
    case 'stop':
      await daemon.stop();
      console.log('Stopped (run "daemon start" to bring it back; it will also start at next login)');
      return;
    case 'restart':
      await daemon.restart();
      console.log('Restarted');
      return;
    case 'status': {
      const s = await daemon.status();
      console.log(
        [
          `label:     ${daemon.spec.label}`,
          `plist:     ${s.installed ? daemon.plistPath : 'not installed'}`,
          `loaded:    ${s.loaded}${s.state ? ` (${s.state}${s.pid ? `, pid ${s.pid}` : ''})` : ''}`,
          s.lastExitCode ? `last exit: ${s.lastExitCode}` : undefined,
          `health:    ${s.healthy ? 'ok' : 'not responding'} on http://${config.host}:${config.port}/healthz`,
        ]
          .filter(Boolean)
          .join('\n'),
      );
      return;
    }
    case 'logs': {
      if (follow) {
        const { spawn } = await import('node:child_process');
        spawn('tail', ['-n', '50', '-f', daemon.spec.logFile], { stdio: 'inherit' });
        return;
      }
      console.log((await daemon.readLog()) || `(no log yet at ${daemon.spec.logFile})`);
      return;
    }
    default:
      throw new Error('usage: ios-dist daemon <install|uninstall|start|stop|restart|status|logs> [-f]');
  }
}

async function main(argv: string[]): Promise<void> {
  const { values, positionals } = parseArgs({
    args: argv,
    allowPositionals: true,
    options: {
      notes: { type: 'string' },
      method: { type: 'string' },
      icon: { type: 'string' },
      force: { type: 'boolean' },
      unsigned: { type: 'boolean' },
      follow: { type: 'boolean', short: 'f' },
      help: { type: 'boolean', short: 'h' },
    },
  });
  const [command, arg] = positionals;
  if (!command || values.help || command === 'help') {
    console.log(USAGE);
    return;
  }

  if (command === 'init') {
    const target = resolveConfigPath();
    if (existsSync(target)) {
      console.log(`${target} already exists`);
      return;
    }
    await mkdir(path.dirname(target), { recursive: true });
    await copyFile(path.join(packageRoot, 'config.example.json'), target);
    await chmod(target, 0o600);
    console.log(`Created ${target} — edit teamId and projects before publishing.`);
    return;
  }

  const config = loadConfig();
  switch (command) {
    case 'config':
      console.log(JSON.stringify({ ...config, exists: existsSync(config.configPath) }, null, 2));
      return;
    case 'serve': {
      const server = await startServer(config);
      console.log(`ios-dist listening on http://${config.host}:${config.port} (data: ${config.dataDir})`);
      const shutdown = () => server.close(() => process.exit(0));
      process.on('SIGTERM', shutdown);
      process.on('SIGINT', shutdown);
      return;
    }
    case 'publish':
      if (!arg) throw new Error('usage: ios-dist publish <project>');
      printIngest(await publishProject(config, arg, {
          notes: values.notes,
          method: values.method,
          unsigned: values.unsigned,
        }));
      return;
    case 'ingest':
      if (!arg) throw new Error('usage: ios-dist ingest <file.ipa>');
      printIngest(await ingestIpa(config, path.resolve(arg), { notes: values.notes, iconSource: values.icon, force: values.force }));
      return;
    case 'list': {
      const apps = await loadCatalog(config.dataDir);
      if (!apps.length) console.log(`No apps in ${config.dataDir}`);
      for (const app of apps) {
        console.log(`${app.name} [${app.bundleId}]`);
        for (const b of app.builds) {
          console.log(`  ${b.version} (${b.build})  ${b.publishedAt}  ${b.profile?.method ?? 'unsigned'}${b.notes ? `  ${b.notes}` : ''}`);
        }
      }
      return;
    }
    case 'daemon':
      return daemonCommand(config, arg, values.follow ?? false);
    case 'tailscale':
      if (arg === 'enable') {
        await enableServe(config);
        console.log(`Serving on ${(await tailnetUrl(config)) ?? 'the tailnet'}`);
      } else if (arg === 'disable') {
        await disableServe(config);
        console.log('Tailscale serve disabled');
      } else if (arg === 'status') {
        console.log(await serveStatus());
      } else {
        throw new Error('usage: ios-dist tailscale <enable|disable|status>');
      }
      return;
    default:
      throw new Error(`unknown command "${command}"\n\n${USAGE}`);
  }
}

main(process.argv.slice(2)).catch((err: unknown) => {
  console.error(`error: ${err instanceof Error ? err.message : String(err)}`);
  process.exit(1);
});

