import { expect, test } from './story-fixture';

test('BGM uses chapter, night and date parity; every track loads and plays', async ({ page }) => {
  // 與其他 UI 測試相同，只在 dev 回應內注入可信起點，不增加正式測試入口。
  await page.route(/\/src\/core\/state\.ts(\?.*)?$/, async route => {
    const response = await route.fetch();
    const body = (await response.text()).replace('export function createGame(', 'function originalCreateGame(') + `
      export function createGame(data) {
        const params = new URLSearchParams(location.search);
        if (!params.has('day')) return originalCreateGame(data);
        const base = originalCreateGame(data).serialize();
        base.flow.mode = 'run';
        base.run.day = Number(params.get('day'));
        base.run.phase = params.get('phase');
        return originalCreateGame(data, base);
      }`;
    await route.fulfill({ response, body });
  });

  const cases = [
    ['/', 'bgm_01_opening'],
    ['/?day=1&phase=morning', 'bgm_02_day_ch1_b'],
    ['/?day=2&phase=afternoon', 'bgm_02_day_ch1_a'],
    ['/?day=16&phase=morning', 'bgm_03_day_ch2'],
    ['/?day=17&phase=evening', 'bgm_03_day_ch2'],
    ['/?day=33&phase=morning', 'bgm_04_day_ch3_a'],
    ['/?day=34&phase=evening', 'bgm_04_day_ch3_b'],
    ['/?day=1&phase=night', 'bgm_05_night_a'],
    ['/?day=16&phase=night', 'bgm_05_night_b'],
    ['/?day=33&phase=night', 'bgm_05_night_a'],
  ];
  for (const [url, track] of cases) {
    await page.goto(url);
    const audio = page.locator('audio');
    await expect(audio).toHaveCount(1);
    await expect(audio).toHaveAttribute('src', `/audio/bgm/${track}.mp3`);
    await expect(audio).toHaveJSProperty('loop', true);
    await page.locator('body').click({ position: { x: 2, y: 2 } });
    await expect(audio).toHaveJSProperty('paused', false);
    await expect.poll(() => audio.evaluate(el => (el as HTMLAudioElement).currentTime)).toBeGreaterThan(0);
    await expect(audio).toHaveJSProperty('error', null);
  }
});
