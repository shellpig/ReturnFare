import { beforeAll, describe, expect, it } from 'vitest';
import {
  ENDING_SNAPSHOT_KEYS,
  HISTORY_RECORD_KEYS,
  RETURNED_KNOWLEDGE_CARD,
  buildEndingPlan,
  parseEndingSnapshot,
  resolveEnding,
  resolveRef,
  startEndingOnDraft,
} from '../src/core/ending';
import {
  createInitialSnapshot,
  initializeRun,
} from '../src/core/run-initialization';
import { createGame } from '../src/core/state';
import type {
  ActiveEndingSnapshot,
  EndingHistoryRecord,
  Game,
  GameSnapshot,
} from '../src/core/state-types';
import { loadGameDataNode } from '../src/data/load-node';
import type { Beat, GameData } from '../src/data/types';

type AnyRec = Record<string, any>; // eslint-disable-line @typescript-eslint/no-explicit-any

let data: GameData;

beforeAll(async () => {
  data = await loadGameDataNode();
});

function replacedRecord(overrides: Partial<EndingHistoryRecord> = {}): EndingHistoryRecord {
  return {
    run_number: 1,
    ending_id: 'ending_replaced',
    opening_choice_id: 'take_family_album',
    ended_day: 45,
    ended_phase: 'evening',
    partner_variant: 'none',
    livelihood_variant: 'none_low',
    inn_appearance_variant: 'none',
    festival_proxy_npc: 'ajie',
    knowledge_gained_this_run: [],
    ...overrides,
  };
}

/** 單輪進行中的可信起點（D45 evening，已凍結代付者）。 */
function runState(edit?: (s: GameSnapshot) => void): GameSnapshot {
  const s = initializeRun(createInitialSnapshot(), data);
  s.flow.mode = 'run';
  s.run.opening_choice_id = 'take_family_album';
  s.run.day = 45;
  s.run.phase = 'evening';
  s.run.selected_festival_proxy_npc = 'ajie';
  edit?.(s);
  return s;
}

/** 以規則層的 buildEndingPlan 凍結結果後，直接放進 ending 模式的可信快照。 */
function endingState(
  endingId: string,
  sourceId: string,
  edit?: (s: GameSnapshot) => void,
): GameSnapshot {
  const s = runState(edit);
  const plan = buildEndingPlan(endingId, sourceId, s, data);
  if (!plan.ok) {
    throw new Error(`fixture plan failed: ${plan.reason_code} ${plan.reason_text}`);
  }
  s.flow.mode = 'ending';
  s.flow.active_ending = plan.snapshot;
  return s;
}

/** 逐頁走到可結算：未揭露就補完，已揭露且非末頁就翻頁。 */
function playToReady(game: Game): void {
  for (let guard = 0; guard < 64 && !game.endingView().can_complete; guard += 1) {
    const view = game.endingView();
    const res = view.page_revealed ? game.advanceEndingPage() : game.revealEndingPage();
    expect(res.ok).toBe(true);
  }
  expect(game.endingView().can_complete).toBe(true);
}

function pageText(ref: string): string {
  const page = resolveRef(ref, data);
  if (!page.ok) {
    throw new Error(`ref unresolved: ${ref}`);
  }
  return page.text;
}

function withEnding(id: string, patch: (ending: AnyRec) => void): GameData {
  const endings = data.endings.map((e) => {
    if (e.id !== id) {
      return e;
    }
    const copy = structuredClone(e) as AnyRec;
    patch(copy);
    return copy as unknown as typeof e;
  });
  return { ...data, endings, endingsById: new Map(endings.map((e) => [e.id, e])) };
}

function withBeat(base: GameData, beat: Beat): GameData {
  const beats = [...base.beats, beat];
  return { ...base, beats, beatsById: new Map(beats.map((b) => [b.id, b])) };
}

function endingTriggerBeat(effect: AnyRec): Beat {
  return {
    id: 'test_e1_trigger_beat',
    location: 'sanquan',
    when: { day: 1, phase: 'morning' },
    fixed: false,
    title: '結局測試格',
    text: '測試開場文本',
    slots: [
      {
        id: 'trigger_slot',
        occupant: null,
        label: '觸發結局',
        accepts: ['protagonist'],
        on_place: effect,
      },
    ],
  } as unknown as Beat;
}

const refuseHistory = (): EndingHistoryRecord => ({
  run_number: 1,
  ending_id: 'ending_refuse_boarding',
  opening_choice_id: 'refuse_boarding',
  ended_day: null,
  ended_phase: null,
  partner_variant: null,
  livelihood_variant: null,
  inn_appearance_variant: null,
  festival_proxy_npc: null,
  knowledge_gained_this_run: [],
});

function openingWithHistory(history: EndingHistoryRecord[], runNumber = 2): Game {
  const s = createInitialSnapshot();
  s.meta.run_number = runNumber;
  s.meta.ending_history.push(...history);
  return createGame(data, s);
}

describe('W6-E1 formal linear ending: refuse_boarding from the opening screen', () => {
  it('chooseOpening -> reveal/advance -> complete returns to opening without ever building a town run', () => {
    const game = openingWithHistory([replacedRecord()]);
    const fresh = createInitialSnapshot();
    expect(game.openingView()[2].available).toBe(true);
    expect(game.hasSeenEnding('ending_replaced')).toBe(true);
    expect(game.hasSeenEnding('ending_refuse_boarding')).toBe(false);

    // 非 ending 模式的 view 是零投影
    expect(game.endingView()).toEqual({
      page_text: '',
      page_index: 0,
      page_count: 0,
      page_revealed: false,
      is_last_page: false,
      can_skip: false,
      can_complete: false,
    });

    const res = game.chooseOpening('refuse_boarding');
    expect(res.ok).toBe(true);
    const snap = game.serialize();
    expect(snap.flow.mode).toBe('ending');
    // 沒有假小鎮 run
    expect(snap.run).toEqual(fresh.run);
    expect(snap.run.hand).toEqual([]);

    const ending = data.endingsById.get('ending_refuse_boarding') as AnyRec;
    const [p0, p1] = ending.first_seen.pages as AnyRec[];
    expect(snap.flow.active_ending).toEqual({
      ending_id: 'ending_refuse_boarding',
      source_id: 'opening_choice',
      run_number: 2,
      opening_choice_id: 'refuse_boarding',
      ended_day: null,
      ended_phase: null,
      partner_variant: null,
      livelihood_variant: null,
      inn_appearance_variant: null,
      festival_proxy_npc: null,
      knowledge_gained_this_run: [],
      page_refs: [
        `ending_refuse_boarding/first_seen/pages/${p0.id}`,
        `ending_refuse_boarding/first_seen/pages/${p1.id}`,
      ],
      page_index: 0,
      page_revealed: false,
      ready_to_complete: false,
    });
    expect(Object.keys(snap.flow.active_ending as object)).toEqual([...ENDING_SNAPSHOT_KEYS]);

    // view 只給當頁文字；其他頁文字不外流；首見不可跳過
    const v0 = game.endingView();
    expect(Object.keys(v0).sort()).toEqual([
      'can_complete',
      'can_skip',
      'is_last_page',
      'page_count',
      'page_index',
      'page_revealed',
      'page_text',
    ]);
    expect(v0.page_text).toBe(p0.text);
    expect(v0.page_count).toBe(2);
    expect(v0.is_last_page).toBe(false);
    expect(v0.can_skip).toBe(false);
    expect(JSON.stringify(v0)).not.toContain(p1.text);

    // 未揭露不能翻頁、不能結算
    expect(game.advanceEndingPage().reason_code).toBe('page_not_revealed');
    expect(game.completeEnding().reason_code).toBe('not_ready');

    expect(game.revealEndingPage().ok).toBe(true);
    expect(game.revealEndingPage().reason_code).toBe('already_revealed');
    expect(game.endingView().page_revealed).toBe(true);
    expect(game.endingView().can_complete).toBe(false);
    expect(game.advanceEndingPage().ok).toBe(true);
    expect(game.endingView().page_text).toBe(p1.text);
    expect(game.endingView().is_last_page).toBe(true);
    expect(game.completeEnding().reason_code).toBe('not_ready');
    expect(game.revealEndingPage().ok).toBe(true);
    expect(game.endingView().can_complete).toBe(true);
    // ready 之後頁面操作一律 wrong_ending_stage
    expect(game.revealEndingPage().reason_code).toBe('wrong_ending_stage');
    expect(game.advanceEndingPage().reason_code).toBe('wrong_ending_stage');
    expect(game.skipSeenEnding().reason_code).toBe('wrong_ending_stage');

    expect(game.completeEnding().ok).toBe(true);
    const done = game.serialize();
    expect(done.flow).toEqual({ mode: 'opening', active_ending: null });
    expect(done.run).toEqual(fresh.run);
    expect(done.meta.run_number).toBe(3);
    expect(done.meta.ending_history).toHaveLength(2);
    expect(done.meta.ending_history[1]).toEqual({
      run_number: 2,
      ending_id: 'ending_refuse_boarding',
      opening_choice_id: 'refuse_boarding',
      ended_day: null,
      ended_phase: null,
      partner_variant: null,
      livelihood_variant: null,
      inn_appearance_variant: null,
      festival_proxy_npc: null,
      knowledge_gained_this_run: [],
    });
    expect(Object.keys(done.meta.ending_history[1])).toEqual([...HISTORY_RECORD_KEYS]);
    expect(done.meta.knowledge[RETURNED_KNOWLEDGE_CARD]).toBe(true);
    expect(game.hasSeenEnding('ending_refuse_boarding')).toBe(true);
  });

  it('duplicate completeEnding is rejected and writes history exactly once', () => {
    const game = createGame(data, endingState('ending_inventory_be', 'ending_effect'));
    playToReady(game);
    expect(game.completeEnding().ok).toBe(true);
    const afterFirst = JSON.stringify(game.serialize());
    expect(game.serialize().meta.ending_history).toHaveLength(1);

    const second = game.completeEnding();
    expect(second.ok).toBe(false);
    expect(second.reason_code).toBe('not_ending');
    expect(JSON.stringify(game.serialize())).toBe(afterFirst);
    expect(game.serialize().meta.ending_history).toHaveLength(1);
    expect(game.serialize().meta.run_number).toBe(2);
  });

  it('first-seen vs repeat is judged by same-id history only, never by run number', () => {
    // 輪數很大但只看過 ending_replaced：不上車仍是首見，不可跳過
    const firstSeen = openingWithHistory([replacedRecord()], 9);
    firstSeen.chooseOpening('refuse_boarding');
    expect(firstSeen.endingView().can_skip).toBe(false);
    expect(firstSeen.endingView().page_count).toBe(2);
    const before = JSON.stringify(firstSeen.serialize());
    const denied = firstSeen.skipSeenEnding();
    expect(denied.ok).toBe(false);
    expect(denied.reason_code).toBe('ending_not_seen');
    expect(JSON.stringify(firstSeen.serialize())).toBe(before);

    // 輪數是 2 但同 id 已有紀錄：重見，單頁摘要，可跳過到 complete 落點
    const repeat = openingWithHistory([replacedRecord(), refuseHistory()], 2);
    repeat.chooseOpening('refuse_boarding');
    const view = repeat.endingView();
    expect(view.page_count).toBe(1);
    expect(view.can_skip).toBe(true);
    const ending = data.endingsById.get('ending_refuse_boarding') as AnyRec;
    expect(view.page_text).toBe(ending.repeat.pages[0].text);
    expect(ending.repeat.skip_to).toBe('complete');

    const historyBefore = JSON.stringify(repeat.serialize().meta.ending_history);
    expect(repeat.skipSeenEnding().ok).toBe(true);
    // 任何跳過都不寫 history
    expect(JSON.stringify(repeat.serialize().meta.ending_history)).toBe(historyBefore);
    expect(repeat.endingView().page_revealed).toBe(true);
    expect(repeat.endingView().can_complete).toBe(true);
    expect(repeat.endingView().can_skip).toBe(false);
    expect(repeat.completeEnding().ok).toBe(true);
    expect(repeat.serialize().meta.ending_history).toHaveLength(3);
  });

  it('repeat skip lands exactly on the data-authored skip_to page, not simply the last page', () => {
    // ending_replaced 的正式 skip_to 與末頁同一頁，無法分辨；用隔離 fixture 把落點指到中間頁。
    const fixture = withEnding('ending_replaced', (e) => {
      e.repeat.skip_to = e.repeat.prefix_pages[0].id;
    });
    const s = runState();
    s.meta.ending_history.push(replacedRecord());
    const plan = buildEndingPlan('ending_replaced', 'd45_coda', s, fixture);
    expect(plan.ok).toBe(true);
    if (!plan.ok) return;
    s.flow.mode = 'ending';
    s.flow.active_ending = plan.snapshot;
    expect(plan.snapshot.page_refs.length).toBeGreaterThan(2);

    const game = createGame(fixture, s);
    expect(game.endingView().can_skip).toBe(true);
    expect(game.skipSeenEnding().ok).toBe(true);
    const view = game.endingView();
    expect(view.page_index).toBe(0); // prefix 的第 0 頁，而不是末頁
    expect(view.page_revealed).toBe(true);
    expect(view.is_last_page).toBe(false);
    expect(view.can_complete).toBe(false);
    expect(view.can_skip).toBe(true);

    // 落點不在本次頁面內 -> data_conflict 且零變化
    const broken = withEnding('ending_replaced', (e) => {
      e.repeat.skip_to = 'no_such_page';
    });
    const g2 = createGame(broken, s);
    const before = JSON.stringify(g2.serialize());
    const res = g2.skipSeenEnding();
    expect(res.ok).toBe(false);
    expect(res.reason_code).toBe('data_conflict');
    expect(JSON.stringify(g2.serialize())).toBe(before);
  });
});

describe('W6-E1 normal ending resolver: representative combinations', () => {
  const pageRefOf = (groupId: string, ruleId: string, first = true): string => {
    const ending = data.endingsById.get('ending_replaced') as AnyRec;
    const group = (ending.variant_groups as AnyRec[]).find((g) => g.id === groupId) as AnyRec;
    const rule = (group.rules as AnyRec[]).find((r) => r.id === ruleId) as AnyRec;
    const page = (rule[first ? 'first_seen_pages' : 'repeat_pages'] as AnyRec[])[0];
    return `ending_replaced/${first ? 'first_seen' : 'repeat'}/variant_groups/${groupId}/${ruleId}/${page.id}`;
  };

  it('first-seen order is prefix -> variant groups in data order -> lookup fragments -> suffix', () => {
    const s = runState((st) => {
      st.run.flags.accepted_inn = true;
      for (const sw of ['s1', 's2', 's3', 's4']) st.run.switches[sw] = true;
      st.run.flags.repaired_sign = true;
      st.run.flags.invited_ajie = true;
      st.run.selected_festival_proxy_npc = 'acai';
    });
    const res = resolveEnding('ending_replaced', s, data);
    expect(res.ok).toBe(true);
    if (!res.ok) return;
    expect(res.branch).toBe('first_seen');
    expect(res.variants).toEqual({
      livelihood_variant: 'uncle_high',
      inn_appearance_variant: 'sign',
      partner_variant: 'ajie',
    });
    // partner 命中 ajie：uninvited_proxy 不啟用，即使代付者已凍結為 acai
    expect(res.page_refs).toEqual([
      'ending_replaced/first_seen/prefix_pages/replacement',
      pageRefOf('livelihood', 'uncle_high'),
      pageRefOf('inn_appearance', 'sign'),
      pageRefOf('partner', 'ajie'),
      'ending_replaced/first_seen/suffix_pages/long_return',
    ]);
    // 每個 ref 都能解析回資料原文
    expect(pageText(res.page_refs[0])).toBe(
      ((data.endingsById.get('ending_replaced') as AnyRec).first_seen.prefix_pages[0] as AnyRec).text,
    );

    // 不邀請：partner=none 才啟用 lookup，依凍結代付者命中 entries
    const none = runState((st) => {
      st.run.selected_festival_proxy_npc = 'acai';
    });
    const res2 = resolveEnding('ending_replaced', none, data);
    expect(res2.ok).toBe(true);
    if (!res2.ok) return;
    expect(res2.page_refs).toEqual([
      'ending_replaced/first_seen/prefix_pages/replacement',
      pageRefOf('livelihood', 'none_low'),
      pageRefOf('inn_appearance', 'none'),
      pageRefOf('partner', 'none'),
      'ending_replaced/first_seen/lookup_fragments/uninvited_proxy/acai/proxy_acai_long',
      'ending_replaced/first_seen/suffix_pages/long_return',
    ]);
  });

  it('repeat branch uses repeat pages for every dimension and short suffix', () => {
    const s = runState((st) => {
      st.meta.ending_history.push(replacedRecord());
      st.run.flags.accepted_outside_job = true;
      st.run.switches.s1 = true;
      st.run.switches.s2 = true;
      st.run.flags.invited_awei = true;
    });
    const res = resolveEnding('ending_replaced', s, data);
    expect(res.ok).toBe(true);
    if (!res.ok) return;
    expect(res.branch).toBe('repeat');
    expect(res.page_refs).toEqual([
      'ending_replaced/repeat/prefix_pages/again_replaced',
      pageRefOf('livelihood', 'boss_mid', false),
      pageRefOf('inn_appearance', 'none', false),
      pageRefOf('partner', 'awei', false),
      'ending_replaced/repeat/suffix_pages/short_return',
    ]);
  });

  it('rule precedence follows data order; a missing frozen proxy under partner=none is a data_conflict', () => {
    const both = runState((st) => {
      st.run.flags.invited_ajie = true;
      st.run.flags.invited_awei = true;
      st.run.flags.accepted_inn = true;
      st.run.flags.accepted_job = true;
      st.run.flags.repaired_windows = true;
      st.run.flags.repaired_pipes = true;
    });
    const res = resolveEnding('ending_replaced', both, data);
    expect(res.ok && res.variants).toEqual({
      livelihood_variant: 'uncle_low',
      inn_appearance_variant: 'pipes',
      partner_variant: 'ajie',
    });

    const noProxy = runState((st) => {
      st.run.selected_festival_proxy_npc = null;
    });
    expect(resolveEnding('ending_replaced', noProxy, data)).toEqual({
      ok: false,
      reason_code: 'data_conflict',
    });
    expect(resolveEnding('no_such_ending', both, data)).toEqual({
      ok: false,
      reason_code: 'unknown_ending',
    });
  });

  // 每個 data-authored variant rule 至少一個命中證據（小型參數表）。
  type RuleCase = {
    group: string;
    id: string;
    setup: (s: GameSnapshot) => void;
  };
  const switches = (n: number) => (s: GameSnapshot) => {
    for (let i = 1; i <= n; i += 1) s.run.switches[`s${i}`] = true;
  };
  const flagged = (flag: string | null, n: number) => (s: GameSnapshot) => {
    if (flag) s.run.flags[flag] = true;
    switches(n)(s);
  };
  const ruleCases: RuleCase[] = [
    { group: 'livelihood', id: 'uncle_high', setup: flagged('accepted_inn', 4) },
    { group: 'livelihood', id: 'uncle_mid', setup: flagged('accepted_inn', 2) },
    { group: 'livelihood', id: 'uncle_low', setup: flagged('accepted_inn', 0) },
    { group: 'livelihood', id: 'boss_high', setup: flagged('accepted_outside_job', 4) },
    { group: 'livelihood', id: 'boss_mid', setup: flagged('accepted_outside_job', 2) },
    { group: 'livelihood', id: 'boss_low', setup: flagged('accepted_outside_job', 0) },
    { group: 'livelihood', id: 'zhou_high', setup: flagged('accepted_job', 4) },
    { group: 'livelihood', id: 'zhou_mid', setup: flagged('accepted_job', 2) },
    { group: 'livelihood', id: 'zhou_low', setup: flagged('accepted_job', 0) },
    { group: 'livelihood', id: 'none_high', setup: flagged(null, 4) },
    { group: 'livelihood', id: 'none_mid', setup: flagged(null, 2) },
    {
      group: 'livelihood',
      id: 'none_mid',
      // s6 累計進度也算一項（switch_progress_at_least s6 >= 3）
      setup: (s) => {
        s.run.switches.s1 = true;
        s.run.switch_progress.s6 = 3;
      },
    },
    { group: 'livelihood', id: 'none_low', setup: flagged(null, 0) },
    { group: 'inn_appearance', id: 'sign', setup: (s) => void (s.run.flags.repaired_sign = true) },
    { group: 'inn_appearance', id: 'pipes', setup: (s) => void (s.run.flags.repaired_pipes = true) },
    { group: 'inn_appearance', id: 'windows', setup: (s) => void (s.run.flags.repaired_windows = true) },
    { group: 'inn_appearance', id: 'none', setup: () => undefined },
    { group: 'partner', id: 'ajie', setup: (s) => void (s.run.flags.invited_ajie = true) },
    { group: 'partner', id: 'awei', setup: (s) => void (s.run.flags.invited_awei = true) },
    { group: 'partner', id: 'none', setup: () => undefined },
  ];

  it('the parameter table covers every rule id of every data-authored variant group', () => {
    const ending = data.endingsById.get('ending_replaced') as AnyRec;
    for (const group of ending.variant_groups as AnyRec[]) {
      const dataIds = (group.rules as AnyRec[]).map((r) => r.id as string).sort();
      const tableIds = [
        ...new Set(ruleCases.filter((c) => c.group === group.id).map((c) => c.id)),
      ].sort();
      expect(tableIds).toEqual(dataIds);
    }
  });

  it.each(ruleCases.map((c, i) => [`${c.group}/${c.id} #${i}`, c] as const))(
    'rule %s hits with its own page in first-seen and repeat branches',
    (_name, c) => {
      const ending = data.endingsById.get('ending_replaced') as AnyRec;
      const group = (ending.variant_groups as AnyRec[]).find((g) => g.id === c.group) as AnyRec;
      const rule = (group.rules as AnyRec[]).find((r) => r.id === c.id) as AnyRec;

      for (const first of [true, false]) {
        const s = runState((st) => {
          if (!first) st.meta.ending_history.push(replacedRecord());
          c.setup(st);
        });
        const res = resolveEnding('ending_replaced', s, data);
        expect(res.ok).toBe(true);
        if (!res.ok) return;
        expect(res.variants[group.history_field as string]).toBe(c.id);
        const pages = rule[first ? 'first_seen_pages' : 'repeat_pages'] as AnyRec[];
        const expectedRef = `ending_replaced/${first ? 'first_seen' : 'repeat'}/variant_groups/${c.group}/${c.id}/${pages[0].id}`;
        expect(res.page_refs).toContain(expectedRef);
        expect(pageText(expectedRef)).toBe(pages[0].text);
      }
    },
  );

  it.each(['ajie', 'awei', 'acai'])(
    'lookup fragment uninvited_proxy resolves the frozen proxy %s only when partner=none',
    (npc) => {
      const ending = data.endingsById.get('ending_replaced') as AnyRec;
      const lf = (ending.lookup_fragments as AnyRec[])[0];
      const entry = (lf.entries as AnyRec[]).find((e) => e.value === npc) as AnyRec;
      const s = runState((st) => {
        st.run.selected_festival_proxy_npc = npc;
      });
      const res = resolveEnding('ending_replaced', s, data);
      expect(res.ok).toBe(true);
      if (!res.ok) return;
      const ref = `ending_replaced/first_seen/lookup_fragments/uninvited_proxy/${npc}/${entry.first_seen_pages[0].id}`;
      expect(res.page_refs).toContain(ref);
      expect(pageText(ref)).toBe(entry.first_seen_pages[0].text);

      const invited = runState((st) => {
        st.run.selected_festival_proxy_npc = npc;
        st.run.flags.invited_ajie = true;
      });
      const res2 = resolveEnding('ending_replaced', invited, data);
      expect(res2.ok && res2.page_refs.some((r) => r.includes('lookup_fragments'))).toBe(false);
    },
  );
});

describe('W6-E1 ending plan: closed source pairs, snapshot nullable matrix, parser', () => {
  it('accepts exactly the four source/ending pairs and rejects every other combination', () => {
    const s = runState();
    const pairs: Array<[string, string]> = [
      ['ending_madness_be', 'madness_cap'],
      ['ending_inventory_be', 'ending_effect'],
      ['ending_replaced', 'd45_coda'],
    ];
    for (const [endingId, source] of pairs) {
      const plan = buildEndingPlan(endingId, source, s, data);
      expect(plan.ok).toBe(true);
      if (plan.ok) {
        expect(plan.snapshot.source_id).toBe(source);
        // 與 parser 往返一致
        expect(parseEndingSnapshot(plan.snapshot, data)).toEqual(plan.snapshot);
      }
    }
    // opening_choice 在 run 生命週期不成立；只有開局入口（allowOpeningSource）收得起
    const viaRun = buildEndingPlan('ending_refuse_boarding', 'opening_choice', s, data);
    expect(viaRun.ok).toBe(false);
    expect(!viaRun.ok && viaRun.reason_code).toBe('invalid_ending_source');
    const viaOpening = buildEndingPlan('ending_refuse_boarding', 'opening_choice', s, data, true);
    expect(viaOpening.ok).toBe(true);

    // 配錯、未知 source、未知 ending
    for (const [endingId, source] of [
      ['ending_inventory_be', 'madness_cap'],
      ['ending_madness_be', 'ending_effect'],
      ['ending_replaced', 'ending_effect'],
      ['ending_madness_be', 'd45_coda'],
      ['ending_madness_be', 'nope'],
      ['ending_madness_be', 'toString'],
    ]) {
      const plan = buildEndingPlan(endingId, source, s, data);
      expect(plan.ok).toBe(false);
      expect(!plan.ok && plan.reason_code).toBe('invalid_ending_source');
    }
    const unknown = buildEndingPlan('ending_none', 'madness_cap', s, data);
    expect(!unknown.ok && unknown.reason_code).toBe('unknown_ending');
  });

  it('snapshot fields and nullable matrix follow Godot per ending (BE keeps run info, refuse is all-null)', () => {
    const s = runState((st) => {
      // 取得順序與 cards.json 順序相反，確認輸出依 cards 順序；開輪既有知識不算本輪新增
      const knowledge = data.cards.filter((c) => c.slotless === true && c.type === 'knowledge');
      st.meta.knowledge[knowledge[0].id] = true;
      st.run.knowledge_at_start = { ...st.meta.knowledge };
      st.meta.knowledge[knowledge[3].id] = true;
      st.meta.knowledge[knowledge[1].id] = true;
      st.run.day = 12;
      st.run.phase = 'night';
      st.run.selected_festival_proxy_npc = null;
    });
    const knowledge = data.cards.filter((c) => c.slotless === true && c.type === 'knowledge');
    const be = buildEndingPlan('ending_madness_be', 'madness_cap', s, data);
    expect(be.ok).toBe(true);
    if (!be.ok) return;
    expect(be.snapshot).toEqual({
      ending_id: 'ending_madness_be',
      source_id: 'madness_cap',
      run_number: 1,
      opening_choice_id: 'take_family_album',
      ended_day: 12,
      ended_phase: 'night',
      partner_variant: null,
      livelihood_variant: null,
      inn_appearance_variant: null,
      festival_proxy_npc: null, // BE 沒有凍結值時為 null
      knowledge_gained_this_run: [knowledge[1].id, knowledge[3].id],
      page_refs: [expect.stringMatching(/^ending_madness_be\/first_seen\/pages\//)],
      page_index: 0,
      page_revealed: false,
      ready_to_complete: false,
    });
    expect(Object.keys(be.snapshot)).toEqual([...ENDING_SNAPSHOT_KEYS]);

    // BE 有凍結代付者就複製
    s.run.selected_festival_proxy_npc = 'awei';
    const beProxy = buildEndingPlan('ending_inventory_be', 'ending_effect', s, data);
    expect(beProxy.ok && beProxy.snapshot.festival_proxy_npc).toBe('awei');

    // 沒有 opening_choice_id 的 run（trace 起點）-> null
    s.run.opening_choice_id = null;
    const noOpening = buildEndingPlan('ending_madness_be', 'madness_cap', s, data);
    expect(noOpening.ok && noOpening.snapshot.opening_choice_id).toBeNull();

    // 正常結局：variant 三欄 + 凍結代付者；缺凍結值或非候選拒絕
    const replaced = buildEndingPlan('ending_replaced', 'd45_coda', s, data);
    expect(replaced.ok).toBe(true);
    if (replaced.ok) {
      expect(replaced.snapshot.livelihood_variant).toBe('none_low');
      expect(replaced.snapshot.inn_appearance_variant).toBe('none');
      expect(replaced.snapshot.partner_variant).toBe('none');
      expect(replaced.snapshot.festival_proxy_npc).toBe('awei');
    }
    s.run.selected_festival_proxy_npc = null;
    const missing = buildEndingPlan('ending_replaced', 'd45_coda', s, data);
    expect(!missing.ok && missing.reason_code).toBe('data_conflict');
    const ineligible = data.npcs.find((n) => !n.festival_proxy_eligible);
    expect(ineligible).toBeDefined();
    s.run.selected_festival_proxy_npc = ineligible?.id ?? '';
    const notCandidate = buildEndingPlan('ending_replaced', 'd45_coda', s, data);
    expect(!notCandidate.ok && notCandidate.reason_code).toBe('data_conflict');

    // 不上車：run 資訊一律 null/空，即使來源狀態殘留值
    s.run.selected_festival_proxy_npc = 'awei';
    const refuse = buildEndingPlan('ending_refuse_boarding', 'opening_choice', s, data, true);
    expect(refuse.ok).toBe(true);
    if (refuse.ok) {
      expect(refuse.snapshot.opening_choice_id).toBe('refuse_boarding');
      expect(refuse.snapshot.ended_day).toBeNull();
      expect(refuse.snapshot.ended_phase).toBeNull();
      expect(refuse.snapshot.festival_proxy_npc).toBeNull();
      expect(refuse.snapshot.knowledge_gained_this_run).toEqual([]);
    }
  });

  it('parser rejects missing/extra fields, empty-string-for-null, inconsistent refs, bad matrices and bad ready flags', () => {
    const base = endingState('ending_replaced', 'd45_coda', (st) => {
      st.run.flags.invited_ajie = true;
    }).flow.active_ending as ActiveEndingSnapshot;
    expect(parseEndingSnapshot(base, data)).toEqual(base);

    const mutate = (fn: (c: AnyRec) => void): unknown => {
      const copy = structuredClone(base) as AnyRec;
      fn(copy);
      return parseEndingSnapshot(copy, data);
    };
    expect(mutate((c) => delete c.source_id)).toBeNull();
    expect(mutate((c) => (c.extra = 1))).toBeNull();
    expect(mutate((c) => (c.opening_choice_id = ''))).toBeNull(); // 空字串不能代 null
    expect(mutate((c) => (c.source_id = 'madness_cap'))).toBeNull(); // 與 ending 不配對
    expect(mutate((c) => (c.partner_variant = 'ghost'))).toBeNull(); // 非 rule id
    expect(mutate((c) => (c.partner_variant = 'none'))).toBeNull(); // 與 page ref 的 rule 不一致
    expect(mutate((c) => (c.festival_proxy_npc = null))).toBeNull(); // 正常結局必須有代付者
    expect(mutate((c) => (c.ended_phase = null))).toBeNull();
    expect(mutate((c) => (c.ended_day = 46))).toBeNull();
    expect(mutate((c) => (c.run_number = 0))).toBeNull();
    expect(mutate((c) => (c.page_index = c.page_refs.length))).toBeNull();
    expect(mutate((c) => (c.page_refs[0] = 'ending_replaced/first_seen/prefix_pages/ghost'))).toBeNull();
    expect(mutate((c) => (c.page_refs[1] = c.page_refs[1].replace('first_seen', 'repeat')))).toBeNull(); // branch 混用
    expect(mutate((c) => (c.page_refs = []))).toBeNull();
    expect(mutate((c) => (c.ready_to_complete = true))).toBeNull(); // 不在末頁已揭露卻 ready
    expect(
      mutate((c) => {
        c.page_index = c.page_refs.length - 1;
        c.page_revealed = true;
      }),
    ).toBeNull(); // 末頁已揭露但 ready=false
    expect(mutate((c) => (c.knowledge_gained_this_run = ['no_such_card']))).toBeNull();
    expect(mutate((c) => (c.knowledge_gained_this_run = ['protagonist']))).toBeNull(); // 非知識卡

    const refuse = buildEndingPlan('ending_refuse_boarding', 'opening_choice', runState(), data, true);
    expect(refuse.ok).toBe(true);
    if (!refuse.ok) return;
    const mutateRefuse = (fn: (c: AnyRec) => void): unknown => {
      const copy = structuredClone(refuse.snapshot) as AnyRec;
      fn(copy);
      return parseEndingSnapshot(copy, data);
    };
    expect(mutateRefuse((c) => (c.ended_day = 3))).toBeNull(); // 不上車沒有結束日
    expect(mutateRefuse((c) => (c.opening_choice_id = 'take_family_album'))).toBeNull();
    expect(mutateRefuse((c) => (c.festival_proxy_npc = 'ajie'))).toBeNull();
    expect(mutateRefuse((c) => (c.livelihood_variant = 'none_low'))).toBeNull(); // linear 沒有 group
  });

  it('startEndingOnDraft refuses wrong mode and an already-active ending without touching the draft', () => {
    const run = runState();
    const wrongMode = structuredClone(run);
    wrongMode.flow.mode = 'opening';
    const before = JSON.stringify(wrongMode);
    const r1 = startEndingOnDraft(wrongMode, 'ending_madness_be', 'madness_cap', data, { fromMode: 'run' });
    expect(!r1.ok && r1.reason_code).toBe('not_run');
    expect(JSON.stringify(wrongMode)).toBe(before);

    const active = endingState('ending_madness_be', 'madness_cap');
    const r2 = startEndingOnDraft(
      Object.assign(active, { flow: { ...active.flow, mode: 'run' as const } }),
      'ending_madness_be',
      'madness_cap',
      data,
      { fromMode: 'run' },
    );
    expect(!r2.ok && r2.reason_code).toBe('ending_active');

    const ok = structuredClone(run);
    expect(startEndingOnDraft(ok, 'ending_madness_be', 'madness_cap', data, { fromMode: 'run' }).ok).toBe(true);
    expect(ok.flow.mode).toBe('ending');
  });
});

describe('W6-E1 ending request pipeline through the formal effect pipeline (isolated fixture beat)', () => {
  const knowledgeIds = () =>
    data.cards.filter((c) => c.slotless === true && c.type === 'knowledge').map((c) => c.id);

  it('an ending effect plus bookkeeping commits together, freezes the result, and completes to opening', () => {
    const [k0, k1, k2] = knowledgeIds();
    const fixture = withBeat(
      data,
      endingTriggerBeat({
        text: '準備進入結局',
        // 故意反序取得：快照必須按 cards 順序
        gain: [k2, k0],
        flag: { ending_flag_kept: true },
        ending: 'ending_inventory_be',
      }),
    );
    void k1;
    const game = createGame(fixture);
    expect(game.chooseOpening('take_family_album').ok).toBe(true);
    const runBefore = game.serialize();

    let notifyCount = 0;
    game.subscribe(() => {
      notifyCount += 1;
    });
    const res = game.tryPlace('protagonist', 'test_e1_trigger_beat', 'trigger_slot');
    expect(res.ok).toBe(true);
    expect(res.lines).toEqual(['準備進入結局']);
    expect(notifyCount).toBe(1); // 一次提交、一次通知

    const snap = game.serialize();
    expect(snap.flow.mode).toBe('ending');
    expect(snap.run.slots_placed['test_e1_trigger_beat::trigger_slot']).toBe(true);
    expect(snap.run.action_spent).toBe(true);
    expect(snap.run.flags.ending_flag_kept).toBe(true);
    const active = snap.flow.active_ending as ActiveEndingSnapshot;
    expect(active.ending_id).toBe('ending_inventory_be');
    expect(active.source_id).toBe('ending_effect');
    expect(active.ended_day).toBe(1);
    expect(active.ended_phase).toBe('morning');
    expect(active.opening_choice_id).toBe('take_family_album');
    // 快照看得到剛完成的動作：本次取得的知識已在內，且依 cards 順序
    expect(active.knowledge_gained_this_run).toEqual([k0, k2]);
    expect(runBefore.flow.mode).toBe('run');

    playToReady(game);
    expect(game.completeEnding().ok).toBe(true);
    const done = game.serialize();
    expect(done.flow.mode).toBe('opening');
    expect(done.run).toEqual(createInitialSnapshot().run);
    expect(done.meta.ending_history).toHaveLength(1);
    expect(done.meta.ending_history[0].knowledge_gained_this_run).toEqual([k0, k2]);
    // 知識保留（含本輪取得與回溯知識），history 不含回溯知識
    expect(done.meta.knowledge[k0] && done.meta.knowledge[k2] && done.meta.knowledge[RETURNED_KNOWLEDGE_CARD]).toBe(true);
    expect(done.meta.ending_history[0].knowledge_gained_this_run).not.toContain(RETURNED_KNOWLEDGE_CARD);
  });

  it('a rejected request (source mismatch / unreadable pages) leaves state, bookkeeping and notifications untouched', () => {
    const cases: Array<[string, GameData, string]> = [
      [
        'ending_replaced via ending_effect',
        withBeat(data, endingTriggerBeat({ text: 'x', flag: { leak: true }, ending: 'ending_replaced' })),
        'invalid_ending_source',
      ],
      [
        'blank page text in the target ending',
        withBeat(
          withEnding('ending_inventory_be', (e) => {
            e.first_seen.pages = [{ id: 'blank', text: '  ' }];
          }),
          endingTriggerBeat({ text: 'x', flag: { leak: true }, ending: 'ending_inventory_be' }),
        ),
        'data_conflict',
      ],
    ];
    for (const [name, fixture, code] of cases) {
      const game = createGame(fixture);
      game.chooseOpening('take_family_album');
      const before = JSON.stringify(game.serialize());
      let notifyCount = 0;
      game.subscribe(() => {
        notifyCount += 1;
      });
      const res = game.tryPlace('protagonist', 'test_e1_trigger_beat', 'trigger_slot');
      expect(res.ok, name).toBe(false);
      expect(res.reason_code, name).toBe(code);
      expect(res.lines, name).toEqual([]);
      expect(notifyCount, name).toBe(0);
      expect(JSON.stringify(game.serialize()), name).toBe(before);
    }
  });

  it('trusted-snapshot sources madness_cap and d45_coda run the full page/complete flow with their own fields', () => {
    const cap = createGame(data, endingState('ending_madness_be', 'madness_cap', (st) => {
      st.run.day = 12;
      st.run.phase = 'night';
      st.run.selected_festival_proxy_npc = null;
    }));
    playToReady(cap);
    expect(cap.completeEnding().ok).toBe(true);
    expect(cap.serialize().meta.ending_history[0]).toMatchObject({
      ending_id: 'ending_madness_be',
      ended_day: 12,
      ended_phase: 'night',
      festival_proxy_npc: null,
    });

    const d45 = createGame(data, endingState('ending_replaced', 'd45_coda', (st) => {
      st.run.flags.invited_awei = true;
      st.run.flags.accepted_job = true;
    }));
    // 首見：prefix + 3 variant + suffix（awei 邀請，無 lookup）
    expect(d45.endingView().page_count).toBe(5);
    playToReady(d45);
    expect(d45.completeEnding().ok).toBe(true);
    expect(d45.serialize().meta.ending_history[0]).toEqual(
      replacedRecord({
        partner_variant: 'awei',
        livelihood_variant: 'zhou_low',
        festival_proxy_npc: 'ajie',
      }),
    );
  });
});

describe('W6-E1 ending mode guard and completeEnding preconditions', () => {
  it('ordinary run/opening operations are rejected atomically while an ending is active', () => {
    const game = createGame(data, endingState('ending_madness_be', 'madness_cap', (st) => {
      st.run.day = 3;
      st.run.phase = 'afternoon';
    }));
    const before = JSON.stringify(game.serialize());
    let notifyCount = 0;
    game.subscribe(() => {
      notifyCount += 1;
    });

    const attempts: Array<[string, () => { ok: boolean; reason_code: string }]> = [
      ['tryPlace', () => game.tryPlace('protagonist', 'd3_pm_shopping', 'any_slot')],
      ['choose', () => game.choose('d22_pm_sandbags', 'sandbags', 'obs_walk')],
      ['advancePhase', () => game.advancePhase()],
      ['chooseOpening', () => game.chooseOpening('take_family_album')],
      ['chooseOpening refuse', () => game.chooseOpening('refuse_boarding')],
      ['playBeat', () => game.playBeat('d1_morning_phone')],
      ['playEvening', () => game.playEvening()],
      ['playNightFixed', () => game.playNightFixed()],
    ];
    for (const [name, attempt] of attempts) {
      const res = attempt();
      expect(res.ok, name).toBe(false);
      expect(['not_run', 'not_opening'], name).toContain(res.reason_code);
      expect(JSON.stringify(game.serialize()), name).toBe(before);
    }
    expect(notifyCount).toBe(0);
    expect(game.getPhaseView().can_advance).toBe(false);
  });

  it('completeEnding rejects outside ending, without active, before ready, and on an invalid snapshot — state untouched', () => {
    // not_ending
    const opening = createGame(data);
    const b0 = JSON.stringify(opening.serialize());
    expect(opening.completeEnding().reason_code).toBe('not_ending');
    expect(JSON.stringify(opening.serialize())).toBe(b0);

    // no_active_ending（mode=ending 但 active 缺失的壞快照）
    const noActive = endingState('ending_madness_be', 'madness_cap');
    noActive.flow.active_ending = null;
    const g1 = createGame(data, noActive);
    const b1 = JSON.stringify(g1.serialize());
    expect(g1.completeEnding().reason_code).toBe('no_active_ending');
    expect(JSON.stringify(g1.serialize())).toBe(b1);

    // not_ready：只讀了第一頁
    const g2 = createGame(data, endingState('ending_replaced', 'd45_coda'));
    g2.revealEndingPage();
    const b2 = JSON.stringify(g2.serialize());
    const r2 = g2.completeEnding();
    expect(r2.ok).toBe(false);
    expect(r2.reason_code).toBe('not_ready');
    expect(JSON.stringify(g2.serialize())).toBe(b2);
    expect(g2.serialize().meta.ending_history).toHaveLength(0);

    // data_conflict：ready 的快照被竄改成不合法結果（正常結局缺代付者），history 不得被寫入
    const bad = endingState('ending_replaced', 'd45_coda');
    const active = bad.flow.active_ending as ActiveEndingSnapshot;
    active.page_index = active.page_refs.length - 1;
    active.page_revealed = true;
    active.ready_to_complete = true;
    active.festival_proxy_npc = null;
    const g3 = createGame(data, bad);
    const b3 = JSON.stringify(g3.serialize());
    const r3 = g3.completeEnding();
    expect(r3.ok).toBe(false);
    expect(r3.reason_code).toBe('data_conflict');
    expect(JSON.stringify(g3.serialize())).toBe(b3);
  });

  it('page operations outside ending mode are rejected with not_ending and zero change', () => {
    const game = createGame(data);
    const before = JSON.stringify(game.serialize());
    for (const res of [game.revealEndingPage(), game.advanceEndingPage(), game.skipSeenEnding()]) {
      expect(res.ok).toBe(false);
      expect(res.reason_code).toBe('not_ending');
    }
    expect(JSON.stringify(game.serialize())).toBe(before);
  });
});

describe('W6-E1 completeEnding: meta preserved, run cleared with the shared initial definition', () => {
  it('keeps every existing meta field, clears the whole run, and the next opening matches a brand-new game on the same meta', () => {
    // 正式資料目前沒有 loop_persistent 卡；跨輪集合只要存在於 meta，開局初始化就會依 cards 順序恢復。
    const persistent = data.cards.find((c) => c.id === 'equip_polaroid');
    expect(persistent).toBeDefined();
    const knowledgeId = data.cards.find((c) => c.slotless === true && c.type === 'knowledge')?.id ?? '';
    const start = endingState('ending_inventory_be', 'ending_effect', (st) => {
      // 髒的 run：把幾乎每個欄位弄髒
      st.run.hand.push('equip_polaroid');
      st.run.madness_clock['madness#1'] = 3;
      st.run._madness_counter = 1;
      st.run.beats_entered.some_beat = true;
      st.run.slots_placed['a::b'] = true;
      st.run.choices['a::g'] = 'b';
      st.run.flags.some_flag = true;
      st.run.switches.s1 = true;
      st.run.switch_progress.s6 = 2;
      st.run.relations.ajie = 2;
      st.run.npc_action_counts.ajie = 4;
      st.run.night_location_chosen = 'n_exit';
      st.run.night_sleep_pending = true;
      st.run.indulgence_count = 2;
      st.run.madness_cards_cleared = 3;
      st.run.forced_pending = ['madness#1'];
      st.run.delegates_used_today.ahong = true;
      st.run.pending_delegation_reports = [{ due_day: 5, beat_id: 'b', slot_id: 's', person_id: 'p' }];
      st.run.action_spent = true;
      st.run.actions_spent_ahead = 1;
      st.meta.knowledge[knowledgeId] = true;
      st.meta.night_locations_seen.n_exit = true;
      st.meta.night_once_beats_seen.some_once = true;
      st.meta.day_locations_visited.sanquan = true;
      st.meta.delegation_tutorial_seen = true;
      st.meta.loop_persistent_item_ids[persistent?.id ?? ''] = true;
      st.meta.run_number = 4;
      st.meta.ending_history.push(replacedRecord({ run_number: 3 }));
    });
    // endingState 在 edit 之後才凍結結果；行動中的 run 髒欄位不影響結局可解析性
    const metaBefore = structuredClone(start.meta);

    const game = createGame(data, start);
    playToReady(game);
    expect(game.completeEnding().ok).toBe(true);
    const done = game.serialize();

    expect(done.flow).toEqual({ mode: 'opening', active_ending: null });
    expect(done.run).toEqual(createInitialSnapshot().run);

    // meta 既有欄位全保留；只有 run_number、history、回溯知識有變
    expect(done.meta.night_locations_seen).toEqual(metaBefore.night_locations_seen);
    expect(done.meta.night_once_beats_seen).toEqual(metaBefore.night_once_beats_seen);
    expect(done.meta.day_locations_visited).toEqual(metaBefore.day_locations_visited);
    expect(done.meta.delegation_tutorial_seen).toBe(true);
    expect(done.meta.loop_persistent_item_ids).toEqual(metaBefore.loop_persistent_item_ids);
    expect(done.meta.knowledge).toEqual({ ...metaBefore.knowledge, [RETURNED_KNOWLEDGE_CARD]: true });
    expect(done.meta.run_number).toBe(5);
    expect(done.meta.ending_history).toHaveLength(2);
    expect(done.meta.ending_history[0]).toEqual(metaBefore.ending_history[0]);

    // 清 run 與全新開局共用同一份定義：同 meta 的全新 Game 與已收尾的 Game 開局結果一致
    const brandNew = createInitialSnapshot();
    brandNew.meta = structuredClone(done.meta);
    const fresh = createGame(data, brandNew);
    expect(game.chooseOpening('take_family_album').ok).toBe(true);
    expect(fresh.chooseOpening('take_family_album').ok).toBe(true);
    expect(game.serialize()).toEqual(fresh.serialize());
    // 跨輪物品由開局重新組裝回手牌，protagonist 在 index 0
    expect(game.serialize().run.hand[0]).toBe('protagonist');
    expect(game.serialize().run.hand).toContain(persistent?.id);
  });
});
