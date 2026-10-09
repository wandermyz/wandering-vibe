import { execFile, spawn } from 'node:child_process';
import { promisify } from 'node:util';

const execFileAsync = promisify(execFile);
const MAX_BUFFER = 64 * 1024 * 1024;

export async function run(cmd: string, args: string[]): Promise<string> {
  const { stdout } = await execFileAsync(cmd, args, { maxBuffer: MAX_BUFFER, encoding: 'utf8' });
  return stdout;
}

export async function runBuffer(cmd: string, args: string[]): Promise<Buffer> {
  const { stdout } = await execFileAsync(cmd, args, { maxBuffer: MAX_BUFFER, encoding: 'buffer' });
  return stdout;
}

/** Runs a command and returns its exit code instead of throwing. */
export async function tryRun(cmd: string, args: string[]): Promise<{ code: number; stdout: string; stderr: string }> {
  try {
    const { stdout, stderr } = await execFileAsync(cmd, args, { maxBuffer: MAX_BUFFER, encoding: 'utf8' });
    return { code: 0, stdout, stderr };
  } catch (err) {
    const e = err as { code?: number | string; stdout?: string; stderr?: string; message: string };
    return { code: typeof e.code === 'number' ? e.code : 1, stdout: e.stdout ?? '', stderr: e.stderr ?? e.message };
  }
}

/** Runs a long command, handing each output line to `onLine`. Resolves with the exit code. */
export function runStreaming(cmd: string, args: string[], onLine: (line: string) => void): Promise<number> {
  return new Promise((resolve, reject) => {
    const child = spawn(cmd, args, { stdio: ['ignore', 'pipe', 'pipe'] });
    for (const stream of [child.stdout, child.stderr]) {
      let pending = '';
      stream.setEncoding('utf8');
      stream.on('data', (chunk: string) => {
        pending += chunk;
        const lines = pending.split('\n');
        pending = lines.pop() ?? '';
        lines.forEach(onLine);
      });
      stream.on('end', () => pending && onLine(pending));
    }
    child.on('error', reject);
    child.on('close', (code) => resolve(code ?? 1));
  });
}
