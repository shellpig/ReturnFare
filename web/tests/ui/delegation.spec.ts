import { finishStory } from './story-fixture';
import { expect, test, type Page } from './story-fixture';

type TestWindow = {
  __testGame?: {
    serialize: () => {
      run: {
        hand: string[];
        action_spent: boolean;
        delegates_used_today: Record<string, boolean>;
        pending_delegation_reports: Array<{
          due_day: number;
          beat_id: string;
          slot_id: string;
          person_id: string;
        }>;
        choices: Record<string, string>;
      };
      meta: {
        delegation_tutorial_seen: boolean;
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
    flags?: Record<string, boolean>;
    delegation_tutorial_seen?: boolean;
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
        const override = JSON.parse(sessionStorage.getItem('__w6c_snap_override__') || 'null');
        if (override) {
          base.flow.mode = 'run';
          base.run.day = override.day;
          base.run.phase = override.phase;
          base.run.hand = override.hand ?? ['protagonist'];
          if (override.flags) {
            base.run.flags = { ...base.run.flags, ...override.flags };
          }
          if (override.night_location_chosen) {
            base.run.night_location_chosen = override.night_location_chosen;
          }
          if (override.delegation_tutorial_seen !== undefined) {
            base.meta.delegation_tutorial_seen = override.delegation_tutorial_seen;
          }
        }
        const game = __origCreateGame(data, override ? base : initialState);
        window.__testGame = game;
        return game;
      }\n`;
    await route.fulfill({ response, body: patchedBody });
  });
  await page.addInitScript((value) => {
    sessionStorage.setItem('__w6c_snap_override__', JSON.stringify(value));
  }, override);
}

test('W6-C UI: D17 下午委託阿珠（隔日上午回報）完整生命週期 — 預覽、取消不變、確認、隔日晨報', async ({
  page,
}) => {
  await page.setViewportSize({ width: 1280, height: 800 });
  await injectStartSnapshot(page, {
    day: 17,
    phase: 'afternoon',
    hand: ['protagonist', 'npc_azhu'], // 已取得阿珠，無阿財
    delegation_tutorial_seen: true, // 教學已看過，避免阻擋流程
  });
  await page.goto('/');

  // 1. 點選山泉閣（sanquan）白天地點
  const sanquanBtn = page.getByRole('button', { name: /山泉閣/ });
  await expect(sanquanBtn).toBeVisible();
  await sanquanBtn.click();

  // 點選「繼續演出」直到所有新事件播完，進入卡槽階段
  const continueBeatBtn = page.getByRole('button', { name: '繼續演出' });
  while (await finishStory(page), await continueBeatBtn.isVisible()) {
    await continueBeatBtn.click();
  }

  // 2. 委託槽位 ask_azhu 可見（因持有 npc_azhu），而 ask_acai 未出現（未持有 npc_acai）
  const azhuSlot = page.locator('[data-testid="slot-ask_azhu"]');
  await expect(azhuSlot).toBeVisible();
  const acaiSlot = page.locator('[data-testid="slot-ask_acai"]');
  await expect(acaiSlot).toHaveCount(0);

  // 確信無通用選擇按鈕繞過委託預覽
  await expect(page.locator('[data-testid="choose-btn-ask_azhu"]')).toHaveCount(0);

  // 3. 點選委託按鈕打開 DelegationPreview 彈窗
  const delegateBtn = page.locator('[data-testid="delegate-btn-ask_azhu"]');
  await expect(delegateBtn).toBeVisible();
  await delegateBtn.click();

  const previewDialog = page.locator('.delegation-preview-dialog');
  await expect(previewDialog).toBeVisible();

  // 4. 驗證預覽內容：taskTitle, data preview, data tendency, 隔日上午回報
  await expect(previewDialog.getByTestId('delegation-task-title')).toContainText('叔叔的舊藥單');
  await expect(previewDialog.getByTestId('delegation-preview')).toContainText('請她在診所那邊查這份處方的來源。');
  await expect(previewDialog.getByTestId('delegation-timing')).toHaveText('隔日上午回報');
  await expect(previewDialog.getByTestId('delegation-tendency')).toContainText('傾向：範圍較廣，隔日上午才回報；而且她很怕。');

  // Show NO full gain/lose/relation/report body
  await expect(previewDialog).not.toContainText('阿源叔早在二十年前');
  await expect(previewDialog).not.toContainText('doc_prescription');
  await expect(previewDialog).not.toContainText('info_uncle_treated_20y');

  // 候選清單只出現已取得的阿珠，未取得的阿財不出現
  await expect(previewDialog.locator('[data-testid="candidate-npc_azhu"]')).toBeVisible();
  await expect(previewDialog.locator('[data-testid="candidate-npc_acai"]')).toHaveCount(0);

  // 5. 取消預覽：快照狀態零變化
  const snapBeforeCancel = await page.evaluate(() =>
    JSON.stringify((window as unknown as TestWindow).__testGame?.serialize()),
  );
  await page.locator('[data-testid="dialog-cancel-delegation"]').click();
  await expect(previewDialog).toHaveCount(0);

  const snapAfterCancel = await page.evaluate(() =>
    JSON.stringify((window as unknown as TestWindow).__testGame?.serialize()),
  );
  expect(snapAfterCancel).toBe(snapBeforeCancel);

  // 6. 重新開啟並確認委託
  await delegateBtn.click();
  await expect(previewDialog).toBeVisible();
  await page.locator('[data-testid="dialog-confirm-delegation"]').click();
  await expect(previewDialog).toHaveCount(0);

  // 7. 放置當下文字顯示，手牌阿珠顯示（今日已受託）
  const actionResult = page.locator('[data-testid="action-result"]');
  await expect(actionResult).toBeVisible();
  await expect(actionResult).toContainText('阿珠眼神閃爍地接下了請求');

  const azhuHandCard = page.locator('[data-testid="card-npc_azhu"]');
  await expect(azhuHandCard).toContainText('（今日已受託）');

  // 8. 返回地圖，經傍晚、夜間推進至 D18 上午
  const backBtn = page.getByRole('button', { name: '返回地圖' });
  await backBtn.click();

  // 推進至傍晚
  const advanceBtn = page.getByRole('button', { name: /推進時段/ });
  await expect(advanceBtn).toBeEnabled();
  await advanceBtn.click();

  // 傍晚演出（繼續演出）
  const continueEveningBtn = page.getByRole('button', { name: '繼續演出' });
  while (await finishStory(page), await continueEveningBtn.isVisible()) {
    await continueEveningBtn.click();
  }

  // 推進至夜晚
  await expect(advanceBtn).toBeEnabled();
  await advanceBtn.click();

  // 夜晚固定演出（繼續演出）
  const continueNightBtn = page.getByRole('button', { name: '繼續演出' });
  while (await finishStory(page), await continueNightBtn.isVisible()) {
    await continueNightBtn.click();
  }

  // 夜間主按鈕（直接睡）推進至 D18 上午
  const sleepBtn = page.getByRole('button', { name: /直接睡|推進時段/ });
  await expect(sleepBtn).toBeEnabled();
  await sleepBtn.click();

  // 9. D18 上午：委託隔日晨報文字在常規 UI 顯示（data-testid="delegation-report"）
  const reportBanner = page.locator('[data-testid="delegation-report"]');
  await expect(reportBanner).toBeVisible();
  await expect(reportBanner).toContainText('隔天清晨，阿珠特地將你拉到無人的防火巷拐角');
  await expect(reportBanner).toContainText('阿源叔早在二十年前，就已經在我們診所接受一模一樣的特殊療程了。');

  // 回報隊列已清空，且獲得處方與知識
  const finalSnap = await page.evaluate(
    () => (window as unknown as TestWindow).__testGame?.serialize(),
  );
  expect(finalSnap?.run.pending_delegation_reports).toEqual([]);
  expect(finalSnap?.run.hand).toContain('doc_prescription');
  expect(finalSnap?.run.hand).toContain('info_uncle_treated_20y');
});

test('W6-C UI: 首次取得人物卡彈出委託教學彈窗，關閉後寫入 meta 且不重複出現；零人物卡無教學', async ({
  page,
}) => {
  await page.setViewportSize({ width: 1280, height: 800 });

  // 1. 零人物卡進入 D17 上午：無教學彈窗
  await injectStartSnapshot(page, {
    day: 17,
    phase: 'morning',
    hand: ['protagonist'],
    delegation_tutorial_seen: false,
  });
  await page.goto('/');

  const tutorialDialog = page.locator('.delegation-tutorial-dialog');
  await expect(tutorialDialog).toHaveCount(0);

  // 2. 點擊山泉閣觸發 d17_morning_phone，獲得第一張人物卡阿婕
  const sanquanBtn = page.getByRole('button', { name: /山泉閣/ });
  await expect(sanquanBtn).toBeVisible();
  await sanquanBtn.click();

  // 3. 首次獲得人物卡時，教學彈窗彈出
  await expect(tutorialDialog).toBeVisible();
  await expect(tutorialDialog.locator('#delegation-tutorial-title')).toHaveText('委託');
  await expect(tutorialDialog.locator('.tutorial-text')).toHaveText(
    '你拿到了第一張人物卡。你可以委託他們代你去做某些事——委託不佔用你的行動格，一天只能委託同一人一次，回報有些立即、有些要等到隔天上午。',
  );

  // 彈窗顯示期間，meta.delegation_tutorial_seen 仍為 false（不可在發卡當下便寫入）
  const metaBeforeDismiss = await page.evaluate(
    () => (window as unknown as TestWindow).__testGame?.serialize().meta.delegation_tutorial_seen,
  );
  expect(metaBeforeDismiss).toBe(false);

  // 4. 點選確定關閉教學彈窗
  const confirmTutorialBtn = page.locator('[data-testid="dialog-confirm-delegation-tutorial"]');
  await expect(confirmTutorialBtn).toBeVisible();
  await confirmTutorialBtn.click();
  await expect(tutorialDialog).toHaveCount(0);

  // 關閉後，meta.delegation_tutorial_seen 轉為 true
  const metaAfterDismiss = await page.evaluate(
    () => (window as unknown as TestWindow).__testGame?.serialize().meta.delegation_tutorial_seen,
  );
  expect(metaAfterDismiss).toBe(true);

  // 點選「繼續演出」完成 beat
  const continueBeatBtn = page.getByRole('button', { name: '繼續演出' });
  while (await finishStory(page), await continueBeatBtn.isVisible()) {
    await continueBeatBtn.click();
  }

  // 5. 推進時段至下午，委託阿婕（immediate 立即回報案例）
  const backBtn = page.getByRole('button', { name: '返回地圖' });
  await backBtn.click();

  const advanceBtn = page.getByRole('button', { name: /推進時段/ });
  await advanceBtn.click();

  // 下午再次進入山泉閣
  await sanquanBtn.click();
  while (await finishStory(page), await continueBeatBtn.isVisible()) {
    await continueBeatBtn.click();
  }

  // 教學彈窗絕不再次出現
  await expect(tutorialDialog).toHaveCount(0);

  // 委託阿婕
  const ajieSlot = page.locator('[data-testid="slot-ask_ajie"]');
  await expect(ajieSlot).toBeVisible();

  const delegateAjieBtn = page.locator('[data-testid="delegate-btn-ask_ajie"]');
  await delegateAjieBtn.click();

  const previewDialog = page.locator('.delegation-preview-dialog');
  await expect(previewDialog).toBeVisible();
  await expect(previewDialog.getByTestId('delegation-timing')).toHaveText('立即回報');

  await page.locator('[data-testid="dialog-confirm-delegation"]').click();
  await expect(previewDialog).toHaveCount(0);

  // 立即獲得結果與處方卡
  const actionResult = page.locator('[data-testid="action-result"]');
  await expect(actionResult).toBeVisible();
  await expect(actionResult).toContainText('阿婕動作俐落');

  const ajieHandCard = page.locator('[data-testid="card-npc_ajie"]');
  await expect(ajieHandCard).toContainText('（今日已受託）');
});
