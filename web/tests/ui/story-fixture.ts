import { test as base } from '@playwright/test';
import type { Page } from '@playwright/test';

export async function finishStory(page: Page) {
  const story = page.locator('body:not(:has(dialog[open])) [data-typing="true"]').first();
  if (await story.isVisible()) await page.locator('[data-typing]').first().click({ position: { x: 5, y: 5 } });
}

// 一般流程驗收以玩家點擊補完文字，避免每段都等待閱讀動畫。
// 逐字速度、操作門檻與補完原子性由 story-text.spec.ts 使用原始 fixture 驗證。
export const test = base.extend({
  page: async ({ page }, use) => {
    await page.addLocatorHandler(page.locator('body:not(:has(dialog[open])) [data-typing="true"]').first(), async story => {
      await story.click();
    });
    await use(page);
  },
});
export { expect } from '@playwright/test';
export type { Page } from '@playwright/test';
