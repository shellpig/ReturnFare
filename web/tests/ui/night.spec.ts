import { expect, test, type Page } from './story-fixture';
import { readFileSync } from 'node:fs';

const locations = JSON.parse(readFileSync('../data/locations.json', 'utf8'));
const tuning = JSON.parse(readFileSync('../data/tuning.json', 'utf8'));
const cards = JSON.parse(readFileSync('../data/cards.json', 'utf8')).cards;
const nightLoc = (id: string) => locations.night.find((l: { id: string }) => l.id === id);
const dayLoc = (id: string) => locations.day.find((l: { id: string }) => l.id === id);
const cardById = (id: string) => cards.find((c: { id: string }) => c.id === id);

type TestWindow = {
  __testGame?: {
    serialize: () => {
      run: { hand: string[]; madness_clock: Record<string, number> };
      meta: { knowledge: Record<string, boolean>; night_locations_seen: Record<string, boolean> };
    };
  };
};

/** 注入起點（測試專用，產品沒有入口）：以路由攔截 dev server 的 state.ts，覆寫開局後的日期／時段。 */
async function injectStartSnapshot(page: Page, override: { day: number; phase: string }) {
  await page.route(/\/src\/core\/state\.ts(\?.*)?$/, async (route) => {
    const response = await route.fetch();
    const originalBody = await response.text();
    const patchedBody =
      originalBody.replace('export function createGame(', 'function __origCreateGame(') +
      `\nexport function createGame(data, initialState) {
        const base = __origCreateGame(data).serialize();
        const override = JSON.parse(sessionStorage.getItem('__w6a_snap_override__') || 'null');
        if (override) {
          base.flow.mode = 'run';
          base.run.day = override.day;
          base.run.phase = override.phase;
          base.run.hand = ['protagonist'];
        }
        const game = __origCreateGame(data, override ? base : initialState);
        window.__testGame = game;
        return game;
      }\n`;
    await route.fulfill({ response, body: patchedBody });
  });
  await page.addInitScript((value) => {
    sessionStorage.setItem('__w6a_snap_override__', JSON.stringify(value));
  }, override);
}

const serializeNow = (page: Page) =>
  page.evaluate(() => {
    const game = (window as unknown as TestWindow).__testGame;
    return game ? JSON.stringify(game.serialize()) : null;
  });

test('夜間：開詳情不改狀態 → 確認進入才發卡 → 隔天回到正確白天地點對位（注入 D17 起點）', async ({
  page,
}) => {
  await page.setViewportSize({ width: 1280, height: 800 });
  await injectStartSnapshot(page, { day: 17, phase: 'night' });
  await page.goto('/');

  const row = nightLoc('n_litcorridor');
  const daytime = dayLoc('clinic_back');
  const cost: number = row.madness_cost;
  const days: number = tuning.madness_countdown_days;
  const body = page.locator('body');

  // 夜間清單：名稱＋狀態文字，主按鈕為「直接睡」；任何地方都沒有「免費」或價碼
  await expect(page.locator('header')).toContainText('第 17 天');
  await expect(page.locator('.map-panel')).toBeVisible();
  const rowButton = page.getByRole('button', { name: `${row.name} [尚未到訪]` });
  await expect(rowButton).toBeVisible();
  await expect(page.locator('.phase-actions button')).toHaveText('直接睡');
  await expect(body).not.toContainText('免費');

  // 開詳情：唯讀，狀態逐字不變
  const untouched = await serializeNow(page);
  expect(untouched).not.toBeNull();
  await rowButton.click();
  await expect(page.getByTestId('night-status')).toHaveText('[尚未到訪]');
  await expect(page.getByTestId('night-desc')).toHaveText(row.desc.trim());
  await expect(page.getByTestId('night-reason')).toHaveCount(0);
  await expect(page.getByTestId('night-warning')).toHaveCount(0);
  await expect(body).not.toContainText('免費');
  await expect(page.getByTestId('night-enter')).toBeEnabled();
  expect(await serializeNow(page)).toBe(untouched);
  // 返回再開一次也不改狀態
  await page.getByRole('button', { name: '返回地圖' }).click();
  await rowButton.click();
  expect(await serializeNow(page)).toBe(untouched);

  // 確認進入：這時才發卡、記到訪、用掉今晚
  await page.getByTestId('night-enter').click();
  const afterEnter = await page.evaluate(() => {
    const snap = (window as unknown as TestWindow).__testGame!.serialize();
    return {
      hand: snap.run.hand,
      clock: snap.run.madness_clock,
      seen: snap.meta.night_locations_seen,
    };
  });
  expect(afterEnter.hand).toEqual(['protagonist', 'madness#1']);
  expect(afterEnter.clock).toEqual({ 'madness#1': days });
  expect(afterEnter.seen).toEqual({ n_litcorridor: true });
  await expect(page.getByTestId('hand-slots')).toHaveText('手牌 2 / 14');
  await expect(page.getByTestId('card-madness#1')).toContainText(`${cardById('madness').name} (${days}天)`);

  // 地點面板：先播 OPEN beat，演完後常態畫面顯示發卡提示
  await expect(page.locator('.location-panel')).toBeVisible();
  await page.getByRole('button', { name: '繼續演出' }).click();
  await expect(page.getByTestId('action-result')).toContainText(`獲得 ${cost} 張發狂卡`);
  await page.getByRole('button', { name: '返回地圖' }).click();

  // 清單位置不變、狀態更新；今夜已選：進入灰掉並顯示封閉碼的中文理由；主按鈕變「結束今晚」
  await expect(page.getByRole('button', { name: `${row.name} [已到訪，尚未對位]` })).toBeVisible();
  await expect(page.locator('.phase-actions button')).toHaveText('結束今晚');
  await page.getByRole('button', { name: `${row.name} [已到訪，尚未對位]` }).click();
  await expect(page.getByTestId('night-enter')).toBeDisabled();
  await expect(page.getByTestId('night-reason')).toHaveText('今夜已探索過其他地點');
  await expect(body).not.toContainText('already_chosen');
  await page.getByRole('button', { name: '返回地圖' }).click();

  // 換日：發狂卡第一次倒數
  await page.locator('.phase-actions button').click();
  await expect(page.locator('header')).toContainText('第 18 天');
  await expect(page.getByTestId('card-madness#1')).toContainText(`(${days - 1}天)`);
  // 白天地圖不曝光夜間資訊
  await expect(page.locator('.map-panel')).toBeVisible();
  await expect(body).not.toContainText('尚未到訪');
  await page.locator('.phase-actions button').click(); // -> D18 afternoon
  await expect(page.locator('header')).toContainText('下午');

  // 錯誤的白天地點沒有對位按鈕（山泉閣）
  await page.getByRole('button', { name: dayLoc('sanquan').name }).click();
  while (await page.getByRole('button', { name: '繼續演出' }).isVisible()) {
    await page.getByRole('button', { name: '繼續演出' }).click();
  }
  await expect(page.getByTestId('night-align-btn')).toHaveCount(0);
  await page.getByRole('button', { name: '返回地圖' }).click();

  // 正確的白天地點：演出播完、進入常態畫面後才出現「把兩邊對起來」
  await page.getByRole('button', { name: daytime.name }).click();
  await expect(page.getByTestId('night-align-btn')).toHaveCount(0); // 演出中不出現
  while (await page.getByRole('button', { name: '繼續演出' }).isVisible()) {
    await page.getByRole('button', { name: '繼續演出' }).click();
  }
  const alignBtn = page.getByTestId('night-align-btn');
  await expect(alignBtn).toHaveText('把兩邊對起來');

  // 取消不改狀態；確認才取得知識，且不增加佔格、不吃行動格
  const beforeAlign = await serializeNow(page);
  await alignBtn.click();
  const dialog = page.getByRole('dialog');
  await expect(dialog).toContainText('確認對位');
  await expect(dialog).toContainText('要將白天地點與夜間見聞對位嗎？');
  await dialog.getByRole('button', { name: '取消' }).click();
  await expect(dialog).toHaveCount(0);
  expect(await serializeNow(page)).toBe(beforeAlign);

  await alignBtn.click();
  await page.getByTestId('night-align-confirm').click();
  await expect(alignBtn).toHaveCount(0);
  const knowledge = await page.evaluate(
    () => (window as unknown as TestWindow).__testGame!.serialize().meta.knowledge,
  );
  expect(knowledge).toEqual({ [row.night_reveal]: true });
  await expect(page.getByTestId('hand-slots')).toHaveText('手牌 2 / 14');
  await expect(page.getByTestId('knowledge-btn')).toContainText('知識 (1)');
  await expect(body).not.toContainText('align');
});
