import { expect, test } from '@playwright/test';
import { readFileSync } from 'node:fs';

const opening = JSON.parse(readFileSync('../data/opening_choices.json', 'utf8'));
const beats = JSON.parse(readFileSync('../data/beats/ch1_d01_d03.json', 'utf8')).beats;
const beat = (id: string) => beats.find((b: { id: string }) => b.id === id);

test('story types, click reveals without advancing, next passage resets, natural completion reveals controls', async ({ page }) => {
  await page.clock.install();
  await page.goto('/');
  await page.getByRole('button', { name: opening.opening_choices[1].label }).click();
  await page.getByRole('dialog').getByRole('button', { name: '確認', exact: true }).click();
  const story = page.locator('.narration');
  const passage = page.locator('.passage');
  await expect(story).toHaveAttribute('data-typing', 'true');
  await expect(page.getByRole('button', { name: '繼續演出' })).toHaveCount(0);
  await expect(page.locator('.hand-panel')).toBeHidden();
  await page.clock.runFor(90);
  const partial = await passage.innerText();
  expect(partial.length).toBeGreaterThan(0);
  expect(partial.length).toBeLessThan(beat('d1_morning_phone').text.length);
  await page.mouse.click(2, 2);
  await expect(passage).toHaveText(beat('d1_morning_phone').text);
  await expect(page.locator('header')).toContainText('第 1 天 上午');
  await expect(page.getByRole('button', { name: '繼續演出' })).toBeVisible();
  await page.getByRole('button', { name: '繼續演出' }).click();
  await expect(story).toHaveAttribute('data-typing', 'true');
  expect((await passage.innerText()).length).toBeLessThan(beat('d1_morning_departure').text.length);
  await story.focus();
  await page.keyboard.press('Space');
  await expect(passage).toHaveText(beat('d1_morning_departure').text);
  await expect(page.locator('header')).toContainText('上午');
  await page.getByRole('button', { name: '推進時段', exact: true }).click();
  await expect(story).toHaveAttribute('data-typing', 'true');
  await expect(page.getByRole('button', { name: '推進時段', exact: true })).toHaveCount(0);
  await page.clock.runFor(Array.from(beat('d1_pm_mountain_road').text).length * 30 + 60);
  await expect(passage).toHaveText(beat('d1_pm_mountain_road').text);
  await expect(page.getByRole('button', { name: '推進時段', exact: true })).toBeVisible();
  await expect(page.locator('.hand-panel')).toBeVisible();
});

test('location story and description gate buttons and people until revealed', async ({ page }) => {
  await page.route(/\/src\/core\/state\.ts(\?.*)?$/, async route => {
    const response = await route.fetch();
    const body = (await response.text()).replace('export function createGame(', 'function originalCreateGame(') + `
      export function createGame(data) {
        const base = originalCreateGame(data).serialize();
        base.flow.mode = 'run'; base.run.day = 2; base.run.phase = 'morning';
        return originalCreateGame(data, base);
      }`;
    await route.fulfill({ response, body });
  });
  await page.goto('/');
  await page.getByRole('button', { name: '山泉閣', exact: true }).click();
  const panel = page.locator('.location-panel');
  await expect(panel).toHaveAttribute('data-typing', 'true');
  await expect(page.getByRole('button', { name: '繼續演出' })).toBeHidden();
  await expect(page.locator('.phase-actions')).toBeHidden();
  await page.locator('.scene-art').click({ position: { x: 5, y: 5 } });
  await expect(page.locator('.beat-text')).toHaveText(beat('d2_morning_intro').text);
  await expect(page.locator('.location-desc')).toHaveCount(0);
  await page.getByRole('button', { name: '繼續演出' }).click();
  await expect(panel).toHaveAttribute('data-typing', 'true');
  await expect(page.locator('.beats-list')).toBeHidden();
  await expect(page.getByRole('button', { name: '返回地圖' })).toBeHidden();
  await page.mouse.click(2, 2);
  await expect(panel).toHaveAttribute('data-typing', 'false');
  await expect(page.locator('.slot-display')).toHaveCount(2);
  await expect(page.locator('.beats-list')).toBeVisible();
  await expect(page.getByRole('button', { name: '返回地圖' })).toBeVisible();
  await expect(page.locator('.phase-actions')).toBeVisible();
});
