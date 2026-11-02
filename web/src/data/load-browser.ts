/**
 * ReturnFare Web — 瀏覽器端資料載入（W2-A）。
 *
 * 注入 fetch：先讀 /data-manifest.json，再依相對路徑讀 /data/<path>。
 * 不得 import node：* 模組；不由 src/main.tsx 與 ui 引入（ui 不自行 import root data/）。
 */

import { loadGameData, type ReadText, type DataFile, type GameData } from './loader';

const MANIFEST_URL = '/data-manifest.json';

async function fetchJsonManifest(): Promise<DataFile[]> {
  const res = await fetch(MANIFEST_URL);
  if (!res.ok) {
    throw new Error(`無法讀取 ${MANIFEST_URL}：HTTP ${res.status}`);
  }
  let parsed: unknown;
  try {
    parsed = await res.json();
  } catch {
    throw new Error(`${MANIFEST_URL}: JSON 解析失敗`);
  }
  const obj = parsed as { files?: unknown };
  if (!Array.isArray(obj.files)) {
    throw new Error(`${MANIFEST_URL}: 缺少 files 陣列`);
  }
  return obj.files as DataFile[];
}

/** onFileLoaded：每讀完一份資料回報（已完成份數, manifest 總份數），供載入畫面顯示進度。 */
export async function loadGameDataBrowser(
  onFileLoaded?: (done: number, total: number) => void,
): Promise<GameData> {
  const manifest = await fetchJsonManifest();
  let loadedCount = 0;

  const readText: ReadText = async (relativeDataPath: string): Promise<string> => {
    // 逐段編碼：整段 encodeURIComponent 會把 beats/ 的斜線變成 %2F，靜態主機找不到檔。
    const url = `/data/${relativeDataPath.split('/').map(encodeURIComponent).join('/')}`;
    const res = await fetch(url);
    if (!res.ok) {
      throw new Error(`${relativeDataPath}: 讀取失敗：HTTP ${res.status}`);
    }
    const text = await res.text();
    loadedCount += 1;
    onFileLoaded?.(loadedCount, manifest.length);
    return text;
  };

  return loadGameData(readText, manifest);
}
