import { expect, test, type Page } from '@playwright/test';
import { readFileSync } from 'node:fs';

const opening = JSON.parse(readFileSync('../data/opening_choices.json', 'utf8'));
const cards = JSON.parse(readFileSync('../data/cards.json', 'utf8')).cards;
const locations = JSON.parse(readFileSync('../data/locations.json', 'utf8')).day;
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
        const game = __origCreateGame(data, initialState);
        win.__testGame = game;
        return game;
      }\n`;
    await route.fulfill({
      response,
      body: patchedBody,
    });
  });
}

test('UI real player flow: walks D1-D3, readonly preview equality, free compare and protagonist action with visible persistent results', async ({
  page,
}) => {
  await page.setViewportSize({ width: 1280, height: 720 });
  await setupGameInspectionRoute(page);
  await page.goto('/');

  // 1. Choose opening (take_family_album)
  await page
    .getByRole('button', { name: opening.opening_choices[0].label })
    .click();
  await page
    .getByRole('dialog')
    .getByRole('button', { name: '確認', exact: true })
    .click();

  const nextBtn = page.getByRole('button', { name: '繼續演出' });
  const advanceBtn = page.getByRole('button', { name: '推進時段' });

  // D1 morning -> afternoon -> evening -> night -> D2 morning
  await nextBtn.click();
  await advanceBtn.click(); // -> D1 pm

  await nextBtn.click();
  await advanceBtn.click(); // -> D1 eve

  await nextBtn.click();
  await nextBtn.click();
  await nextBtn.click();
  await advanceBtn.click(); // -> D1 night

  await nextBtn.click();
  await advanceBtn.click(); // -> D2 morning

  await expect(page.locator('header')).toContainText('第 2 天');
  await expect(page.locator('.map-panel')).toBeVisible();

  // Enter Sanquan on D2 morning
  const sanquanBtn = page.getByRole('button', { name: locById('sanquan').name });
  await expect(sanquanBtn).toBeEnabled();
  await sanquanBtn.click();

  // Stage 1 -> click 繼續演出 -> Stage 2
  await nextBtn.click();
  await expect(page.locator('.slot-item')).toHaveCount(2);

  // Readonly preview check on slot 'ajie' (accepts: [])
  const beforePreviewState = await page.evaluate(() => {
    const win = window as unknown as { __testGame?: { serialize: () => Record<string, unknown> } };
    return win.__testGame ? JSON.stringify(win.__testGame.serialize()) : null;
  });
  expect(beforePreviewState).not.toBeNull();

  // Right-click slot 'ajie'
  const ajieSlot = page.locator('[data-testid="slot-ajie"]');
  await ajieSlot.dispatchEvent('contextmenu');

  const previewDialog = page.locator('dialog.slot-preview-dialog');
  await expect(previewDialog).toBeVisible();
  await expect(previewDialog.getByText('目前沒有可放的卡。')).toBeVisible();

  // Close preview dialog
  await previewDialog.getByRole('button', { name: '關閉' }).click();
  await expect(previewDialog).not.toBeVisible();

  const afterPreviewState = await page.evaluate(() => {
    const win = window as unknown as { __testGame?: { serialize: () => Record<string, unknown> } };
    return win.__testGame ? JSON.stringify(win.__testGame.serialize()) : null;
  });
  // STRICT serialization equality before and after preview dialog
  expect(afterPreviewState).toBe(beforePreviewState);

  // Return to map and advance D2 morning -> D2 afternoon
  await page.getByRole('button', { name: '返回地圖' }).click();
  const phaseAdvanceBtn = page.locator('.phase-actions button');
  await expect(phaseAdvanceBtn).toBeEnabled();
  await phaseAdvanceBtn.click();

  await expect(page.locator('header')).toContainText('下午');

  // D2 afternoon: enter Sanquan
  await sanquanBtn.click();
  // Stage 1 (d2_pm_work) -> click 繼續演出 -> Stage 2
  await nextBtn.click();

  // Slot 'work' is OPEN and accepts protagonist
  const workSlot = page.locator('[data-testid="slot-work"]');
  await expect(workSlot).toBeVisible();

  // Right-click slot 'work' -> readonly preview shows protagonist
  await workSlot.dispatchEvent('contextmenu');
  await expect(previewDialog).toBeVisible();
  await expect(previewDialog.getByText('可放置卡片：')).toBeVisible();
  await expect(previewDialog.getByText(cardById('protagonist').name)).toBeVisible();
  await previewDialog.getByRole('button', { name: '關閉' }).click();
  await expect(previewDialog).not.toBeVisible();

  // Click slot 'work' to open card picker dialog
  await workSlot.click();
  const pickerDialog = page.locator('dialog.card-picker-dialog');
  await expect(pickerDialog).toBeVisible();
  const candidateBtn = pickerDialog.locator('[data-testid="candidate-protagonist"]');
  await expect(candidateBtn).toBeVisible();

  // Choose protagonist
  await candidateBtn.click();
  await expect(pickerDialog).not.toBeVisible();

  // Placement succeeded: result text is visible in .action-result-box
  const actionResultBox = page.locator('[data-testid="action-result"]');
  await expect(actionResultBox).toBeVisible();
  await expect(actionResultBox).toContainText('兩段說法都言之鑿鑿');

  // Gained info cards appear in HandPanel
  const handPanel = page.locator('.hand-panel');
  await expect(handPanel.locator('[data-testid="card-info_husband_version"]')).toBeVisible();
  await expect(handPanel.locator('[data-testid="card-info_wife_version"]')).toBeVisible();

  // Slot 'work' is now resolved (and ordinary resolved is hidden)
  await expect(page.locator('[data-testid="slot-work"]')).toHaveCount(0);

  // Return to map, advance D2 afternoon -> evening -> night -> D3 morning -> D3 afternoon
  await page.getByRole('button', { name: '返回地圖' }).click();
  await page.locator('.phase-actions button').click(); // -> D2 evening

  // D2 evening narration (3 passages: bath intro, bath on_enter, debt alert)
  await nextBtn.click();
  await nextBtn.click();
  await nextBtn.click();
  await advanceBtn.click(); // -> D2 night

  // D2 night narration
  await nextBtn.click();
  await advanceBtn.click(); // -> D3 morning

  // D3 morning map
  await expect(page.locator('header')).toContainText('第 3 天');
  await sanquanBtn.click();
  await nextBtn.click(); // finish morning beat
  await page.getByRole('button', { name: '返回地圖' }).click();
  await page.locator('.phase-actions button').click(); // -> D3 afternoon

  await expect(page.locator('header')).toContainText('下午');

  // D3 afternoon: enter Sanquan
  await sanquanBtn.click();
  await nextBtn.click(); // d3_pm_sanquan Stage 1 -> Stage 2

  // Free compare slot: show_version
  const showVersionSlot = page.locator('[data-testid="slot-show_version"]');
  await expect(showVersionSlot).toBeVisible();

  // Click show_version slot -> picker opens with info_husband_version and info_wife_version
  await showVersionSlot.click();
  await expect(pickerDialog).toBeVisible();
  const husbandCandidate = pickerDialog.locator('[data-testid="candidate-info_husband_version"]');
  await expect(husbandCandidate).toBeVisible();
  await husbandCandidate.click();
  await expect(pickerDialog).not.toBeVisible();

  // Result text visible
  await expect(actionResultBox).toContainText('你平靜地將昨日聽見的那段話挑明');

  // Action NOT spent: help_ahong slot is still open and protagonist can be placed!
  const helpAhongSlot = page.locator('[data-testid="slot-help_ahong"]');
  await expect(helpAhongSlot).toBeVisible();
  await helpAhongSlot.click();
  await expect(pickerDialog).toBeVisible();
  await pickerDialog.locator('[data-testid="candidate-protagonist"]').click();
  await expect(pickerDialog).not.toBeVisible();

  // Protagonist result text visible
  await expect(actionResultBox).toContainText('你走過去幫阿宏搭手抬起沉重的鐵箱');

  // Protagonist card is STILL in hand!
  await expect(handPanel.locator('[data-testid="card-protagonist"]')).toBeVisible();

  // Preview of another protagonist slot shows the Chinese reason, never the raw code; Escape closes it
  await page.locator('[data-testid="slot-handle_couple"]').click({ button: 'right' });
  await expect(previewDialog).toContainText('理由：本時段行動已用完');
  await expect(previewDialog).not.toContainText('action_spent');
  await page.keyboard.press('Escape');
  await expect(previewDialog).toHaveCount(0);

  // State inspection: action_spent is true, slots_placed has both slots
  const finalState = await page.evaluate(() => {
    const win = window as unknown as { __testGame?: { serialize: () => { run: Record<string, unknown> } } };
    return win.__testGame ? win.__testGame.serialize().run : null;
  });
  expect(finalState).not.toBeNull();
  expect(finalState!.action_spent).toBe(true);
  expect((finalState!.slots_placed as Record<string, boolean>)['d3_pm_sanquan::show_version']).toBe(true);
  expect((finalState!.slots_placed as Record<string, boolean>)['d3_pm_sanquan::help_ahong']).toBe(true);
});
