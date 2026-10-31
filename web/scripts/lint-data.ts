/**
 * ReturnFare Web — Build-time 資料検証 CLI（W2-B）。
 *
 * 執行入口：`npm run lint:data [-- --data-dir <dir>]`（cwd: web/），
 * 或透過環境變數 `RETURNFARE_DATA_DIR=<dir>` 指定資料根目錄（供測試注入壞資料 fixture）。
 *
 * - 只讀來源，不修改任何 JSON、不覆寫基線。
 * - 先執行 W2-A loadGameDataNode（攔截讀檔失敗、壞 JSON、七類重複 id、when day+day_from 互斥），
 *   再進入 validateData() 跑完整 registry。
 * - warning 只回報實數不擋 build；error 或載入失敗以 exit code 1 退出。
 */

import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { getDefaultDataDir, loadGameDataNode } from '../src/data/load-node';
import { validateData, type ValidationReport } from '../src/data/validate';

export interface LintCliResult {
  readonly exitCode: number;
  readonly dataDir: string;
  readonly catalog?: {
    readonly cards: number;
    readonly locations: number;
    readonly npcs: number;
    readonly beats: number;
    readonly endings: number;
    readonly openingChoices: number;
    readonly cardTypes: number;
  };
  readonly report?: ValidationReport;
  readonly loadError?: string;
}

function parseDataDirArg(argv: readonly string[], envDataDir?: string): string {
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg === '--data-dir') {
      const next = argv[i + 1];
      if (!next || next.trim().length === 0) {
        throw new Error('lint-data: --data-dir 需要提供目錄路徑');
      }
      return resolve(next);
    }
  }
  if (envDataDir && envDataDir.trim().length > 0) {
    return resolve(envDataDir);
  }
  return getDefaultDataDir();
}

export async function runLintData(
  argv: readonly string[] = [],
  envDataDir: string | undefined = process.env.RETURNFARE_DATA_DIR,
): Promise<LintCliResult> {
  let dataDir: string;
  try {
    dataDir = parseDataDirArg(argv, envDataDir);
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err);
    console.error(msg);
    return { exitCode: 1, dataDir: '', loadError: msg };
  }

  let data;
  try {
    data = await loadGameDataNode(dataDir);
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err);
    console.error(`資料載入失敗：${msg}`);
    return { exitCode: 1, dataDir, loadError: msg };
  }

  const catalog = {
    cards: data.cards.length,
    locations: data.locations.length,
    npcs: data.npcs.length,
    beats: data.beats.length,
    endings: data.endings.length,
    openingChoices: data.openingChoices.length,
    cardTypes: data.cardTypes.length,
  };

  const report = validateData(data);

  console.log('=== ReturnFare 資料載入與驗證 (W2-B) ===');
  console.log(
    `catalog：卡片 ${catalog.cards}／地點 ${catalog.locations}／NPC ${catalog.npcs}／beat ${catalog.beats}／ending ${catalog.endings}／opening ${catalog.openingChoices}／cardTypes ${catalog.cardTypes}`,
  );
  console.log(
    `已執行規則 (${report.executedRules.length})：${report.executedRules.join(', ')}`,
  );
  console.log(`警告：${report.warnings.length} 筆`);
  for (const w of report.warnings) {
    console.log(`  [WARN] [${w.ruleId}] (${w.source}) ${w.message}`);
  }

  if (report.errors.length > 0) {
    console.error(`錯誤：${report.errors.length} 筆`);
    for (const e of report.errors) {
      console.error(`  [ERROR] [${e.ruleId}] (${e.source}) ${e.message}`);
    }
    return { exitCode: 1, dataDir, catalog, report };
  }

  console.log('錯誤：0 筆');
  return { exitCode: 0, dataDir, catalog, report };
}

const isMain =
  Boolean((import.meta as { main?: boolean }).main) ||
  (process.argv[1] !== undefined && resolve(process.argv[1]) === fileURLToPath(import.meta.url));

if (isMain) {
  runLintData(process.argv.slice(2)).then((res) => {
    process.exit(res.exitCode);
  });
}
