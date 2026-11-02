import { finishStory } from './story-fixture';
import { expect, test, type Page } from './story-fixture';

type TestWindow = {
  __testGame?: {
    serialize: () => {
      run: {
        hand: string[];
        madness_clock: Record<string, number>;
        action_spent: boolean;
        indulgence_count: number;
        forced_pending: string[];
      };
    };
  };
};

/**
 * 注入起點（測試專用，路由攔截 dev server 的 state.ts，產品無入口）。
 */
async function injectStartSnapshot(
  page: Page,
  override: {
    day: number;
    phase: string;
    hand?: string[];
    madness_clock?: Record<string, number>;
    night_location_chosen?: string;
  },
) {
  await page.route(/\/src\/core\/state\.ts(\?.*)?$/, async (route) => {
    const response = await route.fetch();
    const originalBody = await response.text();
    const patchedBody =
      originalBody.replace('export function createGame(', 'function __origCreateGame(') +
      `\nexport function createGame(data, initialState) {
        const base = __origCreateGame(data).serialize();
        const override = JSON.parse(sessionStorage.getItem('__w6b_snap_override__') || 'null');
        if (override) {
          base.flow.mode = 'run';
          base.run.day = override.day;
          base.run.phase = override.phase;
          base.run.hand = override.hand ?? ['protagonist'];
          base.run.madness_clock = override.madness_clock ?? {};
          if (override.night_location_chosen) {
            base.run.night_location_chosen = override.night_location_chosen;
          }
        }
        const game = __origCreateGame(data, override ? base : initialState);
        window.__testGame = game;
        return game;
      }\n`;
    await route.fulfill({ response, body: patchedBody });
  });
  await page.addInitScript((value) => {
    sessionStorage.setItem('__w6b_snap_override__', JSON.stringify(value));
  }, override);
}

test('W6-B UI: 主動放置發狂卡至縱慾出口，扣除行動格且主角卡不可放置', async ({
  page,
}) => {
  await page.setViewportSize({ width: 1280, height: 800 });
  await injectStartSnapshot(page, {
    day: 2,
    phase: 'afternoon',
    hand: ['protagonist', 'madness#1'],
    madness_clock: { 'madness#1': 7 },
  });
  await page.goto('/');

  // 1. 白天地圖點選山泉閣（sanquan）
  const sanquanBtn = page.getByRole('button', { name: /山泉閣/ });
  await expect(sanquanBtn).toBeVisible();
  await sanquanBtn.click();

  // 點選「繼續演出」直到所有新事件播放完畢，進入卡槽階段
  const continueBeatBtn = page.getByRole('button', { name: '繼續演出' });
  while (await finishStory(page), await continueBeatBtn.isVisible()) {
    await continueBeatBtn.click();
  }

  // 2. 找到縱慾出口 beat 底下的砸東西槽位（x_smash）
  const smashSlotBtn = page.locator('[data-testid="place-btn-x_smash"]');
  await expect(smashSlotBtn).toBeVisible();
  await smashSlotBtn.click();

  // 3. 卡片選擇彈窗開啟，候選清單只出現 madness#1，主角卡不在此槽位候選
  const candidateMadness = page.locator('[data-testid="candidate-madness#1"]');
  await expect(candidateMadness).toBeVisible();
  const candidateProtagonist = page.locator('[data-testid="candidate-protagonist"]');
  await expect(candidateProtagonist).toHaveCount(0);

  // 4. 點選發狂卡進行放置
  await candidateMadness.click();

  // 5. 結算結果演出文字顯示
  const resultText = page.locator('[data-testid="action-result"]');
  await expect(resultText).toBeVisible();
  await expect(resultText).toContainText('碎瓷片');

  // 6. 狀態驗證：手牌中的發狂卡已消除，行動格已使用，縱慾次數為 1
  const gameState = await page.evaluate(() => {
    return (window as unknown as TestWindow).__testGame?.serialize();
  });
  expect(gameState?.run.hand).toEqual(['protagonist']);
  expect(gameState?.run.action_spent).toBe(true);
  expect(gameState?.run.indulgence_count).toBe(1);

  // 同一地點的正式主角槽：放卡候選已排除主角。
  await page.getByTestId('place-btn-work').click();
  await expect(page.getByTestId('candidate-protagonist')).toHaveCount(0);
  await expect(page.locator('.empty-candidates')).toBeVisible();
  await page.getByRole('button', { name: '關閉', exact: true }).click();

  // 7. 返回地圖，確認行動格已用完（目前無可做動作）
  const backBtn = page.getByRole('button', { name: '返回地圖' });
  await backBtn.click();
  await expect(page.locator('.map-panel')).toBeVisible();
  await expect(page.locator('.phase-actions button')).toBeEnabled();
});

test('W6-B UI: 夜間進上午自動強制縱慾，演出文字顯示、扣格且主角無法放置', async ({
  page,
}) => {
  await page.setViewportSize({ width: 1280, height: 800 });
  await injectStartSnapshot(page, {
    day: 10,
    phase: 'night',
    hand: ['protagonist', 'madness#1'],
    madness_clock: { 'madness#1': 1 },
    night_location_chosen: 'n_exit',
  });
  await page.goto('/');

  // 1. 夜間按結束今晚（推進至 D11 morning）
  const endNightBtn = page.getByRole('button', { name: '結束今晚' });
  await expect(endNightBtn).toBeVisible();
  await endNightBtn.click();

  // 強制文字直接留在地圖，不與一般逐段演出混用。
  await expect(page.getByTestId('forced-narrative')).toContainText('剩菜');

  // 4. 讀畢回到白天地圖，驗證行動格已耗盡且發狂卡已被消除
  const header = page.locator('header');
  await expect(header).toContainText('上午');

  const afterState = await page.evaluate(() => {
    return (window as unknown as TestWindow).__testGame?.serialize();
  });
  expect(afterState?.run.action_spent).toBe(true);
  expect(afterState?.run.hand).toEqual(['protagonist']);
  expect(afterState?.run.forced_pending).toEqual([]);
  expect(afterState?.run.indulgence_count).toBe(1);

  // 5. 打開山泉閣並返回地圖，強制縱慾後的行動耗盡狀態保持一致
  const sanquanBtn = page.getByRole('button', { name: /山泉閣/ });
  await sanquanBtn.click();
  const continueBeatBtn = page.getByRole('button', { name: '繼續演出' });
  while (await finishStory(page), await continueBeatBtn.isVisible()) {
    await continueBeatBtn.click();
  }
  await page.getByTestId('place-btn-checkin').click();
  await expect(page.getByTestId('candidate-protagonist')).toHaveCount(0);
  await expect(page.locator('.empty-candidates')).toBeVisible();
  await page.getByRole('button', { name: '關閉', exact: true }).click();
  const backBtn = page.getByRole('button', { name: '返回地圖' });
  await expect(backBtn).toBeVisible();
  await backBtn.click();
  await expect(page.getByTestId('forced-narrative')).toContainText('剩菜');

  // 依然在地圖，推進按鈕仍可推進至下午
  const advanceBtn = page.locator('.phase-actions button');
  await expect(advanceBtn).toBeEnabled();
});
