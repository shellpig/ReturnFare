import { test, expect } from '@playwright/test';
import { readFileSync } from 'node:fs';
const opening = JSON.parse(readFileSync('../data/opening_choices.json', 'utf8'));
const beats = JSON.parse(readFileSync('../data/beats/ch1_d01_d03.json', 'utf8')).beats;
const nights = JSON.parse(readFileSync('../data/beats/ch1_nights.json', 'utf8')).beats;
const beat = (id: string) => beats.find((b: { id: string }) => b.id === id);

test('phone path displays each original passage through the first night', async ({ page }) => {
  await page.goto('/');
  await page.getByRole('button', { name: opening.opening_choices[1].label }).click();
  await page.getByRole('dialog').getByRole('button', { name: '確認', exact: true }).click();
  const passage = page.locator('.passage');
  const next = page.getByRole('button', { name: '繼續演出' });
  const advance = page.getByRole('button', { name: '推進時段' });
  async function read(text: string) {
    await expect(passage).toHaveText(text);
    await expect(advance).toHaveCount(0);
    await next.click();
  }
  async function phase() { await expect(advance).toBeEnabled(); await advance.click(); }
  await read(beat('d1_morning_phone').text);
  await read(beat('d1_morning_departure').text);
  await expect(passage).toHaveText(beat('d1_morning_departure').text);
  await expect(page.getByRole('button')).toHaveCount(1);
  await phase();
  await read(beat('d1_pm_mountain_road').text);
  await expect(page.getByRole('button')).toHaveCount(1);
  await phase();
  await expect(passage).toHaveText(beat('d1_arrival').text);
  await page.screenshot({ path: '../_qa/web/W3-A/evening.png', fullPage: true });
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true);
  expect(await page.evaluate(async () => {
    await document.fonts.ready;
    return document.fonts.check('16px WenKai') && document.fonts.check('16px TaipeiSans') &&
      [...document.fonts].filter(font => font.status === 'loaded').length >= 2;
  })).toBe(true);
  await read(beat('d1_arrival').text);
  await read(beat('d1_arrival').on_enter.text);
  await read(beat('d1_ambient_couple').text);
  await phase();
  await read(nights.find((b: { id: string }) => b.id === 'n_corridor_ch1').text);
  await phase();
  await expect(page.locator('header')).toContainText('第 2 天');
  await expect(advance).toBeDisabled();
  await expect(page.getByRole('button')).toHaveCount(1);
});
