import { finishStory } from './story-fixture';
import { expect, test, type Page } from './story-fixture';

/**
 * 測試專用起點注入（透過 Playwright 路由攔截 dev server 的 state.ts，正式產品無測試入口）。
 */
async function injectStartSnapshot(page: Page) {
  await page.route(/\/src\/core\/state\.ts(\?.*)?$/, async (route) => {
    const response = await route.fetch();
    const originalBody = await response.text();
    const patchedBody =
      originalBody.replace(
        'export function createGame(',
        'function __origCreateGame(',
      ) +
      `\nexport function createGame(data, initialState) {
        const base = __origCreateGame(data).serialize();
        const override = JSON.parse(sessionStorage.getItem('__w6e2_snap_override__') || 'null');
        if (override) {
          base.flow.mode = 'run';
          base.run.day = override.day;
          base.run.phase = override.phase;
          if (override.hand) {
            base.run.hand = override.hand;
          }
          if (override.flags) {
            base.run.flags = { ...base.run.flags, ...override.flags };
          }
          if (override.choices) {
            base.run.choices = { ...base.run.choices, ...override.choices };
          }
          if (override.slots_placed) {
            base.run.slots_placed = { ...base.run.slots_placed, ...override.slots_placed };
          }
          if (override.selected_festival_proxy_npc !== undefined) {
            base.run.selected_festival_proxy_npc = override.selected_festival_proxy_npc;
          }
        }
        const game = __origCreateGame(data, base);
        window.__lifecycleTestGame = game;
        return game;
      }\n`;
    await route.fulfill({ response, body: patchedBody });
  });
}

test('D45 evening phase-exit button opens coda location, player chooses empty_handed, advance enters EndingPanel', async ({ page }) => {
  await injectStartSnapshot(page);

  await page.addInitScript(() => {
    sessionStorage.setItem(
      '__w6e2_snap_override__',
      JSON.stringify({
        day: 45,
        phase: 'evening',
        hand: ['protagonist'],
        flags: { final_day: true, invited_none: true },
        choices: { 'd29_pm_invitation::invitation': 'invite_none' },
        slots_placed: { 'd29_pm_invitation::invite_none': true },
        selected_festival_proxy_npc: 'ajie',
      }),
    );
  });

  await page.goto('/');

  // 1. D45 evening 無一般可用地圖地點，但通用 phase-exit-open 按鈕可見
  const phaseExitBtn = page.getByTestId('phase-exit-open');
  await expect(phaseExitBtn).toBeVisible();
  await expect(phaseExitBtn).toHaveText('繼續演出');

  // 未完成 coda 時推進時段按鈕維持停用
  const advanceBtn = page.getByRole('button', { name: '推進時段' });
  await expect(advanceBtn).toBeDisabled();

  // 2. 點擊 phase-exit-open 進入 coda 地點（jinghe_back）
  await phaseExitBtn.click();

  // 3. 讀完 coda 事件文本演出
  const continueBtn = page.getByRole('button', { name: '繼續演出' });
  while (await finishStory(page), await continueBtn.isVisible()) {
    await continueBtn.click();
  }

  // 4. 選擇空手收尾選項（empty_handed）
  const emptyHandedBtn = page.getByTestId('choose-btn-empty_handed');
  await expect(emptyHandedBtn).toBeVisible();
  await emptyHandedBtn.click();

  // 5. coda 完成，推進時段按鈕啟用並推進至結局
  await expect(advanceBtn).toBeEnabled();
  await advanceBtn.click();

  // 6. 進入 EndingPanel：結局文字與頁碼可見，一般地圖／手牌／面板控制項消失
  await expect(page.getByTestId('ending-text')).toBeVisible();
  await expect(page.getByTestId('ending-page')).toBeVisible();
  await expect(page.locator('.hand-panel, .map-panel, .location-panel')).toHaveCount(0);
  await expect(page.getByRole('button', { name: '推進時段' })).toHaveCount(0);
});
