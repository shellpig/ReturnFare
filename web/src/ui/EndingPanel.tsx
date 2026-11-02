import { useEffect, useState } from 'react';
import type { Game, MutationResult } from '../core/state-types';
import { strings } from './strings';
import { useGame } from './use-game';

/** 逐字速度：scenes/ui/flow_text.gd start_typewriter 的預設 35 字／秒（純呈現參數，不屬遊戲規則）。 */
const TYPEWRITER_CHARS_PER_SEC = 35;

/**
 * 結局逐頁面板（對應 scenes/ui/ending_panel.gd）。
 * 規則全在 core：本元件只讀 game.endingView() 並派發 reveal／advance／skip／complete。
 * 逐字顯示只是 UI 暫態；計時器綁定當頁，頁面變更或元件卸載即清除，舊 callback 不會落到新畫面。
 */
export function EndingPanel({ game }: { game: Game }) {
  useGame(game);
  const view = game.endingView();
  // 逐字進度綁定頁碼：換頁後舊頁的進度不會套到新頁（避免新頁閃現全文）。
  const [progress, setProgress] = useState({ page: -1, count: 0 });
  const [error, setError] = useState('');
  const chars = Array.from(view.page_text);
  const shown = progress.page === view.page_index ? progress.count : 0;

  // 逐字計時：僅在當頁尚未揭露時運作；以 page_index 為界，換頁或卸載都會清掉計時器。
  useEffect(() => {
    if (view.page_revealed) return;
    const pageIndex = view.page_index;
    setProgress({ page: pageIndex, count: 0 });
    const timer = window.setInterval(() => {
      setProgress((current) =>
        current.page === pageIndex ? { page: pageIndex, count: current.count + 1 } : current,
      );
    }, Math.round(1000 / TYPEWRITER_CHARS_PER_SEC));
    return () => window.clearInterval(timer);
  }, [view.page_index, view.page_revealed, view.page_text]);

  // 自然播完 = 補完當頁（Godot：typewriter_completed -> reveal_ending_page）。
  useEffect(() => {
    if (view.page_revealed || chars.length === 0 || shown < chars.length) return;
    const fresh = game.endingView();
    if (fresh.page_index === view.page_index && !fresh.page_revealed) {
      game.revealEndingPage();
    }
  }, [shown, chars.length, view.page_index, view.page_revealed, game]);

  function report(result: MutationResult) {
    setError(
      result.ok
        ? ''
        : (strings.reasonCodes[result.reason_code] ??
            (result.reason_text || strings.reasonFallback)),
    );
  }

  /** 一次輸入只能做一件事：補完當頁、翻頁、結算三擇一。 */
  function onAdvance() {
    const now = game.endingView();
    if (now.page_count === 0) return;
    if (!now.page_revealed) {
      report(game.revealEndingPage());
    } else if (!now.is_last_page) {
      report(game.advanceEndingPage());
    } else if (now.can_complete) {
      report(game.completeEnding());
    }
  }

  // 鍵盤：空白／Enter／→／↓。焦點在按鈕上時交給按鈕原生 click，避免同一次輸入觸發兩次。
  useEffect(() => {
    function onKeyDown(event: KeyboardEvent) {
      if (event.repeat || event.defaultPrevented) return;
      if (event.target instanceof Element && event.target.closest('button, a, input, textarea, select')) {
        return;
      }
      if (![' ', 'Enter', 'ArrowRight', 'ArrowDown'].includes(event.key)) return;
      event.preventDefault();
      onAdvance();
    }
    window.addEventListener('keydown', onKeyDown);
    return () => window.removeEventListener('keydown', onKeyDown);
  });

  const text = view.page_revealed ? view.page_text : chars.slice(0, shown).join('');
  const typing = !view.page_revealed;
  const advanceLabel = typing
    ? strings.endingReveal
    : !view.is_last_page
      ? strings.endingNext
      : strings.endingComplete;

  return (
    <section className="ending-panel" aria-label={strings.endingRegion} data-ending-typing={typing}>
      <div className="ending-body" data-testid="ending-body" onClick={onAdvance}>
        <p className="story passage ending-text" data-testid="ending-text">
          {text}
        </p>
      </div>
      {error && (
        <p role="alert" className="reason">
          {error}
        </p>
      )}
      <div className="ending-controls">
        <span className="ending-page" data-testid="ending-page">
          {strings.endingPage(view.page_index + 1, view.page_count)}
        </span>
        {view.can_skip && (
          <button type="button" onClick={() => report(game.skipSeenEnding())}>
            {strings.endingSkip}
          </button>
        )}
        <button type="button" onClick={onAdvance}>
          {advanceLabel}
        </button>
      </div>
    </section>
  );
}
