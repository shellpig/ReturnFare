import { test, expect } from './story-fixture';
import { readFileSync } from 'node:fs';
const opening = JSON.parse(readFileSync('../data/opening_choices.json', 'utf8'));
const beats = JSON.parse(readFileSync('../data/beats/ch1_d01_d03.json', 'utf8')).beats;
const nights = JSON.parse(readFileSync('../data/beats/ch1_nights.json', 'utf8')).beats;
const beat = (id: string) => beats.find((b: { id: string }) => b.id === id);

test('phone path displays each original passage through the first night', async ({ page }) => {
  await page.goto('/');
  await expect(page.locator('html')).toHaveAttribute('data-theme', 'day');
  const music = page.locator('audio');
  await expect(music).toHaveAttribute('src', '/audio/bgm/bgm_01_opening.mp3');
  await page.getByRole('button', { name: opening.opening_choices[1].label }).click();
  await page.getByRole('dialog').getByRole('button', { name: '確認', exact: true }).click();
  await expect(music).toHaveAttribute('src', '/audio/bgm/bgm_02_day_ch1_b.mp3');
  await expect(music).toHaveJSProperty('paused', false);
  await music.evaluate(el => { (el as HTMLAudioElement).currentTime = 10; });
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
  await expect(passage).toHaveText(beat('d1_morning_departure').text);
  await expect(next).toHaveCount(0);
  await expect(page.locator('button:not(.hand-panel button):not(.save-panel button)')).toHaveCount(1);
  await phase();
  await expect(passage).toHaveText(beat('d1_pm_mountain_road').text);
  await expect(next).toHaveCount(0);
  // 同曲跨時段不重新起播。
  expect(await music.evaluate(el => (el as HTMLAudioElement).currentTime)).toBeGreaterThanOrEqual(10);
  await expect(page.locator('button:not(.hand-panel button):not(.save-panel button)')).toHaveCount(1);
  await phase();
  await expect(passage).toHaveText(beat('d1_arrival').text);
  await expect(page.locator('html')).toHaveAttribute('data-theme', 'day');
  await page.screenshot({ path: '../_qa/web/W3-A/evening.png', fullPage: true });
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true);
  expect(await page.evaluate(async () => {
    await document.fonts.ready;
    return document.fonts.check('16px WenKai') && document.fonts.check('16px TaipeiSans') &&
      [...document.fonts].filter(font => font.status === 'loaded').length >= 2;
  })).toBe(true);
  await read(beat('d1_arrival').text);
  await read(beat('d1_arrival').on_enter.text);
  await expect(passage).toHaveText(beat('d1_ambient_couple').text);
  await expect(next).toHaveCount(0);
  await phase();
  await expect(passage).toHaveText(nights.find((b: { id: string }) => b.id === 'n_corridor_ch1').text);
  await expect(next).toHaveCount(0);
  await expect(music).toHaveAttribute('src', '/audio/bgm/bgm_05_night_a.mp3');
  await expect(music).toHaveJSProperty('paused', false);
  // W6-A：D1 night 已被 fixed 強制到訪，夜間主按鈕改為「結束今晚」（scenes/main.gd），不再是通用的「推進時段」
  await expect(page.locator('html')).toHaveAttribute('data-theme', 'night');
  await expect(page.locator('.app-shell')).toHaveCSS('background-color', 'rgb(29, 30, 33)');
  await expect(passage).toHaveCSS('color', 'rgb(228, 221, 208)');
  await page.setViewportSize({ width: 390, height: 844 });
  await page.screenshot({ path: '../_qa/web/night-theme-mobile.png', fullPage: true });
  await expect(advance).toHaveCount(0);
  await page.getByRole('button', { name: '結束今晚' }).click();
  await expect(page.locator('header')).toContainText('第 2 天');
  await expect(page.locator('html')).toHaveAttribute('data-theme', 'day');
  await expect(page.locator('.app-shell')).toHaveCSS('background-color', 'rgb(249, 245, 235)');
  await expect(music).toHaveAttribute('src', '/audio/bgm/bgm_02_day_ch1_a.mp3');
  await expect(music).toHaveJSProperty('paused', false);
  const phaseAdvance = page.locator('.phase-actions button');
  await expect(phaseAdvance).toBeEnabled();
  await expect(phaseAdvance).toHaveText('推進時段（還有演出沒看）');
  await expect(page.locator('.map-panel')).toBeVisible();
  await expect(page.getByRole('button', { name: '山泉閣' })).toBeEnabled();
});
