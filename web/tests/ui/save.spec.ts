import { expect, test, finishStory, type Page } from './story-fixture';
import { readFileSync } from 'node:fs';
import type { GameSnapshot } from '../../src/core/state-types';
import { createInitialSnapshot } from '../../src/core/run-initialization';
import { encodeSave } from '../../src/save/codec';

const opening = JSON.parse(readFileSync('../data/opening_choices.json', 'utf8'));
const endings = JSON.parse(readFileSync('../data/endings.json', 'utf8'));
const refuseEnding = endings.find((e: { id: string }) => e.id === 'ending_refuse_boarding');
const refuseOption = opening.opening_choices.find((c: { id: string }) => c.id === 'refuse_boarding');
const [firstEndingPage, secondEndingPage] = refuseEnding.first_seen.pages as { text: string }[];

/**
 * 測試專用遊戲實體觀測接點（透過 Playwright 路由攔截 dev server 的 state.ts，正式產品無測試入口）。
 * 嚴格遵循原 initialState 參數，不更動生產行為。
 */
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

async function getGameSnapshot(page: Page): Promise<GameSnapshot> {
  return page.evaluate(() => (window as unknown as { __testGame: { serialize(): GameSnapshot } }).__testGame.serialize());
}

async function getRawStorage(page: Page): Promise<{ auto: string | null; manual: string | null }> {
  return page.evaluate(() => ({
    auto: window.localStorage.getItem('returnfare.save.auto'),
    manual: window.localStorage.getItem('returnfare.save.manual'),
  }));
}

test.describe('W7-B2 Local Storage & Save UI', () => {
  test('1. Playable path: start album -> D2 placement -> save -> reopen same context -> continue & manual load', async ({
    context,
    page,
  }) => {
    await setupGameInspectionRoute(page);
    await page.goto('/');
    await expect(page.getByRole('heading', { name: opening.screen.title })).toBeVisible();

    // 1. 開局選擇舊相簿
    const album = opening.opening_choices[0];
    await page.getByRole('button', { name: album.label }).click();
    await page.getByRole('dialog').getByRole('button', { name: '確認', exact: true }).click();

    await finishStory(page);
    const advanceBtn = page.getByRole('button', { name: '推進時段' });
    const nextBtn = page.getByRole('button', { name: '繼續演出' });

    // 2. 推進走過第 1 天（D1 morning -> afternoon -> evening -> night -> D2 morning）
    await expect(advanceBtn).toBeEnabled();
    await advanceBtn.click(); // -> D1 pm

    await finishStory(page);
    await expect(advanceBtn).toBeEnabled();
    await advanceBtn.click(); // -> D1 eve

    await finishStory(page);
    await nextBtn.click();
    await finishStory(page);
    await nextBtn.click();
    await finishStory(page);
    await expect(advanceBtn).toBeEnabled();
    await advanceBtn.click(); // -> D1 night

    // 夜間結束今晚
    await finishStory(page);
    const endNight = page.getByRole('button', { name: '結束今晚' });
    await expect(endNight).toBeVisible();
    await endNight.click();

    // 3. 抵達第 2 天上午（D2 morning）
    await expect(page.locator('header')).toContainText('第 2 天');
    await expect(page.locator('header')).toContainText('上午');

    // 推進到 D2 afternoon 進行放置
    const phaseAdvanceBtn = page.locator('.phase-actions button');
    await expect(phaseAdvanceBtn).toBeEnabled();
    await phaseAdvanceBtn.click(); // -> D2 afternoon
    await expect(page.locator('header')).toContainText('下午');

    // 4. 進入山泉閣並在 work 槽放置主角卡
    const sanquanBtn = page.getByRole('button', { name: /山泉閣/ });
    await expect(sanquanBtn).toBeVisible();
    await sanquanBtn.click();

    // 演出推進至卡槽階段
    await finishStory(page);
    await nextBtn.click();

    const workSlot = page.locator('[data-testid="slot-work"]');
    await expect(workSlot).toBeVisible();
    await workSlot.click();

    // 在選卡彈窗中選取主角卡
    const pickerDialog = page.locator('dialog.card-picker-dialog');
    await expect(pickerDialog).toBeVisible();
    const candidateBtn = pickerDialog.locator('[data-testid="candidate-protagonist"]');
    await expect(candidateBtn).toBeVisible();
    await candidateBtn.click();
    await expect(pickerDialog).not.toBeVisible();

    // 驗證放置成功文字
    const actionResultBox = page.locator('[data-testid="action-result"]');
    await expect(actionResultBox).toBeVisible();

    // 返回地圖
    await page.getByRole('button', { name: '返回地圖' }).click();

    // 驗證 live 快照真實放置與卡片帳目狀態
    const liveBeforeSave = await getGameSnapshot(page);
    expect(liveBeforeSave).not.toBeNull();
    expect(liveBeforeSave.run.day).toBe(2);
    expect(liveBeforeSave.run.phase).toBe('afternoon');
    expect(liveBeforeSave.run.action_spent).toBe(true);
    expect(liveBeforeSave.run.slots_placed['d2_pm_work::work']).toBe(true);
    expect(liveBeforeSave.run.hand).toContain('protagonist');
    expect(liveBeforeSave.run.hand).toContain('item_family_album');

    // 5. 點擊「手動存檔」
    await page.getByTestId('manual-save-btn').click();
    await expect(page.getByTestId('save-status')).toHaveText('存檔成功');
    const manualSummaryText = await page.getByTestId('manual-slot-summary').innerText();
    expect(manualSummaryText).toContain('手動存檔：202');

    const savedSnap = await getGameSnapshot(page);

    // 6. 關閉頁面，並在同一個 browser context 重新開啟
    await page.close();
    const page2 = await context.newPage();
    try {
      await setupGameInspectionRoute(page2);
      await page2.goto('/');

      // 驗證啟動時顯示「繼續進度」橫幅
      const continueBtn = page2.getByTestId('continue-auto-btn');
      await expect(continueBtn).toBeVisible();
      await continueBtn.click();

      // 驗證恢復至第 2 天下午，完整快照完全一致
      const continuedSnap = await getGameSnapshot(page2);
      expect(continuedSnap).toEqual(savedSnap);
      await expect(page2.locator('header')).toContainText('第 2 天');
      await expect(page2.locator('header')).toContainText('下午');

      // 驗證手動讀取
      await page2.getByTestId('manual-load-btn').click();
      const confirmBtn = page2.getByTestId('save-dialog-confirm-btn');
      await expect(confirmBtn).toBeVisible();
      await confirmBtn.click();
      await expect(page2.getByTestId('save-status')).toHaveText('讀取成功');

      const manualLoadedSnap = await getGameSnapshot(page2);
      expect(manualLoadedSnap).toEqual(savedSnap);

      // 驗證手動讀取後 auto 槽位已同步至還原快照（再次開新頁面點繼續仍為此進度）
      await page2.close();
      const page3 = await context.newPage();
      try {
        await setupGameInspectionRoute(page3);
        await page3.goto('/');
        const continueBtn3 = page3.getByTestId('continue-auto-btn');
        await expect(continueBtn3).toBeVisible();
        await continueBtn3.click();
        const page3Snap = await getGameSnapshot(page3);
        expect(page3Snap).toEqual(savedSnap);
      } finally {
        await page3.close();
      }
    } finally {
      if (!page2.isClosed()) {
        await page2.close();
      }
    }
  });

  test('2. Opening mode restore: fresh opening save and restore', async ({ browser }) => {
    const context = await browser.newContext();
    try {
      const page = await context.newPage();
      await setupGameInspectionRoute(page);
      await page.goto('/');
      await expect(page.getByRole('heading', { name: opening.screen.title })).toBeVisible();

      // 在開局階段手動存檔
      await page.getByTestId('manual-save-btn').click();
      await expect(page.getByTestId('save-status')).toHaveText('存檔成功');
      const openingSnap = await getGameSnapshot(page);

      // 重開同 context 頁面
      await page.close();
      const page2 = await context.newPage();
      try {
        await setupGameInspectionRoute(page2);
        await page2.goto('/');

        // 點擊讀取手動檔
        await page2.getByTestId('manual-load-btn').click();
        const confirmBtn = page2.getByTestId('save-dialog-confirm-btn');
        await expect(confirmBtn).toBeVisible();
        await confirmBtn.click();
        await expect(page2.getByTestId('save-status')).toHaveText('讀取成功');

        // 驗證完整快照完全一致，且處於開局選擇頁面
        const restoredSnap = await getGameSnapshot(page2);
        expect(restoredSnap).toEqual(openingSnap);
        await expect(page2.getByRole('heading', { name: opening.screen.title })).toBeVisible();
        await expect(page2.getByRole('button', { name: opening.opening_choices[0].label })).toBeVisible();
      } finally {
        await page2.close();
      }
    } finally {
      await context.close();
    }
  });

  test('3. Export download and import into second isolated context with nonempty cross-run meta', async ({
    browser,
  }) => {
    const context1 = await browser.newContext();
    try {
      const page1 = await context1.newPage();
      await setupGameInspectionRoute(page1);

      // 先啟動取得真實引擎產生的基礎快照，再注入非空跨輪 meta 與 D2 狀態
      await page1.goto('/');
      await expect(page1.getByRole('heading', { name: opening.screen.title })).toBeVisible();
      const baseSnap = await getGameSnapshot(page1);
      baseSnap.flow.mode = 'run';
      baseSnap.run.day = 2;
      baseSnap.run.phase = 'morning';
      baseSnap.run.opening_choice_id = 'take_family_album';
      baseSnap.run.hand = ['protagonist', 'item_family_album'];
      baseSnap.meta.run_number = 2;
      baseSnap.meta.ending_history = [
        {
          run_number: 1,
          ending_id: 'ending_replaced',
          opening_choice_id: 'take_family_album',
          ended_day: 45,
          ended_phase: 'evening',
          partner_variant: 'none',
          livelihood_variant: 'none_low',
          inn_appearance_variant: 'none',
          festival_proxy_npc: 'ajie',
          knowledge_gained_this_run: [],
        },
      ];
      baseSnap.meta.knowledge = { k_forty_something: true };
      baseSnap.meta.night_locations_seen = { n_corridor: true };
      baseSnap.meta.day_locations_visited = { sanquan: true };

      // 將具備真實非空跨輪 meta 的存檔注入 context1 的 localStorage
      await page1.evaluate((snap) => {
        window.localStorage.setItem(
          'returnfare.save.auto',
          JSON.stringify({
            format: 'returnfare-web',
            version: 1,
            saved_at: '2026-11-01T12:00:00.000Z',
            state: snap,
          }),
        );
      }, baseSnap);

      // 重新整理以觸發繼續進度
      await page1.reload();
      const continueBtn = page1.getByTestId('continue-auto-btn');
      await expect(continueBtn).toBeVisible();
      await continueBtn.click();

      // 驗證 context1 已載入該快照
      const live1 = await getGameSnapshot(page1);
      expect(live1.meta.run_number).toBe(2);
      expect(live1.meta.ending_history).toHaveLength(1);
      expect(live1.run.day).toBe(2);

      await page1.getByTestId('manual-save-btn').click();
      const rawBeforeExport = await getRawStorage(page1);
      expect(rawBeforeExport.auto).not.toBeNull();
      expect(rawBeforeExport.manual).not.toBeNull();

      // 點擊匯出存檔並攔截下載檔案
      const downloadPromise = page1.waitForEvent('download');
      await page1.getByTestId('export-btn').click();
      const download = await downloadPromise;
      const downloadPath = await download.path();
      expect(downloadPath).toBeTruthy();

      // 斷言：匯出下載操作未對當前 live Game 與 localStorage 造成任何副作用
      const liveAfterExport = await getGameSnapshot(page1);
      const rawAfterExport = await getRawStorage(page1);
      expect(liveAfterExport).toEqual(live1);
      expect(rawAfterExport).toEqual(rawBeforeExport);

      const downloadedText = readFileSync(downloadPath!, 'utf8');
      const parsedSave = JSON.parse(downloadedText);
      expect(parsedSave.format).toBe('returnfare-web');
      expect(parsedSave.version).toBe(1);
      expect(parsedSave.state.meta.run_number).toBe(2);
      expect(parsedSave.state.meta.ending_history).toHaveLength(1);

      // 在完全獨立的 context2 匯入此檔案
      const context2 = await browser.newContext();
      try {
        const page2 = await context2.newPage();
        await setupGameInspectionRoute(page2);
        await page2.goto('/');

        // 初始為開局頁面
        await expect(page2.getByRole('heading', { name: opening.screen.title })).toBeVisible();

        // 上傳檔案
        await page2.getByTestId('manual-save-btn').click();
        const manualBeforeImport = (await getRawStorage(page2)).manual;
        expect(manualBeforeImport).not.toBeNull();
        await page2.getByTestId('import-file-input').setInputFiles(downloadPath!);

        // 確認彈窗出現
        await expect(page2.getByRole('dialog')).toBeVisible();
        await page2.getByTestId('save-dialog-confirm-btn').click();
        await expect(page2.getByTestId('save-status')).toHaveText('匯入成功');

        // 斷言：context2 還原之快照與 context1 完全一致，包含非空跨輪 meta
        const live2 = await getGameSnapshot(page2);
        expect(live2).toEqual(live1);
        expect(live2.meta.run_number).toBe(2);
        expect(live2.meta.ending_history).toEqual(live1.meta.ending_history);
        expect((await getRawStorage(page2)).manual).toBe(manualBeforeImport);

        // 斷言：context1 的 live 遊戲與存檔依然絲毫未受污染
        expect(await getGameSnapshot(page1)).toEqual(live1);
        expect(await getRawStorage(page1)).toEqual(rawBeforeExport);
      } finally {
        await context2.close();
      }
    } finally {
      await context1.close();
    }
  });

  test('4. Cancel import / bad JSON / newer version preserves live game and slots', async ({
    page,
  }) => {
    await setupGameInspectionRoute(page);
    await page.goto('/');
    const album = opening.opening_choices[0];
    await page.getByRole('button', { name: album.label }).click();
    await page.getByRole('dialog').getByRole('button', { name: '確認', exact: true }).click();
    await expect(page.locator('header')).toContainText('第 1 天');

    await page.getByTestId('manual-save-btn').click();
    const liveBefore = await getGameSnapshot(page);
    const rawBefore = await getRawStorage(page);
    expect(rawBefore.auto).not.toBeNull();
    expect(rawBefore.manual).not.toBeNull();

    // 1. 取消匯入：上傳有效快照但點取消
    const validJson = JSON.stringify({
      format: 'returnfare-web',
      version: 1,
      saved_at: '2026-11-01T12:00:00.000Z',
      state: liveBefore,
    });

    await page.getByTestId('import-file-input').setInputFiles({
      name: 'save.json',
      mimeType: 'application/json',
      buffer: Buffer.from(validJson),
    });

    await expect(page.getByRole('dialog')).toBeVisible();
    await page.getByTestId('save-dialog-cancel-btn').click();
    await expect(page.getByRole('dialog')).toHaveCount(0);

    // 斷言：取消匯入後，live 快照與 localStorage 原樣不變
    expect(await getGameSnapshot(page)).toEqual(liveBefore);
    expect(await getRawStorage(page)).toEqual(rawBefore);

    // 2. 損毀 JSON
    await page.getByTestId('import-file-input').setInputFiles({
      name: 'corrupted.json',
      mimeType: 'application/json',
      buffer: Buffer.from('{{{ broken json'),
    });
    await expect(page.getByTestId('save-error')).toContainText('JSON 解析失敗');

    // 斷言：損毀 JSON 後，live 快照與 localStorage 原樣不變
    expect(await getGameSnapshot(page)).toEqual(liveBefore);
    expect(await getRawStorage(page)).toEqual(rawBefore);

    // 3. 較新未支援版號
    const newerVersionJson = JSON.stringify({
      format: 'returnfare-web',
      version: 999,
      saved_at: '2099-01-01T00:00:00.000Z',
      state: {},
    });
    await page.getByTestId('import-file-input').setInputFiles({
      name: 'newer.json',
      mimeType: 'application/json',
      buffer: Buffer.from(newerVersionJson),
    });
    await expect(page.getByTestId('save-error')).toContainText('unsupported_version');

    // 斷言：未支援版號後，live 快照與 localStorage 原樣不變
    expect(await getGameSnapshot(page)).toEqual(liveBefore);
    expect(await getRawStorage(page)).toEqual(rawBefore);
  });

  test('5. Manual save overwrite cancellation preserves previous file', async ({ page }) => {
    await setupGameInspectionRoute(page);
    await page.goto('/');
    const album = opening.opening_choices[0];
    await page.getByRole('button', { name: album.label }).click();
    await page.getByRole('dialog').getByRole('button', { name: '確認', exact: true }).click();

    // 第一次手動存檔
    await page.getByTestId('manual-save-btn').click();
    await expect(page.getByTestId('save-status')).toHaveText('存檔成功');
    const firstManualSummary = await page.getByTestId('manual-slot-summary').innerText();
    const rawBeforeOverwrite = await getRawStorage(page);

    // 推進到下午
    await finishStory(page);
    const advance = page.getByRole('button', { name: '推進時段' });
    await expect(advance).toBeEnabled();
    await advance.click();
    await expect(page.locator('header')).toContainText('下午');

    // 再次點手動存檔，彈出覆蓋確認對話框
    await page.getByTestId('manual-save-btn').click();
    await expect(page.getByRole('dialog')).toBeVisible();
    await expect(page.getByText('確認覆蓋手動存檔')).toBeVisible();

    // 點擊取消
    await page.getByTestId('save-dialog-cancel-btn').click();
    await expect(page.getByRole('dialog')).toHaveCount(0);

    // 斷言：手動存檔摘要與原始字串完全維持取消前的內容
    const currentSummary = await page.getByTestId('manual-slot-summary').innerText();
    expect(currentSummary).toBe(firstManualSummary);
    const rawAfterCancel = await getRawStorage(page);
    expect(rawAfterCancel.manual).toBe(rawBeforeOverwrite.manual);
  });

  test('6. Mobile viewport verifies controls reachable, real chooser/download and no #boot overlay', async ({
    page,
  }) => {
    await page.setViewportSize({ width: 390, height: 844 });
    await setupGameInspectionRoute(page);
    await page.goto('/');

    // 確保載入動畫已完全就緒並移除 #boot 遮罩
    await expect(page.locator('#boot')).toHaveCount(0);

    const savePanel = page.locator('.save-panel');
    await expect(savePanel).toBeVisible();

    const exportBtn = page.getByTestId('export-btn');
    const importBtn = page.getByTestId('import-btn');
    await expect(exportBtn).toBeVisible();
    await expect(importBtn).toBeVisible();

    // 實際觸發匯出下載事件
    const downloadPromise = page.waitForEvent('download');
    await exportBtn.click();
    const download = await downloadPromise;
    const downloadPath = await download.path();
    expect(downloadPath).toBeTruthy();

    // 實際觸發匯入檔案選取事件並開啟彈窗
    const fileChooserPromise = page.waitForEvent('filechooser');
    await importBtn.click();
    const fileChooser = await fileChooserPromise;
    await fileChooser.setFiles(downloadPath!);

    await expect(page.getByRole('dialog')).toBeVisible();
    await page.getByTestId('save-dialog-cancel-btn').click();
    await expect(page.getByRole('dialog')).toHaveCount(0);

    // 驗證 390px 寬度下無水平破版
    const hasNoOverflow = await page.evaluate(() => {
      return document.documentElement.scrollWidth <= window.innerWidth;
    });
    expect(hasNoOverflow).toBe(true);

    await page.screenshot({ path: '../_qa/web/W7-B/mobile-save-panel.png' });
  });

  test('7. Production autosave failure UI when setItem throws & imported game auto-write failure', async ({
    browser,
  }) => {
    const context = await browser.newContext();
    try {
      const page = await context.newPage();
      await setupGameInspectionRoute(page);

      // 先種入一份既有合法自動存檔字串，用於驗證失敗時舊檔原樣保留
      // （須為可解碼的合法存檔；壞檔／不支援版本會暫停 autosave，見測試 9）
      const initialOldRaw = encodeSave(createInitialSnapshot(), '2026-11-01T00:00:00.000Z');

      await page.addInitScript(({ raw }) => {
        window.localStorage.setItem('returnfare.save.auto', raw);
      }, { raw: initialOldRaw });

      await page.goto('/');
      await expect(page.getByRole('heading', { name: opening.screen.title })).toBeVisible();

      // 模擬瀏覽器 localStorage 寫入配額用盡或受限
      await page.evaluate(() => {
        Storage.prototype.setItem = () => {
          throw new Error('QuotaExceededError: LocalStorage quota exceeded');
        };
      });

      // 進行一次會觸發自動存檔的動作（選擇開局舊相簿）
      const album = opening.opening_choices[0];
      await page.getByRole('button', { name: album.label }).click();
      await page.getByRole('dialog').getByRole('button', { name: '確認', exact: true }).click();

      // 斷言：錯誤橫幅清楚呈現自動存檔失敗原因，且不被後續動作靜默清除
      await expect(page.getByTestId('save-error')).toBeVisible();
      await expect(page.getByTestId('save-error')).toContainText('寫入儲存空間失敗');
      await expect(page.getByTestId('save-error')).toContainText('QuotaExceededError');

      // 斷言：記憶體中遊戲依然可正常繼續遊玩
      await expect(page.locator('header')).toContainText('第 1 天');

      // 斷言：LocalStorage 中的舊存檔字串原樣保留，未被半套破壞
      const currentRaw = await page.evaluate(() => window.localStorage.getItem('returnfare.save.auto'));
      expect(currentRaw).toBe(initialOldRaw);

      // 模擬匯入存檔時，記憶體替換成功但自動存檔寫入失敗的場景
      const validImportJson = JSON.stringify({
        format: 'returnfare-web',
        version: 1,
        saved_at: '2026-11-01T12:00:00.000Z',
        state: {
          flow: { mode: 'run', active_ending: null },
          run: {
            day: 3, phase: 'morning', opening_choice_id: 'take_family_album',
            knowledge_at_start: {}, selected_festival_proxy_npc: null,
            action_spent: false, actions_spent_ahead: 0, hand: ['protagonist'],
            madness_clock: {}, _madness_counter: 0, beats_entered: {},
            slots_placed: {}, choices: {}, flags: {}, switches: {},
            switch_progress: {}, relations: {}, npc_action_counts: {},
            night_location_chosen: '', night_sleep_pending: false,
            indulgence_count: 0, madness_cards_cleared: 0, forced_pending: [],
            delegates_used_today: {}, pending_delegation_reports: [],
            active_encounter: {},
          },
          meta: {
            knowledge: {}, night_locations_seen: {}, night_once_beats_seen: {},
            day_locations_visited: {}, delegation_tutorial_seen: false,
            run_number: 1, ending_history: [], loop_persistent_item_ids: {},
          },
        },
      });

      await page.getByTestId('import-file-input').setInputFiles({
        name: 'import_d3.json',
        mimeType: 'application/json',
        buffer: Buffer.from(validImportJson),
      });

      await expect(page.getByRole('dialog')).toBeVisible();
      await page.getByTestId('save-dialog-confirm-btn').click();

      // 斷言：替換成功後進到第 3 天，但自動存檔失敗的錯誤訊息依然保留可見
      await expect(page.locator('header')).toContainText('第 3 天');
      await expect(page.getByTestId('save-error')).toBeVisible();
      await expect(page.getByTestId('save-error')).toContainText('寫入儲存空間失敗');

      // 斷言：舊檔案依然維持不變
      const currentRawAfterImport = await page.evaluate(() => window.localStorage.getItem('returnfare.save.auto'));
      expect(currentRawAfterImport).toBe(initialOldRaw);
    } finally {
      await context.close();
    }
  });

  test('8. Ending nonzero-page restore with page index, revealed state, and history intact', async ({
    browser,
  }) => {
    const context = await browser.newContext();
    try {
      const page = await context.newPage();
      await setupGameInspectionRoute(page);

      // 種入第 2 輪 meta 紀錄以解鎖不上車選項
      await page.goto('/');
      await expect(page.getByRole('heading', { name: opening.screen.title })).toBeVisible();
      const initSnap = await getGameSnapshot(page);
      initSnap.meta.run_number = 2;
      initSnap.meta.ending_history = [
        {
          run_number: 1,
          ending_id: 'ending_replaced',
          opening_choice_id: 'take_family_album',
          ended_day: 45,
          ended_phase: 'evening',
          partner_variant: 'none',
          livelihood_variant: 'none_low',
          inn_appearance_variant: 'none',
          festival_proxy_npc: 'ajie',
          knowledge_gained_this_run: [],
        },
      ];

      await page.evaluate((snap) => {
        window.localStorage.setItem(
          'returnfare.save.auto',
          JSON.stringify({
            format: 'returnfare-web',
            version: 1,
            saved_at: '2026-11-01T12:00:00.000Z',
            state: snap,
          }),
        );
      }, initSnap);

      await page.reload();
      const continueBtn = page.getByTestId('continue-auto-btn');
      await expect(continueBtn).toBeVisible();
      await continueBtn.click();

      // 進入不上車結局
      await page.getByRole('button', { name: refuseOption.label }).click();
      await page.getByRole('dialog').getByRole('button', { name: '確認', exact: true }).click();

      // 揭露第 1 頁
      await expect(page.getByTestId('ending-page')).toHaveText('第 1 / 2 頁');
      await page.getByTestId('ending-body').click();
      await expect(page.getByTestId('ending-text')).toHaveText(firstEndingPage.text);

      // 翻至第 2 頁
      const nextPageBtn = page.getByRole('button', { name: '下一頁' });
      await expect(nextPageBtn).toBeVisible();
      await nextPageBtn.click();
      await expect(page.getByTestId('ending-page')).toHaveText('第 2 / 2 頁');

      // 揭露第 2 頁
      await page.getByTestId('ending-body').click();
      await expect(page.getByTestId('ending-text')).toHaveText(secondEndingPage.text);
      await expect(page.getByRole('button', { name: '完成' })).toBeVisible({ timeout: 10000 });

      // 手動存檔
      await page.getByTestId('manual-save-btn').click();
      await expect(page.getByTestId('save-status')).toHaveText('存檔成功');

      const endingSavedSnap = await getGameSnapshot(page);
      expect(endingSavedSnap.flow.mode).toBe('ending');
      expect((endingSavedSnap.flow as { active_ending?: { ending_id: string; page_index: number; page_revealed: boolean } }).active_ending?.page_index).toBe(1);
      expect((endingSavedSnap.flow as { active_ending?: { ending_id: string; page_index: number; page_revealed: boolean } }).active_ending?.page_revealed).toBe(true);

      // 重開頁面，點擊繼續進度
      await page.close();
      const page2 = await context.newPage();
      try {
        await setupGameInspectionRoute(page2);
        await page2.goto('/');
        const continueBtn2 = page2.getByTestId('continue-auto-btn');
        await expect(continueBtn2).toBeVisible();
        await continueBtn2.click();

        // 斷言：恢復至同結局、同一頁次（第 2 頁）、已揭露狀態與跨輪歷史完整保留
        const restoredEndingSnap = await getGameSnapshot(page2);
        expect(restoredEndingSnap).toEqual(endingSavedSnap);
        await expect(page2.getByTestId('ending-page')).toHaveText('第 2 / 2 頁');
        await expect(page2.getByTestId('ending-text')).toHaveText(secondEndingPage.text);
        await expect(page2.getByRole('button', { name: '完成' })).toBeVisible();
        expect(restoredEndingSnap.meta.ending_history).toHaveLength(1);

        // 同一結局頁重新匯入時也須退掉舊計時器。延後逐字 tick，避免自然播完掩蓋漏清理。
        await page2.evaluate(() => {
          const active = new Set<number>();
          const cleared = new Set<number>();
          const set = window.setInterval.bind(window);
          const clear = window.clearInterval.bind(window);
          window.setInterval = ((handler: TimerHandler, timeout?: number, ...args: unknown[]) => {
            const endingTimer = timeout === Math.round(1000 / 35);
            const id = set(handler, endingTimer ? 60_000 : timeout, ...args);
            if (endingTimer) active.add(id);
            return id;
          }) as typeof window.setInterval;
          window.clearInterval = ((id?: number) => {
            if (id !== undefined && active.delete(id)) cleared.add(id);
            clear(id);
          }) as typeof window.clearInterval;
          (window as unknown as { __saveTimers: () => { active: number[]; cleared: number[] } }).__saveTimers =
            () => ({ active: [...active], cleared: [...cleared] });
        });
        const timers = () => page2.evaluate(() =>
          (window as unknown as { __saveTimers: () => { active: number[]; cleared: number[] } }).__saveTimers(),
        );
        const unrevealed = structuredClone(restoredEndingSnap);
        unrevealed.flow.active_ending!.page_revealed = false;
        unrevealed.flow.active_ending!.ready_to_complete = false;
        const reloadFile = {
          name: 'same-ending-page.json', mimeType: 'application/json',
          buffer: Buffer.from(JSON.stringify({
            format: 'returnfare-web', version: 1, saved_at: '2026-11-02T00:00:00.000Z', state: unrevealed,
          })),
        };
        for (let reload = 0; reload < 2; reload += 1) {
          const oldTimer = (await timers()).active[0];
          await page2.getByTestId('import-file-input').setInputFiles(reloadFile);
          await page2.getByTestId('save-dialog-confirm-btn').click();
          await expect.poll(async () => (await timers()).active.length).toBe(1);
          if (reload > 0) {
            await expect.poll(async () => (await timers()).cleared).toContain(oldTimer);
            expect((await timers()).active).not.toContain(oldTimer);
          }
          expect(await getGameSnapshot(page2)).toEqual(unrevealed);
        }
      } finally {
        await page2.close();
      }
    } finally {
      await context.close();
    }
  });

test('9. Unsupported-version auto save is preserved until explicit overwrite confirmation', async ({
    page,
  }) => {
    await setupGameInspectionRoute(page);
    await page.goto('/');
    const unsupportedAuto = JSON.stringify({
      format: 'returnfare-web',
      version: 99,
      saved_at: '2026-11-01T12:00:00.000Z',
      state: {},
    });
    await page.evaluate((raw) => window.localStorage.setItem('returnfare.save.auto', raw), unsupportedAuto);
    await page.reload();

    await expect(page.getByTestId('autosave-suspended-banner')).toBeVisible();
    await expect(page.getByTestId('save-error')).toContainText('保留原檔案');

    // 開局選擇並推進：auto 原字串逐字不變
    await page.getByRole('button', { name: opening.opening_choices[0].label }).click();
    await page.getByRole('dialog').getByRole('button', { name: '確認', exact: true }).click();
    await expect(page.locator('header')).toContainText('第 1 天');
    await finishStory(page);
    await page.getByRole('button', { name: '推進時段' }).click();
    await expect(page.locator('header')).toContainText('第 1 天');
    expect((await getRawStorage(page)).auto).toBe(unsupportedAuto);

    // 點覆蓋後取消：仍不變
    await page.getByTestId('overwrite-auto-btn').click();
    await page.getByTestId('save-dialog-cancel-btn').click();
    await expect(page.getByRole('dialog')).toHaveCount(0);
    expect((await getRawStorage(page)).auto).toBe(unsupportedAuto);
    await expect(page.getByTestId('autosave-suspended-banner')).toBeVisible();

    // 確認後 auto 變為目前進度且可解碼
    await page.getByTestId('overwrite-auto-btn').click();
    await page.getByTestId('save-dialog-confirm-btn').click();
    await expect(page.getByTestId('autosave-suspended-banner')).toHaveCount(0);
    const live = await getGameSnapshot(page);
    const raw = (await getRawStorage(page)).auto;
    expect(raw).not.toBe(unsupportedAuto);
    const decoded = JSON.parse(raw!);
    expect(decoded.version).toBe(1);
    expect(decoded.state).toEqual(live);
  });

  test('10. Startup banner disappears after continuing from an opening-mode auto save', async ({
    page,
  }) => {
    await setupGameInspectionRoute(page);
    await page.goto('/');
    // 以手動存檔→讀取讓 auto 槽位停在 opening
    await page.getByTestId('manual-save-btn').click();
    await page.getByTestId('manual-load-btn').click();
    await page.getByTestId('save-dialog-confirm-btn').click();
    await expect(page.getByTestId('save-status')).toHaveText('讀取成功');

    await page.reload();
    await expect(page.getByTestId('save-continue-banner')).toBeVisible();
    await page.getByTestId('continue-auto-btn').click();
    await expect(page.getByTestId('save-status')).toHaveText('進度已載入');
    await expect(page.getByTestId('save-continue-banner')).toHaveCount(0);
  });
});
