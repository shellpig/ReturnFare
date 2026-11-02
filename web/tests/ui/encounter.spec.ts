import { finishStory } from './story-fixture';
import { expect, test, type Page } from './story-fixture';

type TestWindow = {
  __testGame?: {
    serialize: () => unknown;
  };
};

/**
 * 測試專用起點注入（透過 Playwright 路由攔截 dev server 的 state.ts，正式產品無測試入口）。
 */
async function injectStartSnapshot(
  page: Page,
  override: {
    day: number;
    phase: string;
    hand?: string[];
    knowledge?: Record<string, boolean>;
    flags?: Record<string, boolean>;
    night_locations_seen?: Record<string, boolean>;
    madness_clock?: Record<string, number>;
  },
) {
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
        const override = JSON.parse(sessionStorage.getItem('__w6d_snap_override__') || 'null');
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
          if (override.knowledge) {
            base.meta.knowledge = { ...base.meta.knowledge, ...override.knowledge };
          }
          if (override.night_locations_seen) {
            base.meta.night_locations_seen = {
              ...base.meta.night_locations_seen,
              ...override.night_locations_seen,
            };
          }
          if (override.madness_clock) {
            base.run.madness_clock = {
              ...base.run.madness_clock,
              ...override.madness_clock,
            };
          }
        }
        const game = __origCreateGame(data, override ? base : initialState);
        window.__testGame = game;
        return game;
      }\n`;
    await route.fulfill({ response, body: patchedBody });
  });
  await page.addInitScript((value) => {
    sessionStorage.setItem('__w6d_snap_override__', JSON.stringify(value));
  }, override);
}

test('W6-D UI: D8 evening 推進至入夜遭遇 — intro -> ack -> 候選卡取消不變 -> 確認回應 -> 結果可見且日常推進封鎖', async ({
  page,
}) => {
  await page.setViewportSize({ width: 1280, height: 800 });
  await injectStartSnapshot(page, {
    day: 8,
    phase: 'evening',
    hand: ['protagonist', 'item_gradphoto', 'routine_debt'],
    knowledge: { k_not_today: true },
  });
  await page.goto('/');

  // 1. D8 evening 推進時段至 night
  const advanceBtn = page.getByRole('button', { name: '推進時段' });
  await expect(advanceBtn).toBeVisible();
  await advanceBtn.click();

  // 2. 自動播放入夜 fixed beat，啟動遭遇進入 intro 階段
  const encounterPanel = page.locator('[data-testid="encounter-panel"]');
  await expect(encounterPanel).toBeVisible();

  // 演出若有多段，以「繼續演出」逐段推進
  const continueBtn = page.locator('[data-testid="encounter-intro-continue"]');
  while (await finishStory(page), await continueBtn.isVisible()) {
    await continueBtn.click();
  }

  // 遭遇 intro 階段中：日常時段推進按鈕不可用
  await expect(page.getByRole('button', { name: '推進時段' })).toHaveCount(0);
  await expect(page.getByRole('button', { name: '直接睡' })).toHaveCount(0);

  // 3. 確認開場（ack）
  const ackBtn = page.locator('[data-testid="encounter-intro-ack"]');
  await expect(ackBtn).toBeVisible();
  await ackBtn.click();

  // 4. 進入第一回合（round 階段）
  const demand = page.locator('[data-testid="encounter-demand"]');
  await expect(demand).toBeVisible();
  await expect(demand).toHaveText('「那個名字什麼時候開始是你的？」');

  // 回合進行中：日常推進依舊不可用
  await expect(page.getByRole('button', { name: '推進時段' })).toHaveCount(0);
  await expect(page.getByRole('button', { name: '直接睡' })).toHaveCount(0);

  // 逃離支付預覽取消：從開啟前取樣，能攔住提前扣卡。
  const paymentBefore = await page.evaluate(
    () => JSON.stringify((window as unknown as TestWindow).__testGame!.serialize()),
  );
  await page.getByTestId('encounter-escape-pay-item_gradphoto').click();
  await page.getByTestId('dialog-cancel-encounter-escape').click();
  expect(await page.evaluate(
    () => JSON.stringify((window as unknown as TestWindow).__testGame!.serialize()),
  )).toBe(paymentBefore);

  // 5. 點選候選卡片開啟確認對話框（k_not_today 為合法提交卡片）
  const candBtn = page.locator('[data-testid="encounter-candidate-k_not_today"]');
  await expect(candBtn).toBeVisible();
  await expect(candBtn).toBeEnabled();
  const beforeJson = await page.evaluate(
    () => JSON.stringify((window as unknown as TestWindow).__testGame!.serialize()),
  );
  await candBtn.click();

  const cancelBtn = page.locator(
    '[data-testid="dialog-cancel-encounter-respond"]',
  );
  const confirmBtn = page.locator(
    '[data-testid="dialog-confirm-encounter-respond"]',
  );
  await expect(cancelBtn).toBeVisible();
  await expect(confirmBtn).toBeVisible();

  // 6. 取消預覽：狀態零變更（序列化完全一致）
  await cancelBtn.click();
  await expect(cancelBtn).toHaveCount(0);
  const afterJson = await page.evaluate(
    () => JSON.stringify((window as unknown as TestWindow).__testGame!.serialize()),
  );
  expect(afterJson).toBe(beforeJson);

  // 7. 確認提交回應
  await candBtn.click();
  await expect(confirmBtn).toBeVisible();
  await confirmBtn.click();

  // 8. 正式結果可見，推進至第二回合
  const actionLines = page.locator('.encounter-action-lines');
  await expect(actionLines).toBeVisible();
  await expect(actionLines).toContainText(
    '他停頓了一下。這個超乎常理的回答顯然脫離了他的預想。',
  );
  await expect(demand).toHaveText('「那誰記得你？」');
});

test('W6-D UI: D45 afternoon 遭遇結算 after_finish 自動推進至 evening，保留出口文字', async ({
  page,
}) => {
  await page.setViewportSize({ width: 1280, height: 800 });
  await injectStartSnapshot(page, {
    day: 45,
    phase: 'morning',
    hand: [
      'protagonist',
      'item_gradphoto',
      'routine_debt',
      'item_old_paper',
    ],
    flags: { final_day: true },
  });
  await page.goto('/');

  // 1. D45 morning 推進至 afternoon
  const advanceBtn = page.getByRole('button', { name: '推進時段' });
  await expect(advanceBtn).toBeVisible();
  await advanceBtn.click();

  // 2. D45 自動啟動遭遇 intro
  const encounterPanel = page.locator('[data-testid="encounter-panel"]');
  await expect(encounterPanel).toBeVisible();

  const continueBtn = page.locator('[data-testid="encounter-intro-continue"]');
  while (await finishStory(page), await continueBtn.isVisible()) {
    await continueBtn.click();
  }

  const ackBtn = page.locator('[data-testid="encounter-intro-ack"]');
  await expect(ackBtn).toBeVisible();
  await ackBtn.click();

  // 3. 提交主角卡
  const candBtn = page.locator('[data-testid="encounter-candidate-protagonist"]');
  await expect(candBtn).toBeVisible();
  await expect(candBtn).toBeEnabled();
  await candBtn.click();

  const confirmBtn = page.locator(
    '[data-testid="dialog-confirm-encounter-respond"]',
  );
  await expect(confirmBtn).toBeVisible();
  await confirmBtn.click();

  // 4. 遭遇結束並自動推進至 evening，保留出口演出結果橫幅
  const resultBanner = page.locator('[data-testid="encounter-result"]');
  await expect(resultBanner).toBeVisible();
  await expect(resultBanner).toContainText(
    '走廊的風漸漸停了，周圍只剩下濃黑的霧。',
  );

  // 時段已進入傍晚（D45 evening）
  await expect(page.locator('.daytime-shell')).toBeVisible();
  await expect(page.locator('header')).toContainText('第 45 天');
  await expect(page.locator('header')).toContainText('傍晚');
});
