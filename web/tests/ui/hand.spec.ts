import { expect, test, type Page } from '@playwright/test';
import { readFileSync } from 'node:fs';

const opening = JSON.parse(readFileSync('../data/opening_choices.json', 'utf8'));
const cards = JSON.parse(readFileSync('../data/cards.json', 'utf8')).cards;
const tuning = JSON.parse(readFileSync('../data/tuning.json', 'utf8'));
const cardsById = (id: string) => cards.find((c: { id: string }) => c.id === id);

async function setupGameInspectionRoute(page: Page) {
  await page.route(/\/src\/core\/state\.ts(\?.*)?$/, async (route) => {
    const response = await route.fetch();
    const originalBody = await response.text();
    const patchedBody =
      originalBody.replace(
        'export function createGame(',
        'function __origCreateGame(',
      ) +
      `\nexport function createGame(data, initialState) {
        const win = window;
        const base = __origCreateGame(data).serialize();
        const override = JSON.parse(sessionStorage.getItem('__w5a_snap_override__') || 'null');
        if (override) {
          base.flow.mode = 'run';
          base.run.day = override.day;
          base.run.phase = override.phase;
          base.run.hand = override.hand || ['protagonist'];
          base.meta.knowledge = override.knowledge || {};
          base.meta.day_locations_visited = override.visited || {};
        }
        const game = __origCreateGame(data, override ? base : initialState);
        win.__w5aGame = game;
        return game;
      }\n`;
    await route.fulfill({
      response,
      body: patchedBody,
    });
  });
}

test('normal album opening displays protagonist and album each once, opens readable card detail dialog, and closes with zero state mutation', async ({
  page,
}) => {
  // Explicitly set viewport to 1280x720 before goto
  await page.setViewportSize({ width: 1280, height: 720 });
  await setupGameInspectionRoute(page);
  await page.goto('/');

  // 1. Choose first opening option (take_family_album)
  await page
    .getByRole('button', { name: opening.opening_choices[0].label })
    .click();
  await page
    .getByRole('dialog')
    .getByRole('button', { name: '確認', exact: true })
    .click();

  // D1 morning narration phase
  const handPanel = page.locator('.hand-panel');
  await expect(handPanel).toBeVisible();

  // Hand slots: "手牌 2 / <tuning.hand_size>"
  await expect(handPanel.getByTestId('hand-slots')).toHaveText(
    `手牌 2 / ${tuning.hand_size}`,
  );
  // Knowledge count: "知識 (0)"
  await expect(handPanel.getByTestId('knowledge-btn')).toHaveText('知識 (0)');

  // Hand cards: exactly protagonist and family album, each once
  const cardBtns = handPanel.locator('.card-btn');
  await expect(cardBtns).toHaveCount(2);
  await expect(cardBtns.nth(0)).toHaveText(cardsById('protagonist').name);
  await expect(cardBtns.nth(1)).toHaveText(cardsById('item_family_album').name);

  // Capture full state before opening detail dialog
  const beforeSerialized = await page.evaluate(() => {
    const win = window as unknown as {
      __w5aGame?: { serialize: () => Record<string, unknown> };
    };
    return win.__w5aGame ? JSON.stringify(win.__w5aGame.serialize()) : null;
  });
  expect(beforeSerialized).not.toBeNull();

  // Click album card to open CardDetail
  await handPanel.getByTestId('card-item_family_album').click();

  const dialog = page.locator('dialog.card-detail-dialog');
  await expect(dialog).toBeVisible();
  await expect(dialog.locator('#card-dialog-title')).toHaveText('卡片詳情');
  await expect(dialog.locator('.card-detail-name')).toHaveText(
    cardsById('item_family_album').name,
  );
  await expect(dialog.locator('.card-detail-text')).toHaveText(
    cardsById('item_family_album').text,
  );

  // Check dialog bounding box fits completely inside 1280x720 viewport
  const box = await dialog.boundingBox();
  expect(box).not.toBeNull();
  expect(box!.x).toBeGreaterThanOrEqual(0);
  expect(box!.y).toBeGreaterThanOrEqual(0);
  expect(box!.x + box!.width).toBeLessThanOrEqual(1280);
  expect(box!.y + box!.height).toBeLessThanOrEqual(720);

  // Check desktop horizontal scrollWidth fits within innerWidth
  const noOverflow = await page.evaluate(
    () => document.documentElement.scrollWidth <= window.innerWidth,
  );
  expect(noOverflow).toBe(true);

  // Close dialog using "關閉" button
  await dialog.getByRole('button', { name: '關閉' }).click();
  await expect(dialog).toHaveCount(0);

  // Capture full state after closing dialog and verify byte-for-byte identity
  const afterSerialized = await page.evaluate(() => {
    const win = window as unknown as {
      __w5aGame?: { serialize: () => Record<string, unknown> };
    };
    return win.__w5aGame ? JSON.stringify(win.__w5aGame.serialize()) : null;
  });
  expect(afterSerialized).toBe(beforeSerialized);

  // Verify hand panel UI remains intact
  await expect(handPanel.getByTestId('hand-slots')).toHaveText(
    `手牌 2 / ${tuning.hand_size}`,
  );
  await expect(handPanel.getByTestId('knowledge-btn')).toHaveText('知識 (0)');
  await expect(cardBtns).toHaveCount(2);
});

test('separate trusted formal knowledge snapshot verifies separate knowledge display, count, order, and details without mutation', async ({
  page,
}) => {
  // Explicitly set viewport to 1280x800
  await page.setViewportSize({ width: 1280, height: 800 });
  await setupGameInspectionRoute(page);

  await page.addInitScript(() => {
    sessionStorage.setItem(
      '__w5a_snap_override__',
      JSON.stringify({
        day: 2,
        phase: 'morning',
        hand: ['protagonist'],
        knowledge: {
          k_night_sanquan: true,
          k_i_returned: true,
        },
        visited: { sanquan: true },
      }),
    );
  });

  await page.goto('/');

  const handPanel = page.locator('.hand-panel');
  await expect(handPanel).toBeVisible();

  // Hand slots exclude knowledge: "手牌 1 / <tuning.hand_size>"
  await expect(handPanel.getByTestId('hand-slots')).toHaveText(
    `手牌 1 / ${tuning.hand_size}`,
  );
  // Knowledge count: "知識 (2)"
  await expect(handPanel.getByTestId('knowledge-btn')).toHaveText('知識 (2)');

  // Hand has only protagonist
  const cardBtns = handPanel.locator('.card-btn');
  await expect(cardBtns).toHaveCount(1);
  await expect(cardBtns.nth(0)).toHaveText(cardsById('protagonist').name);

  // Capture full state before opening knowledge dialog
  const beforeSerialized = await page.evaluate(() => {
    const win = window as unknown as {
      __w5aGame?: { serialize: () => Record<string, unknown> };
    };
    return win.__w5aGame ? JSON.stringify(win.__w5aGame.serialize()) : null;
  });
  expect(beforeSerialized).not.toBeNull();

  // Click knowledge button to open knowledge list dialog
  await handPanel.getByTestId('knowledge-btn').click();

  const dialog = page.locator('dialog.card-detail-dialog');
  await expect(dialog).toBeVisible();
  await expect(dialog.locator('#card-dialog-title')).toHaveText('知識清單');

  const items = dialog.locator('.knowledge-item');
  await expect(items).toHaveCount(2);

  // Exact order and content: k_night_sanquan then k_i_returned
  await expect(items.nth(0).locator('.knowledge-name')).toHaveText(
    cardsById('k_night_sanquan').name,
  );
  await expect(items.nth(0).locator('.knowledge-text')).toHaveText(
    cardsById('k_night_sanquan').text,
  );

  await expect(items.nth(1).locator('.knowledge-name')).toHaveText(
    cardsById('k_i_returned').name,
  );
  await expect(items.nth(1).locator('.knowledge-text')).toHaveText(
    cardsById('k_i_returned').text,
  );

  // Check dialog bounding box fits completely inside 1280x800 viewport
  const box = await dialog.boundingBox();
  expect(box).not.toBeNull();
  expect(box!.x).toBeGreaterThanOrEqual(0);
  expect(box!.y).toBeGreaterThanOrEqual(0);
  expect(box!.x + box!.width).toBeLessThanOrEqual(1280);
  expect(box!.y + box!.height).toBeLessThanOrEqual(800);

  // Check desktop horizontal scrollWidth fits within innerWidth
  const noOverflow = await page.evaluate(
    () => document.documentElement.scrollWidth <= window.innerWidth,
  );
  expect(noOverflow).toBe(true);

  // Close via Escape key
  await page.keyboard.press('Escape');
  await expect(dialog).toHaveCount(0);

  // Capture full state after closing dialog and verify byte-for-byte identity
  const afterSerialized = await page.evaluate(() => {
    const win = window as unknown as {
      __w5aGame?: { serialize: () => Record<string, unknown> };
    };
    return win.__w5aGame ? JSON.stringify(win.__w5aGame.serialize()) : null;
  });
  expect(afterSerialized).toBe(beforeSerialized);
});
