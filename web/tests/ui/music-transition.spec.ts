import { test, expect, finishStory, type Page } from './story-fixture';
import { readFileSync } from 'node:fs';

const opening = JSON.parse(readFileSync('../data/opening_choices.json', 'utf8'));

async function reachEveningEnd(page: Page) {
  await page.goto('/');
  await page.getByRole('button', { name: opening.opening_choices[1].label }).click();
  await page.getByRole('dialog').getByRole('button', { name: '確認', exact: true }).click();
  await page.getByRole('button', { name: '繼續演出' }).click();
  await page.getByRole('button', { name: '推進時段', exact: true }).click();
  await page.getByRole('button', { name: '推進時段', exact: true }).click();
  await page.getByRole('button', { name: '繼續演出' }).click();
  await page.getByRole('button', { name: '繼續演出' }).click();
}

test('BGM 開關記住選擇，關閉後操作及換曲不恢復播放，開啟接續播放', async ({ page }) => {
  await page.goto('/');
  const toggle = page.getByTestId('bgm-toggle');
  const audio = page.locator('audio');
  await expect(toggle).toHaveText('音樂：開');
  await toggle.click();
  await expect(toggle).toHaveAttribute('aria-pressed', 'false');
  await expect(audio).toHaveJSProperty('paused', true);
  await page.reload();
  await expect(toggle).toHaveText('音樂：關');
  await page.getByRole('button', { name: opening.opening_choices[1].label }).click();
  await page.getByRole('dialog').getByRole('button', { name: '確認', exact: true }).click();
  await expect(audio).toHaveAttribute('src', '/audio/bgm/bgm_02_day_ch1_b.mp3');
  await page.keyboard.press('Shift');
  await expect(audio).toHaveJSProperty('paused', true);
  await expect(audio).toHaveJSProperty('muted', true);
  await toggle.click();
  await expect(audio).toHaveJSProperty('paused', false);
  await expect(audio).toHaveJSProperty('muted', false);
  await audio.evaluate(el => { (el as HTMLAudioElement).currentTime = 10; });
  await toggle.click();
  await toggle.click();
  await expect(audio).toHaveJSProperty('paused', false);
  expect(await audio.evaluate(el => (el as HTMLAudioElement).currentTime)).toBeGreaterThanOrEqual(10);
});

test('正式開局日夜雙向轉場：遮住後才切換，期間封鎖操作', async ({ page }) => {
  await reachEveningEnd(page);
  await finishStory(page);
  // 轉場期間內容 inert；中途斷言不能讓自動補字 handler 等待可點擊。
  await page.removeLocatorHandler(page.locator('body:not(:has(dialog[open])) [data-typing="true"]').first());
  await page.clock.install();
  await page.clock.pauseAt(new Date());
  await page.getByRole('button', { name: '推進時段', exact: true }).click();
  const overlay = page.getByTestId('day-night-transition');
  await expect(overlay).toHaveClass('day-night-transition to-night');
  await expect(overlay).toHaveCSS('background-color', 'rgb(8, 11, 16)');
  await expect(page.locator('html')).toHaveAttribute('data-theme', 'day');
  expect(await page.locator('.save-panel').evaluate(el => el.parentElement!.inert)).toBe(true);
  await page.keyboard.press('Enter');
  await page.clock.runFor(410);
  await expect(overlay).toHaveClass('day-night-transition to-night revealing');
  await expect(page.locator('html')).toHaveAttribute('data-theme', 'night');
  await page.clock.runFor(410);
  await expect(overlay).toHaveCount(0);
  expect(await page.locator('.save-panel').evaluate(el => el.parentElement!.inert)).toBe(false);

  await finishStory(page);
  await page.getByRole('button', { name: '結束今晚', exact: true }).click();
  await expect(overlay).toHaveClass('day-night-transition to-day');
  await expect(overlay).toHaveCSS('background-color', 'rgb(238, 230, 215)');
  await expect(page.locator('html')).toHaveAttribute('data-theme', 'night');
  await page.clock.runFor(410);
  await expect(page.locator('html')).toHaveAttribute('data-theme', 'day');
  await expect(page.locator('header')).toContainText('第 2 天');
  await page.clock.runFor(410);
  await expect(overlay).toHaveCount(0);
});

test('減少動態效果時日夜直接切換，初次載入不播放轉場', async ({ page }) => {
  await page.emulateMedia({ reducedMotion: 'reduce' });
  await reachEveningEnd(page);
  await expect(page.getByTestId('day-night-transition')).toHaveCount(0);
  await page.getByRole('button', { name: '推進時段', exact: true }).click();
  await expect(page.locator('html')).toHaveAttribute('data-theme', 'night');
  await expect(page.getByTestId('day-night-transition')).toHaveCount(0);
});
