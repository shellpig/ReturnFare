/**
 * index.html 載入畫面的進度控制。純呈現：不參與規則，也不影響資料載入結果。
 * 分段：程式就緒 → 資料逐份完成 → 兩套字型就緒；就緒或失敗都會移除載入畫面。
 */

/** 各階段在進度條上的終點（0～1）。 */
export const BOOT_SCRIPT_READY = 0.1;
const BOOT_DATA_DONE = 0.8;

export function setBootProgress(ratio: number): void {
  const pct = Math.round(Math.min(Math.max(ratio, 0), 1) * 100);
  const bar = document.getElementById('boot-bar');
  if (bar) bar.style.width = `${pct}%`;
  document.getElementById('boot-track')?.setAttribute('aria-valuenow', String(pct));
}

/** 資料第 done／total 份完成時的進度。 */
export function setBootDataProgress(done: number, total: number): void {
  setBootProgress(BOOT_SCRIPT_READY + (BOOT_DATA_DONE - BOOT_SCRIPT_READY) * (total > 0 ? done / total : 1));
}

/** 等兩套自託管字型就緒；字型失敗不擋遊戲（font-display: swap 會退回系統字型）。 */
export async function waitBootFonts(): Promise<void> {
  if (!('fonts' in document)) return;
  await Promise.all(['16px WenKai', '16px TaipeiSans'].map(font => document.fonts.load(font).catch(() => [])));
  setBootProgress(1);
}

/** 淡出並移除載入畫面。 */
export function finishBoot(): void {
  const boot = document.getElementById('boot');
  if (!boot) return;
  boot.classList.add('done');
  window.setTimeout(() => boot.remove(), 300);
}
