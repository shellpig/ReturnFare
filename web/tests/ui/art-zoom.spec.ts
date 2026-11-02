import { test, expect, type Page } from '@playwright/test';
import { readFileSync } from 'node:fs';

const opening = JSON.parse(readFileSync('../data/opening_choices.json', 'utf8'));
const beats = JSON.parse(readFileSync('../data/beats/ch1_d01_d03.json', 'utf8')).beats;
const intro = beats.find((beat: { id: string }) => beat.id === 'd2_morning_intro');
test.use({ viewport: { width: 390, height: 844 }, hasTouch: true, isMobile: true });

async function reveal(page: Page) {
  const typing = page.locator('[data-typing="true"]').first();
  if (await typing.count()) await typing.tap();
}

async function dragTouch(page: Page, x: number, y: number, dx: number, dy: number) {
  const session = await page.context().newCDPSession(page);
  try {
    await session.send('Input.dispatchTouchEvent', { type: 'touchStart', touchPoints: [{ x, y }] });
    for (let step = 1; step <= 5; step++) {
      await session.send('Input.dispatchTouchEvent', { type: 'touchMove', touchPoints: [{ x: x + dx * step / 5, y: y + dy * step / 5 }] });
    }
    await session.send('Input.dispatchTouchEvent', { type: 'touchEnd', touchPoints: [] });
  } finally {
    await session.detach();
  }
}

test('mobile artwork zoom toggles, pans without navigating, keeps markers clickable and lets scene text extend below the image', async ({ page }) => {
  await page.goto('/');
  await page.getByRole('button', { name: opening.opening_choices[0].label }).tap();
  await page.getByRole('dialog').getByRole('button', { name: '確認', exact: true }).tap();
  await reveal(page);
  await page.getByRole('button', { name: '推進時段', exact: true }).tap();
  await reveal(page);
  await page.getByRole('button', { name: '推進時段', exact: true }).tap();
  await reveal(page);
  await page.getByRole('button', { name: '繼續演出', exact: true }).tap();
  await reveal(page);
  await page.getByRole('button', { name: '繼續演出', exact: true }).tap();
  await reveal(page);
  await page.getByRole('button', { name: '推進時段', exact: true }).tap();
  await reveal(page);
  await page.getByRole('button', { name: '結束今晚', exact: true }).tap();
  await expect(page.locator('.map-panel')).toBeVisible();
  const map = page.locator('.map-art-frame');
  const originalWidth = (await page.locator('.map-art').boundingBox())!.width;
  const zoomButton = page.getByRole('button', { name: '放大圖片 2x', exact: true });
  const initialBackground = await zoomButton.evaluate(button => getComputedStyle(button).backgroundColor);
  const buttonBox = (await zoomButton.boundingBox())!;
  expect(buttonBox.y + buttonBox.height).toBeLessThanOrEqual((await page.locator('.map-art').boundingBox())!.y);
  await zoomButton.hover();
  await expect(zoomButton).toHaveCSS('background-color', initialBackground);
  const saved = await page.evaluate(() => localStorage.getItem('returnfare.save.auto'));
  await page.getByRole('button', { name: '放大圖片 2x', exact: true }).tap();
  await expect(map).toHaveAttribute('data-zoomed', 'true');
  await expect(page.getByRole('button', { name: '恢復原圖', exact: true })).toHaveCSS('background-color', initialBackground);
  expect((await page.locator('.map-art').boundingBox())!.width).toBeCloseTo(originalWidth * 2, 0);
  await page.getByRole('button', { name: '恢復原圖', exact: true }).tap();
  await expect(map).toHaveAttribute('data-zoomed', 'false');
  await expect(zoomButton).toHaveCSS('background-color', initialBackground);
  expect((await page.locator('.map-art').boundingBox())!.width).toBeCloseTo(originalWidth, 0);
  await page.getByRole('button', { name: '放大圖片 2x', exact: true }).tap();
  const marker = page.getByRole('button', { name: '山泉閣', exact: true });
  const point = (await marker.boundingBox())!;
  const transformBefore = await map.locator('.art-canvas').evaluate(canvas => canvas.style.transform);
  await dragTouch(page, point.x + point.width / 2, point.y + point.height / 2, -24, 32);
  await expect(page.locator('.location-panel')).toHaveCount(0);
  expect(await map.locator('.art-canvas').evaluate(canvas => canvas.style.transform)).not.toBe(transformBefore);
  expect(await page.evaluate(() => localStorage.getItem('returnfare.save.auto'))).toBe(saved);
  await page.screenshot({ path: '../_qa/web/map-mobile-zoom.png', fullPage: true });

  // Keep native touch scheduling active while checking that controls don't reveal prose.
  await marker.tap();
  const panel = page.locator('.location-panel');
  await expect(panel).toHaveAttribute('data-typing', 'true');
  const scene = page.locator('.scene-art-view');
  const sceneWidth = (await page.locator('.scene-art').boundingBox())!.width;
  const sceneButtonBox = (await zoomButton.boundingBox())!;
  expect(sceneButtonBox.y + sceneButtonBox.height).toBeLessThanOrEqual((await page.locator('.scene-art').boundingBox())!.y);
  await page.getByRole('button', { name: '放大圖片 2x', exact: true }).tap();
  await expect(scene).toHaveAttribute('data-zoomed', 'true');
  await expect(panel).toHaveAttribute('data-typing', 'true');
  expect((await page.locator('.scene-art').boundingBox())!.width).toBeCloseTo(sceneWidth * 2, 0);
  const sceneViewport = (await scene.locator('.art-viewport').boundingBox())!;
  const sceneTransform = await scene.locator('.art-canvas').evaluate(canvas => canvas.style.transform);
  await dragTouch(page, sceneViewport.x + 50, sceneViewport.y + 50, 30, 25);
  expect(await scene.locator('.art-canvas').evaluate(canvas => canvas.style.transform)).not.toBe(sceneTransform);
  await expect(panel).toHaveAttribute('data-typing', 'true');
  await page.getByRole('button', { name: '恢復原圖', exact: true }).tap();
  await expect(scene).toHaveAttribute('data-zoomed', 'false');
  await expect(panel).toHaveAttribute('data-typing', 'true');
  await page.locator('.scene-text-overlay').tap();
  await expect(page.locator('.beat-text')).toHaveText(intro.text);
  const geometry = await page.locator('.scene-art-frame').evaluate(frame => {
    const image = frame.querySelector('img')!.getBoundingClientRect();
    const paragraph = frame.querySelector('.beat-text')!.getBoundingClientRect();
    const overlay = frame.querySelector('.scene-text-overlay')!;
    return { extendsBelow: paragraph.bottom > image.bottom, fits: paragraph.bottom <= frame.getBoundingClientRect().bottom,
      noInternalScroll: overlay.scrollHeight <= overlay.clientHeight + 1 };
  });
  expect(geometry).toEqual({ extendsBelow: true, fits: true, noInternalScroll: true });
  await page.screenshot({ path: '../_qa/web/scene-mobile-flow.png', fullPage: true });
  await page.setViewportSize({ width: 1280, height: 800 });
  await expect(page.locator('.art-zoom-toggle')).toBeHidden();
});
