import { expect, test } from './story-fixture';
import { readFileSync } from 'node:fs';

const nightLocation = JSON.parse(readFileSync('../data/locations.json', 'utf8')).night
  .find((location: { id: string }) => location.id === 'n_litcorridor');

test('night palette covers map, location and modal without dimming art', async ({ page }) => {
  await page.route(/\/src\/core\/state\.ts(\?.*)?$/, async route => {
    const response = await route.fetch();
    const body = (await response.text()).replace('export function createGame(', 'function originalCreateGame(') + `
      export function createGame(data) {
        const base = originalCreateGame(data).serialize();
        base.flow.mode = 'run'; base.run.day = 17; base.run.phase = 'night';
        base.run.hand = ['protagonist'];
        return originalCreateGame(data, base);
      }`;
    await route.fulfill({ response, body });
  });
  await page.goto('/');
  await expect(page.locator('html')).toHaveAttribute('data-theme', 'night');
  await expect(page.locator('.app-shell')).toHaveCSS('background-color', 'rgb(29, 30, 33)');
  await expect(page.locator('.phase-actions button')).toHaveCSS('background-color', 'rgb(44, 44, 45)');
  await expect(page.locator('.map-art')).toHaveCSS('filter', 'none');
  await page.getByTestId('card-protagonist').click();
  const dialog = page.getByRole('dialog');
  await expect(dialog).toHaveCSS('background-color', 'rgb(29, 30, 33)');
  await expect(dialog).toHaveCSS('color', 'rgb(228, 221, 208)');
  await page.screenshot({ path: '../_qa/web/night-theme-dialog.png', fullPage: true });
  await page.keyboard.press('Escape');
  await page.getByRole('button', { name: `${nightLocation.name} [尚未到訪]`, exact: true }).click();
  await expect(page.getByTestId('night-enter')).toBeVisible();
  await expect(page.getByTestId('night-desc')).toHaveCSS('color', 'rgb(228, 221, 208)');
  await page.setViewportSize({ width: 390, height: 844 });
  await page.screenshot({ path: '../_qa/web/night-theme-location-mobile.png', fullPage: true });
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true);
});
