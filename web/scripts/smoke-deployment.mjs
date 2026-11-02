import { chromium, expect } from '@playwright/test';
import { createHash } from 'node:crypto';
import { mkdir, readFile, readdir, writeFile } from 'node:fs/promises';
import { resolve, relative } from 'node:path';
import { fileURLToPath } from 'node:url';

// Exercise the actual static build locally or at its deployed origin, without fixtures.
const repo = fileURLToPath(new URL('../../', import.meta.url));
const [origin, distArg, outputArg] = process.argv.slice(2);
if (!origin || !distArg || !outputArg) {
  throw new Error('Usage: node scripts/smoke-deployment.mjs <origin> <dist> <output-dir>');
}
const dist = resolve(distArg);
const output = resolve(outputArg);
await mkdir(output, { recursive: true });
const sha256 = bytes => createHash('sha256').update(bytes).digest('hex');
const report = { origin, dist, assets: [], browser: null };

async function filesIn(directory) {
  const entries = await readdir(directory, { withFileTypes: true });
  const nested = await Promise.all(entries.map(entry => {
    const path = resolve(directory, entry.name);
    return entry.isDirectory() ? filesIn(path) : [path];
  }));
  return nested.flat();
}

const files = await filesIn(dist);
for (const file of files) {
  const path = relative(dist, file).replaceAll('\\', '/');
  if (/(^|\/)(docs|tests|prototype|_qa|trace|\.git)(\/|$)|\.(gd|tscn|ts|tsx|map)$|save.*\.json$/i.test(path)) {
    throw new Error(`Unexpected deployment file: ${path}`);
  }
  const bytes = await readFile(file);
  if (path.endsWith('.js') && /__testGame|__origCreateGame|__qa|fixture-host/.test(bytes.toString())) {
    throw new Error(`Test injection in bundle: ${path}`);
  }
  const response = await fetch(new URL(path, origin));
  if (!response.ok) throw new Error(`${path}: HTTP ${response.status}`);
  const actual = Buffer.from(await response.arrayBuffer());
  if (sha256(actual) !== sha256(bytes)) throw new Error(`${path}: deployed bytes differ from build`);
  const contentType = response.headers.get('content-type') ?? '';
  if (!path.endsWith('.html') && contentType.includes('text/html')) {
    throw new Error(`${path}: received HTML instead of asset`);
  }
  if (path.endsWith('.json')) JSON.parse(actual.toString());
  if (path.endsWith('.woff2') && actual.subarray(0, 4).toString() !== 'wOF2') {
    throw new Error(`${path}: invalid WOFF2`);
  }
  report.assets.push({ path, bytes: bytes.length, sha256: sha256(bytes), contentType });
}
report.totalBytes = report.assets.reduce((sum, file) => sum + file.bytes, 0);
report.manifest = JSON.parse(await readFile(resolve(dist, 'data-manifest.json'), 'utf8'));

const opening = JSON.parse(await readFile(resolve(repo, 'data/opening_choices.json'), 'utf8'));
const errors = [];
const browser = await chromium.launch({ headless: true });
try {
  const context = await browser.newContext({ viewport: { width: 1280, height: 800 } });
  const page = await context.newPage();
  page.on('pageerror', error => errors.push(error.message));
  page.on('console', message => { if (message.type() === 'error') errors.push(message.text()); });
  await page.addLocatorHandler(page.locator('body:not(:has(dialog[open])) [data-typing="true"]').first(),
    async story => { await story.click(); });
  await page.goto(origin);
  await expect(page.getByRole('heading', { name: opening.screen.title })).toBeVisible();
  await page.getByRole('button', { name: opening.opening_choices[0].label }).click();
  await page.getByRole('dialog').getByRole('button', { name: '確認', exact: true }).click();
  const advance = page.getByRole('button', { name: '推進時段', exact: true });
  await advance.click(); // D1 afternoon
  await advance.click(); // D1 evening
  await page.getByRole('button', { name: '繼續演出', exact: true }).click();
  await page.getByRole('button', { name: '繼續演出', exact: true }).click();
  await advance.click(); // D1 night
  await page.getByRole('button', { name: '結束今晚', exact: true }).click();
  await expect(page.locator('header')).toContainText('第 2 天');
  await expect(page.locator('header')).toContainText('上午');
  await page.locator('.phase-actions button').click();
  await page.getByRole('button', { name: /山泉閣/ }).click();
  await page.getByRole('button', { name: '繼續演出', exact: true }).click();
  await page.getByTestId('slot-work').click();
  await page.getByTestId('candidate-protagonist').click();
  await expect(page.getByTestId('action-result')).toBeVisible();
  await page.getByRole('button', { name: '返回地圖', exact: true }).click();
  await page.getByTestId('manual-save-btn').click();
  await expect(page.getByTestId('save-status')).toHaveText('存檔成功');
  const saved = await page.evaluate(() => JSON.parse(localStorage.getItem('returnfare.save.manual')));
  expect(saved.state.run.day).toBe(2);
  expect(saved.state.run.phase).toBe('afternoon');
  expect(saved.state.run.slots_placed['d2_pm_work::work']).toBe(true);
  expect(saved.state.run.action_spent).toBe(true);
  await page.reload();
  await page.getByTestId('continue-auto-btn').click();
  await expect(page.locator('header')).toContainText('第 2 天');
  await expect(page.locator('header')).toContainText('下午');
  await page.getByTestId('manual-load-btn').click();
  await page.getByTestId('save-dialog-confirm-btn').click();
  await expect(page.getByTestId('save-status')).toHaveText('讀取成功');
  const restored = await page.evaluate(() => JSON.parse(localStorage.getItem('returnfare.save.auto')));
  expect(restored.state).toEqual(saved.state);
  await page.evaluate(() => document.fonts.ready);
  const fonts = await page.evaluate(() => [...document.fonts].map(font => ({ family: font.family, status: font.status })));
  expect(fonts.filter(font => font.status === 'loaded').length).toBeGreaterThanOrEqual(2);
  await page.screenshot({ path: resolve(output, 'playable-and-restored.png'), fullPage: true });
  report.browser = { path: 'opening -> D2 afternoon -> work placement -> save -> reload -> continue -> manual load', fonts, errors };
  expect(errors).toEqual([]);
  await context.close();
} finally {
  await browser.close();
  await writeFile(resolve(output, 'report.json'), JSON.stringify(report, null, 2));
}
console.log(JSON.stringify({ assets: report.assets.length, bytes: report.totalBytes, browser: report.browser }));
