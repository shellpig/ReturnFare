import { expect, test } from './story-fixture';
import { readFileSync } from 'node:fs';

const opening = JSON.parse(readFileSync('../data/opening_choices.json', 'utf8'));
const ch1Beats = JSON.parse(
  readFileSync('../data/beats/ch1_d01_d03.json', 'utf8'),
).beats;
const ch2Beats = JSON.parse(
  readFileSync('../data/beats/ch2_d16_d22.json', 'utf8'),
).beats;
const nights = JSON.parse(
  readFileSync('../data/beats/ch1_nights.json', 'utf8'),
).beats;
const locations = JSON.parse(
  readFileSync('../data/locations.json', 'utf8'),
).day;

const ch1Beat = (id: string) =>
  ch1Beats.find((b: { id: string }) => b.id === id);
const ch2Beat = (id: string) =>
  ch2Beats.find((b: { id: string }) => b.id === id);
const locById = (id: string) =>
  locations.find((l: { id: string }) => l.id === id);

test('D2 morning map and two-stage LocationPanel: plays OPEN beat first without slots, reveals desc and slots on advance, replays on re-entry, and keeps unvisited empty locations disabled', async ({
  page,
}) => {
  await page.goto('/');

  // Choose first opening option (take_family_album) and walk D1 -> D2 morning
  await page
    .getByRole('button', { name: opening.opening_choices[0].label })
    .click();
  await page
    .getByRole('dialog')
    .getByRole('button', { name: '確認', exact: true })
    .click();

  const nextBtn = page.getByRole('button', { name: '繼續演出' });
  const advanceBtn = page.getByRole('button', { name: '推進時段' });

  // D1 morning: d1_morning_departure
  await advanceBtn.click();

  // D1 afternoon: d1_pm_mountain_road
  await advanceBtn.click();

  // D1 evening: d1_arrival (text + on_enter.text) + d1_ambient_couple
  await nextBtn.click();
  await nextBtn.click();
  await advanceBtn.click();

  // D1 night: n_corridor_ch1
  await expect(page.locator('.passage')).toHaveText(
    nights.find((b: { id: string }) => b.id === 'n_corridor_ch1').text,
  );
  // W6-A：夜間已被 fixed 強制到訪，主按鈕為「結束今晚」
  await page.getByRole('button', { name: '結束今晚' }).click();

  // Now at D2 morning: daytime map is visible
  await expect(page.locator('header')).toContainText('第 2 天');
  await expect(page.locator('.map-panel')).toBeVisible();

  // Unvisited empty locations on D2 morning (e.g. 診所, 老街) are disabled and cannot be clicked into LocationPanel
  const clinicBtn = page.getByRole('button', { name: locById('clinic').name });
  await expect(clinicBtn).toBeDisabled();
  await clinicBtn.dispatchEvent('click');
  await expect(page.locator('.location-panel')).toHaveCount(0);

  // Open 山泉閣 (sanquan)
  const sanquanBtn = page.getByRole('button', {
    name: locById('sanquan').name,
  });
  await expect(sanquanBtn).toBeEnabled();
  await sanquanBtn.click();

  // Stage 1: OPEN beat d2_morning_intro text is immediately shown; desc and slots are NOT rendered yet
  const d2Intro = ch1Beat('d2_morning_intro');
  await expect(page.locator('.location-panel')).toBeVisible();
  await expect(page.locator('.beat-title')).toHaveText(d2Intro.title);
  await expect(page.locator('.beat-text')).toHaveText(d2Intro.text);
  await expect(page.locator('.location-desc')).toHaveCount(0);
  await expect(page.locator('.slot-item')).toHaveCount(0);

  // Click 繼續演出 -> transitions to Stage 2: location desc and slots appear
  await nextBtn.click();
  await expect(page.locator('.location-desc')).toHaveText(
    locById('sanquan').desc,
  );
  await expect(page.locator('.slot-item')).toHaveCount(2);
  await expect(page.locator('.slot-label').nth(0)).toHaveText('阿婕（前台）');
  await expect(page.locator('.slot-label').nth(1)).toHaveText('中年夫妻');
  const displaySlots = page.locator('.slot-display');
  await expect(displaySlots).toHaveCount(2);
  await expect(displaySlots.locator('button')).toHaveCount(0);
  for (const viewport of [{ width: 1280, height: 800 }, { width: 390, height: 844 }]) {
    await page.setViewportSize(viewport);
    const left = await displaySlots.nth(0).boundingBox();
    const right = await displaySlots.nth(1).boundingBox();
    expect(left).not.toBeNull();
    expect(right).not.toBeNull();
    expect(Math.abs(left!.y - right!.y)).toBeLessThan(1);
    expect(right!.x).toBeGreaterThanOrEqual(left!.x + left!.width);
    await expect(displaySlots.nth(0)).toHaveCSS('border-top-width', '0px');
    await expect(displaySlots.nth(0)).toHaveCSS('background-color', 'rgba(0, 0, 0, 0)');
  }
  await page.screenshot({ path: '../_qa/web/display-slots-mobile.png', fullPage: true });
  await page.setViewportSize({ width: 1280, height: 800 });

  // Return to map and re-enter 山泉閣 -> beat text replays in Stage 1
  await page.getByRole('button', { name: '返回地圖' }).click();
  await expect(page.locator('.map-panel')).toBeVisible();
  await sanquanBtn.click();
  await expect(page.locator('.beat-text')).toHaveText(d2Intro.text);
  await expect(page.locator('.slot-item')).toHaveCount(0);
});

test('D19 afternoon upstream (only LOCKED beat) records visit on UI click without calling playBeat(), and D20 afternoon upstream (no beats) stays Enabled and shows formal desc', async ({
  page,
}) => {
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
        const base = __origCreateGame(data).serialize();
        const override = JSON.parse(sessionStorage.getItem('__w4b_snap_override__') || 'null');
        if (override) {
          base.flow.mode = 'run';
          base.run.day = override.day;
          base.run.phase = override.phase;
          base.run.hand = ['protagonist'];
          base.meta.day_locations_visited = override.visited || {};
        }
        const game = __origCreateGame(data, override ? base : initialState);
        win.__w4bPlayBeatCalls = 0;
        const origPlayBeat = game.playBeat.bind(game);
        game.playBeat = (beatId) => {
          win.__w4bPlayBeatCalls += 1;
          return origPlayBeat(beatId);
        };
        win.__w4bGame = game;
        return game;
      }\n`;
    await route.fulfill({
      response,
      body: patchedBody,
    });
  });

  await page.addInitScript(() => {
    if (!sessionStorage.getItem('__w4b_snap_override__')) {
      sessionStorage.setItem(
        '__w4b_snap_override__',
        JSON.stringify({ day: 19, phase: 'afternoon', visited: {} }),
      );
    }
  });

  await page.goto('/');

  await expect(page.locator('header')).toContainText('第 19 天');
  const upstreamLoc = locById('upstream');
  const d19UpstreamBeat = ch2Beat('d19_pm_upstream');

  // Upstream has a LOCKED beat on D19 afternoon, so its map button is Enabled
  const upstreamBtn = page.getByRole('button', { name: upstreamLoc.name });
  await expect(upstreamBtn).toBeEnabled();
  await upstreamBtn.click();

  // Because d19_pm_upstream is LOCKED (not OPEN), UI goes straight to Stage 2 (desc + locked beat/slot) without calling playBeat()
  await expect(page.locator('.location-desc')).toHaveText(upstreamLoc.desc);
  await expect(page.locator('.beat-group-title')).toContainText(
    d19UpstreamBeat.title,
  );
  await expect(page.locator('.beat-group-title')).toContainText(
    d19UpstreamBeat.reject_reason,
  );

  const d19Check = await page.evaluate(() => {
    const win = window as unknown as {
      __w4bPlayBeatCalls: number;
      __w4bGame: {
        serialize: () => {
          meta: { day_locations_visited: Record<string, boolean> };
        };
      };
    };
    const visited = win.__w4bGame.serialize().meta.day_locations_visited;
    sessionStorage.setItem(
      '__w4b_snap_override__',
      JSON.stringify({ day: 20, phase: 'afternoon', visited }),
    );
    return {
      playBeatCalls: win.__w4bPlayBeatCalls,
      visitedUpstream: visited.upstream === true,
    };
  });
  expect(d19Check).toEqual({
    playBeatCalls: 0,
    visitedUpstream: true,
  });

  // Reload into D20 afternoon preserving the visit record from D19 afternoon
  await page.reload();

  await expect(page.locator('header')).toContainText('第 20 天');
  // Even though upstream has 0 beats on D20 afternoon, it was visited on D19 so it remains Enabled on the map
  await expect(upstreamBtn).toBeEnabled();
  await upstreamBtn.click();

  // Clicking upstream on D20 afternoon displays only its formal desc (no beats, no slots)
  await expect(page.locator('.location-desc')).toHaveText(upstreamLoc.desc);
  await expect(page.locator('.beat-group')).toHaveCount(0);
  await expect(page.locator('.slot-item')).toHaveCount(0);
});
