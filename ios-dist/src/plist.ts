export type PlistValue =
  | string
  | number
  | boolean
  | Date
  | PlistValue[]
  | { [key: string]: PlistValue | undefined };

export function xmlEscape(s: string): string {
  return s
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&apos;');
}

function render(value: PlistValue, indent: string): string {
  if (typeof value === 'string') return `${indent}<string>${xmlEscape(value)}</string>`;
  if (typeof value === 'boolean') return `${indent}<${value}/>`;
  if (typeof value === 'number') {
    return Number.isInteger(value) ? `${indent}<integer>${value}</integer>` : `${indent}<real>${value}</real>`;
  }
  if (value instanceof Date) {
    return `${indent}<date>${value.toISOString().replace(/\.\d{3}Z$/, 'Z')}</date>`;
  }
  const inner = `${indent}\t`;
  if (Array.isArray(value)) {
    if (value.length === 0) return `${indent}<array/>`;
    return [`${indent}<array>`, ...value.map((v) => render(v, inner)), `${indent}</array>`].join('\n');
  }
  const entries = Object.entries(value).filter((e): e is [string, PlistValue] => e[1] !== undefined);
  if (entries.length === 0) return `${indent}<dict/>`;
  return [
    `${indent}<dict>`,
    ...entries.flatMap(([k, v]) => [`${inner}<key>${xmlEscape(k)}</key>`, render(v, inner)]),
    `${indent}</dict>`,
  ].join('\n');
}

/** Serializes a value as an XML property list document. */
export function toPlist(value: PlistValue): string {
  return [
    '<?xml version="1.0" encoding="UTF-8"?>',
    '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">',
    '<plist version="1.0">',
    render(value, ''),
    '</plist>',
    '',
  ].join('\n');
}
