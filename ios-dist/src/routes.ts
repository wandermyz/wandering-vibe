/** URL paths served by the web server. Bundle IDs and builds are validated, so they are URL-safe. */
export const routes = {
  home: '/',
  app: (bundleId: string) => `/apps/${bundleId}`,
  icon: (bundleId: string) => `/apps/${bundleId}/icon.png`,
  manifest: (bundleId: string, build: string) => `/apps/${bundleId}/builds/${build}/manifest.plist`,
  ipa: (bundleId: string, build: string) => `/apps/${bundleId}/builds/${build}/app.ipa`,
  apiApps: '/api/apps',
  apiLatest: (bundleId: string) => `/api/apps/${bundleId}/latest`,
};
