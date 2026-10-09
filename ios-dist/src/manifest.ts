import { toPlist } from './plist.js';

export interface ManifestInput {
  ipaUrl: string;
  displayImageUrl?: string;
  fullSizeImageUrl?: string;
  bundleId: string;
  version: string;
  title: string;
}

/** Renders the OTA manifest that `itms-services://` downloads before fetching the IPA. */
export function renderManifest(input: ManifestInput): string {
  const assets = [{ kind: 'software-package', url: input.ipaUrl }];
  if (input.displayImageUrl) assets.push({ kind: 'display-image', url: input.displayImageUrl });
  if (input.fullSizeImageUrl) assets.push({ kind: 'full-size-image', url: input.fullSizeImageUrl });
  return toPlist({
    items: [
      {
        assets,
        metadata: {
          'bundle-identifier': input.bundleId,
          'bundle-version': input.version,
          kind: 'software',
          title: input.title,
        },
      },
    ],
  });
}

export function installLink(manifestUrl: string): string {
  return `itms-services://?action=download-manifest&url=${encodeURIComponent(manifestUrl)}`;
}
