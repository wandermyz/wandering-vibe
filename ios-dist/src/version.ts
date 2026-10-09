/** Compares dotted numeric versions ("1.2.10" > "1.2.9"). Returns <0, 0 or >0. */
export function compareVersions(a: string, b: string): number {
  const pa = a.split('.').map((n) => Number.parseInt(n, 10) || 0);
  const pb = b.split('.').map((n) => Number.parseInt(n, 10) || 0);
  for (let i = 0; i < Math.max(pa.length, pb.length); i++) {
    const diff = (pa[i] ?? 0) - (pb[i] ?? 0);
    if (diff !== 0) return Math.sign(diff);
  }
  return 0;
}

const pad = (n: number) => String(n).padStart(2, '0');

/**
 * A monotonically increasing CFBundleVersion derived from local time: "YYYYMMDD.HHmmss".
 * iOS only updates an installed app in place when CFBundleVersion goes up.
 */
export function makeBuildNumber(d: Date = new Date()): string {
  const date = `${d.getFullYear()}${pad(d.getMonth() + 1)}${pad(d.getDate())}`;
  const time = `${pad(d.getHours())}${pad(d.getMinutes())}${pad(d.getSeconds())}`;
  return `${date}.${time}`;
}
