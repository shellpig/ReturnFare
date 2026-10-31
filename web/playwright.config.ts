import { defineConfig } from '@playwright/test';
export default defineConfig({
  testDir: './tests/ui', outputDir: '../_qa/web/W3-A/results',
  use: { browserName: 'chromium', headless: true, baseURL: 'http://127.0.0.1:4178', viewport: { width: 1280, height: 800 } },
  webServer: { command: 'npm run dev -- --host 127.0.0.1 --port 4178 --strictPort', url: 'http://127.0.0.1:4178', reuseExistingServer: false, timeout: 120000 },
});
