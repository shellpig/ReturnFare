import { expect, test, type Page } from '@playwright/test';
import { readFileSync } from 'node:fs';

const locations = JSON.parse(readFileSync('../data/locations.json', 'utf8')).day;
const cards = JSON.parse(readFileSync('../data/cards.json', 'utf8')).cards;
const locById = (id: string) => locations.find((l: { id: string }) => l.id === id);
const cardById = (id: string) => cards.find((c: { id: string }) => c.id === id);

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
        const override = JSON.parse(sessionStorage.getItem('__w5c_snap_override__') || 'null');
        if (override) {
          base.flow.mode = 'run';
          base.run.day = override.day;
          base.run.phase = override.phase;
          base.run.hand = override.hand || ['protagonist'];
          base.run.flags = override.flags || {};
          base.meta.knowledge = override.knowledge || {};
          base.meta.day_locations_visited = override.visited || {};
        }
        const game = __origCreateGame(data, override ? base : initialState);
        win.__testGame = game;
        return game;
      }\n`;
    await route.fulfill({
      response,
      body: patchedBody,
    });
  });
}

test.describe('W5-C choice_group UI interactions', () => {
  test('formal D22 sandbags direct choice: picker escape zero mutation, choice stays read-only, other options collapse, result visible, no raw English code', async ({
    page,
  }) => {
    await page.setViewportSize({ width: 1280, height: 720 });
    await setupGameInspectionRoute(page);

    // Inject trusted formal D22 afternoon snapshot
    await page.addInitScript(() => {
      sessionStorage.setItem(
        '__w5c_snap_override__',
        JSON.stringify({
          day: 22,
          phase: 'afternoon',
          flags: { acai_obs_knee: true },
          hand: ['protagonist', 'equip_polaroid'],
          visited: { sanquan: true },
        }),
      );
    });

    await page.goto('/');

    // Verify D22 Afternoon on header
    await expect(page.locator('header')).toContainText('第 22 天');
    await expect(page.locator('.map-panel')).toBeVisible();

    // Enter Sanquan
    const sanquanBtn = page.getByRole('button', { name: locById('sanquan').name });
    await expect(sanquanBtn).toBeEnabled();
    await sanquanBtn.click();

    // Advance beat intro ("下雨前全鎮都在忙...")
    const continueBtn = page.getByRole('button', { name: '繼續演出' });
    await expect(continueBtn).toBeVisible();
    await continueBtn.click();

    // Slots stage is now displayed
    const obsWalkSlot = page.locator('[data-testid="slot-obs_walk"]');
    await expect(obsWalkSlot).toBeVisible();
    await expect(page.locator('[data-testid="slot-obs_hands"]')).toBeVisible();
    await expect(page.locator('[data-testid="slot-obs_talk"]')).toBeVisible();
    await expect(page.locator('[data-testid="slot-dismiss"]')).toBeVisible();

    // 1. Verify card picker open -> Escape/close leaves full serialize unchanged
    const beforePickerState = await page.evaluate(() => {
      const win = window as unknown as {
        __testGame?: { serialize: () => Record<string, unknown> };
      };
      return win.__testGame ? JSON.stringify(win.__testGame.serialize()) : null;
    });
    expect(beforePickerState).not.toBeNull();

    // Click "放入卡片" on obs_walk
    const placeBtn = obsWalkSlot.locator('[data-testid="place-btn-obs_walk"]');
    await expect(placeBtn).toBeVisible();
    await placeBtn.click();

    // Card picker dialog is open
    const pickerDialog = page.locator('dialog.card-picker-dialog');
    await expect(pickerDialog).toBeVisible();
    await expect(
      pickerDialog.getByRole('button', {
        name: cardById('equip_polaroid').name,
      }),
    ).toBeVisible();

    // Press Escape to close dialog
    await page.keyboard.press('Escape');
    await expect(pickerDialog).not.toBeVisible();

    const afterPickerState = await page.evaluate(() => {
      const win = window as unknown as {
        __testGame?: { serialize: () => Record<string, unknown> };
      };
      return win.__testGame ? JSON.stringify(win.__testGame.serialize()) : null;
    });
    expect(afterPickerState).toBe(beforePickerState);

    // 2. Real click direct choice on obs_walk
    const chooseBtn = obsWalkSlot.locator('[data-testid="choose-btn-obs_walk"]');
    await expect(chooseBtn).toBeVisible();
    await chooseBtn.click();

    // Chosen slot stays visible read-only (has .slot-resolved, no buttons)
    await expect(obsWalkSlot).toBeVisible();
    await expect(obsWalkSlot).toHaveClass(/slot-resolved/);
    await expect(obsWalkSlot.locator('button')).toHaveCount(0);

    // Other options of acai_read group disappear
    await expect(page.locator('[data-testid="slot-obs_hands"]')).toHaveCount(0);
    await expect(page.locator('[data-testid="slot-obs_talk"]')).toHaveCount(0);
    await expect(page.locator('[data-testid="slot-dismiss"]')).toHaveCount(0);

    // Result text is visible in action-result-box
    const resultBox = page.locator('[data-testid="action-result"]');
    await expect(resultBox).toBeVisible();
    await expect(resultBox).toContainText('你死死盯著他走下木梯的雙腳');

    // Ensure NO raw English reason codes anywhere in the location panel
    const panelText = await page.locator('.location-panel').innerText();
    expect(panelText).not.toMatch(/\bresolved\b/i);
    expect(panelText).not.toMatch(/\bcard_required\b/i);
    expect(panelText).not.toMatch(/\bnot_accepted\b/i);
    expect(panelText).not.toMatch(/\baction_spent\b/i);
    expect(panelText).not.toMatch(/\bunknown_beat\b/i);
    expect(panelText).not.toMatch(/\bunknown_slot\b/i);
    expect(panelText).not.toMatch(/\bnot_held\b/i);

    // Verify choice persisted in game state
    const afterChoiceState = await page.evaluate(() => {
      const win = window as unknown as {
        __testGame?: { serialize: () => { run: { choices: Record<string, string> } } };
      };
      return win.__testGame ? win.__testGame.serialize().run.choices : null;
    });
    expect(afterChoiceState?.['d22_pm_sandbags::acai_read']).toBe('obs_walk');
  });

  test('formal D22 sandbags choice with equip_polaroid card: resolves, collapses other options, and shows result', async ({
    page,
  }) => {
    await page.setViewportSize({ width: 1280, height: 720 });
    await setupGameInspectionRoute(page);

    await page.addInitScript(() => {
      sessionStorage.setItem(
        '__w5c_snap_override__',
        JSON.stringify({
          day: 22,
          phase: 'afternoon',
          flags: { acai_obs_knee: true },
          hand: ['protagonist', 'equip_polaroid'],
          visited: { sanquan: true },
        }),
      );
    });

    await page.goto('/');

    const sanquanBtn = page.getByRole('button', { name: locById('sanquan').name });
    await sanquanBtn.click();

    const continueBtn = page.getByRole('button', { name: '繼續演出' });
    await continueBtn.click();

    const obsWalkSlot = page.locator('[data-testid="slot-obs_walk"]');
    await expect(obsWalkSlot).toBeVisible();

    // Click "放入卡片" on obs_walk
    await obsWalkSlot.locator('[data-testid="place-btn-obs_walk"]').click();

    const pickerDialog = page.locator('dialog.card-picker-dialog');
    await expect(pickerDialog).toBeVisible();

    // Select equip_polaroid
    const polaroidBtn = pickerDialog.locator('[data-testid="candidate-equip_polaroid"]');
    await expect(polaroidBtn).toBeVisible();
    await polaroidBtn.click();

    await expect(pickerDialog).not.toBeVisible();

    // Chosen slot stays visible as RESOLVED
    await expect(obsWalkSlot).toBeVisible();
    await expect(obsWalkSlot).toHaveClass(/slot-resolved/);
    await expect(obsWalkSlot.locator('button')).toHaveCount(0);

    // Other options of acai_read group disappear
    await expect(page.locator('[data-testid="slot-obs_hands"]')).toHaveCount(0);
    await expect(page.locator('[data-testid="slot-obs_talk"]')).toHaveCount(0);
    await expect(page.locator('[data-testid="slot-dismiss"]')).toHaveCount(0);

    // Result text is visible
    const resultBox = page.locator('[data-testid="action-result"]');
    await expect(resultBox).toBeVisible();
    await expect(resultBox).toContainText('你死死盯著他走下木梯的雙腳');
  });
});
