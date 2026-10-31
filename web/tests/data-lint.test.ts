import { describe, it, expect } from 'vitest';
import { cp, mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import { dirname, join, resolve } from 'node:path';
import { tmpdir } from 'node:os';
import { loadGameData } from '../src/data/loader';
import { buildManifest, createNodeReadText, loadGameDataNode } from '../src/data/load-node';
import {
  LINT_REGISTRY,
  lint_choice_rules,
  lint_free_slot_rules,
  validateData,
  type LintGroup,
} from '../src/data/validate';
import { runLintData } from '../scripts/lint-data';
import type { GameData, ReadText } from '../src/data/types';

const REPO_ROOT = resolve(__dirname, '..', '..');
const DATA_DIR = join(REPO_ROOT, 'data');

/**
 * 透過記憶體覆寫特定相對路徑的 JSON，經過正式 loadGameData 載入，
 * 絕不修改 repo data/，也不污染其他測試案例。
 */
async function loadPatchedData(
  mutateJson: (relPath: string, parsed: Record<string, unknown> | unknown[]) => void,
): Promise<GameData> {
  const manifest = await buildManifest(DATA_DIR);
  const baseReadText = createNodeReadText(DATA_DIR);
  const patchedReadText: ReadText = async (relPath: string) => {
    const rawText = await baseReadText(relPath);
    const parsed = JSON.parse(rawText) as Record<string, unknown> | unknown[];
    mutateJson(relPath, parsed);
    return JSON.stringify(parsed);
  };
  return loadGameData(patchedReadText, manifest);
}

describe('W2-B build-time data lint', () => {
  it('validates formal data with 0 errors, 4 exempted choice warnings, and all 7 groups / 22 rules executed', async () => {
    const data = await loadGameDataNode();
    const report = validateData(data);

    expect(report.errors).toEqual([]);
    expect(report.warnings.length).toBe(4);
    for (const w of report.warnings) {
      expect(w.ruleId).toBe('lint_free_slot_rules');
      expect(w.message).toContain('DataFacts 豁免名單');
    }

    // 確認 registry 22 條規則全部執行，且覆蓋全部 7 個群組
    expect(report.executedRules).toEqual(LINT_REGISTRY.map((r) => r.id));
    expect(report.executedRules.length).toBe(22);

    const groups = new Set<LintGroup>(LINT_REGISTRY.map((r) => r.group));
    expect(groups).toEqual(
      new Set<LintGroup>([
        'structure_refs_tuning',
        'vocabulary_card_types',
        'day_supply_free_slot_echo',
        'indulgence',
        'night',
        'delegation_encounter',
        'opening_ending_loop',
      ]),
    );

    // lint_choice_rules 與 lint_free_slot_rules 同源且只登錄一次
    expect(lint_choice_rules).toBe(lint_free_slot_rules);
    expect(
      LINT_REGISTRY.filter(
        (r) => r.id === 'lint_free_slot_rules' || r.id === 'lint_choice_rules',
      ).length,
    ).toBe(1);
  });

  it('catches unknown cross-table references (verify_references) and required tuning keys (Data.REQUIRED_TUNING_KEYS)', async () => {
    const data = await loadPatchedData((relPath, parsed) => {
      if (relPath === 'tuning.json' && !Array.isArray(parsed)) {
        delete (parsed.indulgence as Record<string, unknown>).soak_phase_cost;
        parsed.phases_per_day = 3;
      }
      if (relPath === 'beats/ch1_d01_d03.json' && !Array.isArray(parsed)) {
        const beats = parsed.beats as Array<Record<string, unknown>>;
        beats[0].location = 'unknown_location_id';
        beats[0].on_enter = { gain: ['unknown_card_id'] };
      }
    });

    const report = validateData(data);
    const refErrors = report.errors.filter((e) => e.ruleId === 'verify_references');
    expect(refErrors.some((e) => e.message.includes('unknown_location_id'))).toBe(true);
    expect(refErrors.some((e) => e.message.includes('unknown_card_id'))).toBe(true);

    const tuningErrors = report.errors.filter((e) => e.ruleId === 'Data.REQUIRED_TUNING_KEYS');
    expect(
      tuningErrors.some((e) => e.message.includes('indulgence.soak_phase_cost') && e.source === 'tuning.json'),
    ).toBe(true);
    expect(
      tuningErrors.some((e) => e.message.includes('phases_per_day=3') && e.source === 'tuning.json'),
    ).toBe(true);
  });

  it('catches unknown condition operators, effect keys, and malformed composite condition containers (lint_vocabulary)', async () => {
    const data = await loadPatchedData((relPath, parsed) => {
      if (relPath === 'beats/ch1_d01_d03.json' && !Array.isArray(parsed)) {
        const beats = parsed.beats as Array<Record<string, unknown>>;
        beats[0].condition = { unknown_condition_op: 1 };
        beats[0].on_enter = { unknown_effect_key: true };
        beats[1].condition = { all: {} };
        beats[2].condition = { any: 'bad' };
        beats[3].condition = { count_at_least: { n: 1, of: {} } };
        beats[4].condition = { not: null };
      }
    });

    const report = validateData(data);
    const vocabErrors = report.errors.filter((e) => e.ruleId === 'lint_vocabulary');
    expect(vocabErrors.some((e) => e.message.includes('unknown_condition_op'))).toBe(true);
    expect(vocabErrors.some((e) => e.message.includes('unknown_effect_key'))).toBe(true);
    expect(vocabErrors.some((e) => e.message.includes('all 必須為非空 Array'))).toBe(true);
    expect(vocabErrors.some((e) => e.message.includes('any 必須為非空 Array'))).toBe(true);
    expect(
      vocabErrors.some((e) => e.message.includes('count_at_least.of 必須為非空 Array')),
    ).toBe(true);
    expect(
      vocabErrors.some((e) => e.message.includes('condition 子條件不得為 null 或省略')),
    ).toBe(true);
  });

  it('catches non-array or missing ending page list fields (lint_endings)', async () => {
    const data = await loadPatchedData((relPath, parsed) => {
      if (relPath === 'endings.json' && Array.isArray(parsed)) {
        const replaced = parsed.find(
          (item) => (item as Record<string, unknown>).id === 'ending_replaced',
        ) as Record<string, unknown> | undefined;
        if (replaced) {
          const firstSeen = replaced.first_seen as Record<string, unknown>;
          firstSeen.prefix_pages = {};
          const repeat = replaced.repeat as Record<string, unknown>;
          delete repeat.suffix_pages;
          const vgs = replaced.variant_groups as Array<Record<string, unknown>>;
          const rules = vgs[0].rules as Array<Record<string, unknown>>;
          rules[0].first_seen_pages = {};
        }
      }
    });

    const report = validateData(data);
    const endingErrors = report.errors.filter((e) => e.ruleId === 'lint_endings');
    expect(
      endingErrors.some((e) =>
        e.message.includes('ending_replaced [first_seen.prefix_pages]：頁面列表必須為 Array'),
      ),
    ).toBe(true);
    expect(
      endingErrors.some((e) =>
        e.message.includes('ending_replaced [repeat.suffix_pages]：頁面列表必須為 Array'),
      ),
    ).toBe(true);
    expect(
      endingErrors.some((e) =>
        e.message.includes('first_seen_pages]：頁面列表必須為 Array'),
      ),
    ).toBe(true);
  });

  it('distinguishes warnings (lint_missing_reject_reason & exempted free slots) from errors (non-exempted free-slot panel)', async () => {
    const warnOnlyData = await loadPatchedData((relPath, parsed) => {
      if (relPath === 'beats/ch1_d01_d03.json' && !Array.isArray(parsed)) {
        const beats = parsed.beats as Array<Record<string, unknown>>;
        beats[0].requires = { day_at_least: 1 };
        delete beats[0].reject_reason;
      }
    });

    const warnReport = validateData(warnOnlyData);
    expect(warnReport.errors).toEqual([]);
    expect(
      warnReport.warnings.some(
        (w) => w.ruleId === 'lint_missing_reject_reason' && w.message.includes('沒有 reject_reason'),
      ),
    ).toBe(true);

    const errorData = await loadPatchedData((relPath, parsed) => {
      if (relPath === 'beats/ch1_d01_d03.json' && !Array.isArray(parsed)) {
        const beats = parsed.beats as Array<Record<string, unknown>>;
        beats.push({
          id: 'unexempted_free_only_beat',
          location: 'oldstreet',
          when: { day: 32, phase: 'afternoon' },
          text: 'test',
          slots: [
            {
              id: 'free_choice_slot',
              choice_group: 'cg_test',
              accepts: [],
              on_place: { text: 'chosen' },
            },
          ],
        });
      }
    });

    const errReport = validateData(errorData);
    expect(
      errReport.errors.some(
        (e) =>
          e.ruleId === 'lint_free_slot_rules' &&
          e.source.includes('unexempted_free_only_beat') &&
          e.message.includes('違反 SCHEMA 同面板規約'),
      ),
    ).toBe(true);
  });

  it('catches bad encounter next_round and unreachable / cyclic round graphs (lint_encounters)', async () => {
    const danglingData = await loadPatchedData((relPath, parsed) => {
      if (relPath === 'beats/ch1_nights.json' && !Array.isArray(parsed)) {
        const beats = parsed.beats as Array<Record<string, unknown>>;
        const encBeat = beats.find((b) => b.encounter !== undefined);
        if (encBeat && typeof encBeat.encounter === 'object' && encBeat.encounter !== null) {
          const rounds = (encBeat.encounter as { rounds: Array<Record<string, unknown>> }).rounds;
          const responses = rounds[0].responses as Array<Record<string, unknown>>;
          responses[0].next_round = 'ghost_round_id';
        }
      }
    });

    const danglingReport = validateData(danglingData);
    expect(
      danglingReport.errors.some(
        (e) =>
          e.ruleId === 'lint_encounters' &&
          e.message.includes('next_round 引用不存在的 round -> ghost_round_id'),
      ),
    ).toBe(true);

    const unreachableCycleData = await loadPatchedData((relPath, parsed) => {
      if (relPath === 'beats/ch1_nights.json' && !Array.isArray(parsed)) {
        const beats = parsed.beats as Array<Record<string, unknown>>;
        const encBeat = beats.find((b) => b.encounter !== undefined);
        if (encBeat && typeof encBeat.encounter === 'object' && encBeat.encounter !== null) {
          const rounds = (encBeat.encounter as { rounds: Array<Record<string, unknown>> }).rounds;
          rounds.push({
            id: 'r_unreachable_self_loop',
            demand: 'd',
            responses: [
              {
                id: 'resp_loop',
                accepts: ['protagonist'],
                consume_card: false,
                next_round: 'r_unreachable_self_loop',
                on_resolve: { text: 't' },
              },
            ],
            fallback: {
              next_round: 'r_unreachable_self_loop',
              on_resolve: { text: 'f' },
            },
          });
        }
      }
    });

    const cycleReport = validateData(unreachableCycleData);
    expect(
      cycleReport.errors.some(
        (e) =>
          e.ruleId === 'lint_encounters' &&
          e.message.includes('round r_unreachable_self_loop 不可從第一回合到達'),
      ),
    ).toBe(true);
    expect(
      cycleReport.errors.some(
        (e) =>
          e.ruleId === 'lint_encounters' &&
          e.message.includes('round graph 不得存在任何 cycle'),
      ),
    ).toBe(true);
  });

  it('catches missing night location desc and day_counterpart name spoilers (lint_night_location_descs)', async () => {
    const missingDescData = await loadPatchedData((relPath, parsed) => {
      if (relPath === 'locations.json' && !Array.isArray(parsed)) {
        const nightLocs = parsed.night as Array<Record<string, unknown>>;
        const nExit = nightLocs.find((l) => l.id === 'n_exit');
        if (nExit) {
          nExit.desc = '   ';
        }
      }
    });

    const missingDescReport = validateData(missingDescData);
    expect(
      missingDescReport.errors.some(
        (e) =>
          e.ruleId === 'lint_night_location_descs' &&
          e.source === 'n_exit' &&
          e.message.includes('night desc 為空'),
      ),
    ).toBe(true);

    const spoilerDescData = await loadPatchedData((relPath, parsed) => {
      if (relPath === 'locations.json' && !Array.isArray(parsed)) {
        const nightLocs = parsed.night as Array<Record<string, unknown>>;
        const nExit = nightLocs.find((l) => l.id === 'n_exit');
        if (nExit) {
          nExit.desc = '站在山泉閣外的石階頂端向下望去，整條街空無一人。';
        }
      }
    });

    const spoilerReport = validateData(spoilerDescData);
    expect(
      spoilerReport.errors.some(
        (e) =>
          e.ruleId === 'lint_night_location_descs' &&
          e.source === 'n_exit' &&
          e.message.includes('山泉閣'),
      ),
    ).toBe(true);
  });

  it('CLI runner succeeds on formal data and fails with exitCode 1 on injected bad fixture directory or missing file', async () => {
    const formalRes = await runLintData([], DATA_DIR);
    expect(formalRes.exitCode).toBe(0);
    expect(formalRes.report?.errors.length).toBe(0);
    expect(formalRes.report?.warnings.length).toBe(4);

    const tempRoot = resolve(tmpdir());
    const tempDir = await mkdtemp(join(tempRoot, 'rf-w2b-lint-'));
    try {
      await cp(DATA_DIR, tempDir, { recursive: true });

      // 注入壞夜間 desc 到暫存目錄，確認 CLI exitCode === 1
      const locPath = join(tempDir, 'locations.json');
      const locs = JSON.parse(await readFile(locPath, 'utf8')) as {
        day: unknown[];
        night: Array<Record<string, unknown>>;
      };
      locs.night[0].desc = '';
      await writeFile(locPath, JSON.stringify(locs, null, 2));

      const badRes = await runLintData(['--data-dir', tempDir]);
      expect(badRes.exitCode).toBe(1);
      expect(
        badRes.report?.errors.some((e) => e.ruleId === 'lint_night_location_descs'),
      ).toBe(true);

      // 移除必要檔 tuning.json，確認載入錯誤附檔名且 exitCode === 1
      await rm(join(tempDir, 'tuning.json'), { force: true });
      const missingRes = await runLintData([], tempDir);
      expect(missingRes.exitCode).toBe(1);
      expect(missingRes.loadError).toContain('tuning.json');
    } finally {
      if (dirname(resolve(tempDir)) !== tempRoot) {
        throw new Error('Unexpected fixture cleanup path');
      }
      await rm(tempDir, { recursive: true, force: true });
    }
  });
});
