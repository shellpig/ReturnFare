import { test, expect } from './story-fixture';
import { readFileSync } from 'node:fs';
const opening = JSON.parse(readFileSync('../data/opening_choices.json', 'utf8'));

test('opening preview, cancel, lock reason and confirmation', async ({ page }) => {
  await page.goto('/');
  const album = opening.opening_choices[0];
  const locked = opening.opening_choices[2];
  await expect(page.getByRole('heading', { name: opening.screen.title })).toBeVisible();
  await expect(page.getByRole('button', { name: locked.label })).toBeDisabled();
  await expect(page.getByText(locked.reject_reason)).toBeVisible();
  await page.getByRole('button', { name: album.label }).click();
  const dialog = page.getByRole('dialog');
  await expect(dialog.getByText(album.preview)).toBeVisible();
  await expect(dialog.getByText(album.confirm_text)).toBeVisible();
  await dialog.getByRole('button', { name: '取消' }).click();
  await expect(page.getByRole('heading', { name: opening.screen.title })).toBeVisible();
  await page.getByRole('button', { name: album.label }).click();
  await dialog.getByRole('button', { name: '確認', exact: true }).click();
  const beats = JSON.parse(readFileSync('../data/beats/ch1_d01_d03.json', 'utf8')).beats;
  await expect(page.locator('.passage')).toHaveText(beats.find((b: { id: string }) => b.id === 'd1_morning_departure').text);
});

test('data failure does not start game', async ({ page }) => {
  await page.route('**/data-manifest.json', route => route.fulfill({ status: 500, body: 'failure' }));
  await page.goto('/');
  await expect(page.getByRole('alert')).toContainText('資料載入失敗');
  await expect(page.getByRole('button')).toHaveCount(0);
});
