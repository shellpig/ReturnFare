import { expect, test, type Page } from './story-fixture';
import { readFileSync } from 'node:fs';

const endings = JSON.parse(readFileSync('../data/endings.json', 'utf8'));
const opening = JSON.parse(readFileSync('../data/opening_choices.json', 'utf8'));
const refuse = endings.find((e: { id: string }) => e.id === 'ending_refuse_boarding');
const refuseOption = opening.opening_choices.find((c: { id: string }) => c.id === 'refuse_boarding');
const [firstPage, secondPage] = refuse.first_seen.pages as { text: string }[];

/**
 * 可信快照注入（僅限 Playwright 路由攔截，產品程式沒有測試入口）：
 * 以「已看過正常結局」的 meta 起算第 2 輪，讓正式的「不上車」選項解鎖。
 */
async function injectSeenReplacedHistory(page: Page) {
  await page.route(/\/src\/core\/state\.ts(\?.*)?$/, async (route) => {
    const response = await route.fetch();
    const originalBody = await response.text();
    const patchedBody =
      originalBody.replace('export function createGame(', 'function __origCreateGame(') +
      `\nexport function createGame(data, initialState) {
        const base = __origCreateGame(data).serialize();
        base.meta.run_number = 2;
        base.meta.ending_history = [{
          run_number: 1, ending_id: 'ending_replaced', opening_choice_id: 'take_family_album',
          ended_day: 45, ended_phase: 'evening', partner_variant: 'none',
          livelihood_variant: 'none_low', inn_appearance_variant: 'none',
          festival_proxy_npc: 'ajie', knowledge_gained_this_run: [],
        }];
        const game = __origCreateGame(data, base);
        window.__w6e1Game = game;
        return game;
      }\n`;
    await route.fulfill({ response, body: patchedBody });
  });
}

const history = (page: Page) =>
  page.evaluate(() => (window as unknown as { __w6e1Game: { serialize(): { meta: { ending_history: unknown[]; run_number: number } } } }).__w6e1Game.serialize().meta);

test('refuse boarding: fill -> flip -> last page -> complete back to opening, with no ordinary controls in ending mode', async ({ page }) => {
  await injectSeenReplacedHistory(page);
  await page.goto('/');
  await expect(page.getByRole('heading', { name: opening.screen.title })).toBeVisible();
  await page.getByRole('button', { name: refuseOption.label }).click();
  await page.getByRole('dialog').getByRole('button', { name: '確認', exact: true }).click();

  const text = page.getByTestId('ending-text');
  const label = page.getByTestId('ending-page');
  // 結局模式：沒有地圖、手牌、推進時段，也沒有開局選項；首見沒有跳過
  await expect(label).toHaveText('第 1 / 2 頁');
  await expect(page.getByRole('button', { name: '顯示全文' })).toBeHidden();
  await expect(page.getByRole('button', { name: '跳過' })).toHaveCount(0);
  await expect(page.getByRole('button', { name: '推進時段' })).toHaveCount(0);
  await expect(page.locator('.hand-panel, .map-panel, .opening')).toHaveCount(0);
  // 逐字顯示中：還沒有第二頁文字
  await expect(page.getByText(secondPage.text)).toHaveCount(0);

  // 一次點擊只補完當頁，不翻頁
  await page.mouse.click(2, 2);
  await expect(text).toHaveText(firstPage.text);
  await expect(label).toHaveText('第 1 / 2 頁');
  await expect(page.getByRole('button', { name: '下一頁' })).toBeVisible();
  expect((await history(page)).ending_history).toHaveLength(1);

  // 一次鍵盤輸入只翻頁，不同時補完下一頁
  await page.keyboard.press('Space');
  await expect(label).toHaveText('第 2 / 2 頁');
  await expect(page.getByRole('button', { name: '顯示全文' })).toBeHidden();
  await expect(page.getByText(firstPage.text)).toHaveCount(0);

  // 逐字自然播完 = 補完當頁；末頁揭露後才出現「完成」
  await expect(page.getByRole('button', { name: '完成' })).toBeVisible({ timeout: 20000 });
  await expect(text).toHaveText(secondPage.text);
  await expect(label).toHaveText('第 2 / 2 頁');
  expect((await history(page)).ending_history).toHaveLength(1);

  // 結算：回到開局，沒有結局殘留；history 只多一筆
  await page.getByRole('button', { name: '完成' }).click();
  await expect(page.getByRole('heading', { name: opening.screen.title })).toBeVisible();
  await expect(page.getByTestId('ending-text')).toHaveCount(0);
  await expect(page.getByRole('button', { name: refuseOption.label })).toBeEnabled();
  const meta = await history(page);
  expect(meta.ending_history).toHaveLength(2);
  expect(meta.run_number).toBe(3);
});
