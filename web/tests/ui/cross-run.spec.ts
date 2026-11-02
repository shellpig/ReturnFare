import { finishStory } from './story-fixture';
import { expect, test, type Page } from './story-fixture';
import { readFileSync } from 'node:fs';
import type { GameSnapshot } from '../../src/core/state-types';

const opening = JSON.parse(readFileSync('../data/opening_choices.json', 'utf8'));
const snapshot = (page: Page) => page.evaluate(() =>
  (window as unknown as { __crossRunGame: { serialize(): GameSnapshot } }).__crossRunGame.serialize(),
);

/**
 * 測試專用起點注入（透過 Playwright 路由攔截 dev server 的 state.ts，正式產品無測試入口）。
 * 依審查建議從可信 D45 afternoon 固定遭遇（d45_encounter）起步，實證遭遇 -> 終局 -> 跨輪完整真實 UI 流轉。
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
          if (override.opening_choice_id !== undefined) {
            base.run.opening_choice_id = override.opening_choice_id;
          }
          if (override.active_encounter) {
            base.run.active_encounter = override.active_encounter;
          }
        }
        const game = __origCreateGame(data, base);
        window.__crossRunGame = game;
        return game;
      }\n`;
    await route.fulfill({ response, body: patchedBody });
  });
}

test('UI cross-run: D45 afternoon encounter -> D45 evening coda -> ending -> clean opening -> D1 -> D2 map', async ({ page }) => {
  await injectStartSnapshot(page);

  // 測試端精準監控 EndingPanel 之 setInterval / clearInterval（間隔 20~40ms 之逐字計時器）
  await page.addInitScript(() => {
    const activeEndingTimers = new Set<number>();
    const origSetInterval = window.setInterval;
    const origClearInterval = window.clearInterval;

    window.setInterval = function (handler: TimerHandler, timeout?: number, ...args: unknown[]) {
      const id = origSetInterval(handler, timeout, ...args);
      if (timeout !== undefined && timeout >= 20 && timeout <= 40) {
        activeEndingTimers.add(id);
      }
      return id;
    } as typeof window.setInterval;

    window.clearInterval = function (id?: unknown) {
      if (typeof id === 'number') {
        activeEndingTimers.delete(id);
      }
      origClearInterval(id as number | undefined);
    } as typeof window.clearInterval;

    (window as unknown as { __endingTimerStatus: () => { activeCount: number } }).__endingTimerStatus = () => ({
      activeCount: activeEndingTimers.size,
    });
  });

  // 注入可信 D45 afternoon 固定遭遇（d45_encounter，stage: intro）
  await page.addInitScript(() => {
    sessionStorage.setItem(
      '__w6e2_snap_override__',
      JSON.stringify({
        day: 45,
        phase: 'afternoon',
        hand: ['protagonist'],
        flags: { final_day: true, invited_none: true },
        choices: { 'd29_pm_invitation::invitation': 'invite_none' },
        slots_placed: { 'd29_pm_invitation::invite_none': true },
        selected_festival_proxy_npc: 'ajie',
        opening_choice_id: 'take_family_album',
        active_encounter: {
          stage: 'intro',
          beat_id: 'd45_encounter',
          round_id: '',
          blocked_slots: 0,
          attempted_card_ids: [],
          visited_round_ids: [],
        },
      }),
    );
  });

  await page.goto('/');

  // 1. D45 afternoon 進入固定遭遇 intro
  const encounterPanel = page.locator('[data-testid="encounter-panel"]');
  await expect(encounterPanel).toBeVisible();

  const introContinue = page.getByTestId('encounter-intro-continue');
  while (await finishStory(page), await introContinue.isVisible()) {
    await introContinue.click();
  }

  const ackBtn = page.getByTestId('encounter-intro-ack');
  await expect(ackBtn).toBeVisible();
  await ackBtn.click();

  // 2. 進入第一回合：點擊主角卡候選按鈕開啟對話框，測試「取消」與「確認」真實 UI 行為
  const candBtn = page.getByTestId('encounter-candidate-protagonist');
  await expect(candBtn).toBeVisible();
  const beforeSelection = await snapshot(page);
  await candBtn.click();

  const cancelRespond = page.getByTestId('dialog-cancel-encounter-respond');
  const confirmRespond = page.getByTestId('dialog-confirm-encounter-respond');
  await expect(cancelRespond).toBeVisible();
  await expect(confirmRespond).toBeVisible();

  // 取消：對話框關閉，遭遇維持
  await cancelRespond.click();
  await expect(cancelRespond).toHaveCount(0);
  await expect(encounterPanel).toBeVisible();
  expect(await snapshot(page)).toEqual(beforeSelection);

  // 再次點選並確認回應
  await candBtn.click();
  await expect(confirmRespond).toBeVisible();
  await confirmRespond.click();

  // 3. d45_encounter 具備 after_finish: advance_phase，自動推進至 D45 evening
  // 遭遇面板消失，舊遭遇對話框與按鈕無殘留
  await expect(encounterPanel).toHaveCount(0);
  await expect(cancelRespond).toHaveCount(0);
  await expect(confirmRespond).toHaveCount(0);
  await expect(page.getByTestId('encounter-result')).toBeVisible();

  // 4. D45 evening 進入 coda
  const phaseExitBtn = page.getByTestId('phase-exit-open');
  await expect(phaseExitBtn).toBeVisible();
  await phaseExitBtn.click();

  const continueCodaBtn = page.getByRole('button', { name: '繼續演出' });
  while (await finishStory(page), await continueCodaBtn.isVisible()) {
    await continueCodaBtn.click();
  }

  // 選擇空手收尾路線
  const emptyHandedBtn = page.getByTestId('choose-btn-empty_handed');
  await expect(emptyHandedBtn).toBeVisible();
  await emptyHandedBtn.click();

  // 推進時段進入 EndingPanel
  const advanceBtn = page.getByRole('button', { name: '推進時段' });
  await expect(advanceBtn).toBeEnabled();
  await advanceBtn.click();

  // 5. 進入 EndingPanel：驗證計時器運作與揭露即時清除
  await expect(page.getByTestId('ending-text')).toBeVisible();
  await expect(page.getByTestId('ending-page')).toBeVisible();

  const getTimerCount = () =>
    page.evaluate(() => (window as unknown as { __endingTimerStatus: () => { activeCount: number } }).__endingTimerStatus().activeCount);

  // 翻閱並揭露頁面直到「完成」
  const ending = (await snapshot(page)).flow.active_ending;
  expect(ending).not.toBeNull();
  let loopGuard = ending!.page_refs.length * 2 + 1;
  while (loopGuard > 0) {
    loopGuard -= 1;
    const completeButton = page.getByRole('button', { name: '完成' });
    if (await completeButton.isVisible()) {
      await completeButton.click();
      break;
    }
    if (await page.locator('[data-ending-typing="true"]').isVisible()) {
      // 逐字輸入中至少存在 1 個活躍 interval
      await expect.poll(getTimerCount).toBeGreaterThanOrEqual(1);
      await page.getByTestId('ending-body').click();
      // 點擊「顯示全文」後當頁揭露，計時器立即清除歸零
      await expect.poll(getTimerCount).toBe(0);
      continue;
    }
    const nextButton = page.getByRole('button', { name: '下一頁' });
    if (await nextButton.isVisible()) {
      await nextButton.click();
      continue;
    }
    throw new Error('結局沒有預期的揭露、翻頁或完成入口');
  }

  // 6. 回到開局畫面：驗證上一輪面板、遭遇、結局文字與計時器全數清除無殘留
  await expect(page.getByRole('heading', { name: opening.screen.title })).toBeVisible();
  await expect(page.getByTestId('ending-text')).toHaveCount(0);
  await expect(page.getByTestId('ending-page')).toHaveCount(0);
  await expect(page.locator('.hand-panel, .map-panel, .location-panel, .encounter-panel')).toHaveCount(0);
  await expect(page.locator('[data-testid="encounter-panel"]')).toHaveCount(0);
  await expect(page.getByRole('button', { name: '推進時段' })).toHaveCount(0);

  // 斷言卸載後計時器維持為 0，舊 callback 不會在開局畫面觸發
  expect(await getTimerCount()).toBe(0);

  // 唯讀斷言：輪數遞增為 2，歷輪結局記錄恰好 1 筆
  const snapAfterComplete = await page.evaluate(
    () => (window as unknown as { __crossRunGame: { serialize: () => { meta: { run_number: number; ending_history: unknown[] } } } }).__crossRunGame.serialize(),
  );
  expect(snapAfterComplete.meta.run_number).toBe(2);
  expect(snapAfterComplete.meta.ending_history).toHaveLength(1);

  // 7. 開局選項真實點選、取消與確認
  const albumOption = opening.opening_choices.find((c: { id: string }) => c.id === 'take_family_album');
  await page.getByRole('button', { name: albumOption.label }).click();

  const cancelDialogBtn = page.getByRole('dialog').getByRole('button', { name: '取消', exact: true });
  const confirmDialogBtn = page.getByRole('dialog').getByRole('button', { name: '確認', exact: true });
  await expect(cancelDialogBtn).toBeVisible();
  await expect(confirmDialogBtn).toBeVisible();

  // 取消：對話框關閉，留在開局
  await cancelDialogBtn.click();
  await expect(cancelDialogBtn).toHaveCount(0);

  // 再次點選並確認進入新一輪
  await page.getByRole('button', { name: albumOption.label }).click();
  await expect(confirmDialogBtn).toBeVisible();
  await confirmDialogBtn.click();

  // 8. 推進 D1 morning -> afternoon -> evening -> night -> D2 morning
  const nextPerformanceBtn = page.getByRole('button', { name: '繼續演出' });
  const advancePhaseBtn = page.getByRole('button', { name: '推進時段' });

  // D1 morning 演出
  while (await finishStory(page), await nextPerformanceBtn.isVisible()) {
    await nextPerformanceBtn.click();
  }
  await expect(advancePhaseBtn).toBeEnabled();
  await advancePhaseBtn.click();

  // D1 afternoon 演出
  while (await finishStory(page), await nextPerformanceBtn.isVisible()) {
    await nextPerformanceBtn.click();
  }
  await expect(advancePhaseBtn).toBeEnabled();
  await advancePhaseBtn.click();

  // D1 evening 演出
  while (await finishStory(page), await nextPerformanceBtn.isVisible()) {
    await nextPerformanceBtn.click();
  }
  await expect(advancePhaseBtn).toBeEnabled();
  await advancePhaseBtn.click();

  // D1 night 演出（走廊 fixed 後以「結束今晚」換日）
  while (await finishStory(page), await nextPerformanceBtn.isVisible()) {
    await nextPerformanceBtn.click();
  }
  const endNightBtn = page.getByRole('button', { name: '結束今晚' });
  await expect(endNightBtn).toBeVisible();
  await endNightBtn.click();

  // 9. 成功抵達 D2 晨間地圖
  await expect(page.locator('header')).toContainText('第 2 天');
  await expect(page.locator('.map-panel')).toBeVisible();
  await expect(page.getByRole('button', { name: '山泉閣' })).toBeEnabled();
  await expect(page.locator('.location-panel, .encounter-panel, .ending-panel, [role="dialog"], dialog')).toHaveCount(0);
  await expect(page.getByTestId('encounter-result')).toHaveCount(0);
  expect(await getTimerCount()).toBe(0);

  // 最終純唯讀斷言確認
  const finalSnap = await page.evaluate(
    () => (window as unknown as { __crossRunGame: { serialize: () => { run: { day: number; phase: string; opening_choice_id: string } } } }).__crossRunGame.serialize(),
  );
  expect(finalSnap.run.day).toBe(2);
  expect(finalSnap.run.phase).toBe('morning');
  expect(finalSnap.run.opening_choice_id).toBe('take_family_album');
});
