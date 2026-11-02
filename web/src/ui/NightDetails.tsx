import type { NightLocationSummary } from '../core/night';
import { strings } from './strings';
import { useStoryText } from './use-story-text';

/**
 * 夜間地點詳情（對應 scenes/ui/location_panel.gd show_night_details）。
 * 唯讀：只渲染 Game.nightLocationSummary() 的結果，開詳情不收費、不消耗今晚、不改狀態；
 * 只有按下可用的「進入」才由 onEnter 交給規則層。
 */
export function NightDetails({
  locationId,
  summary,
  onEnter,
  onBack,
}: {
  locationId: string;
  summary: NightLocationSummary;
  onEnter: (locationId: string) => void;
  onBack: () => void;
}) {
  const story = useStoryText([summary.desc ?? ''], locationId);
  // 拒絕理由：資料側理由優先，否則走封閉碼的中文對照，英文碼不外露（location_panel.gd _NIGHT_REJECT_TEXTS）。
  const reason =
    summary.can_enter || summary.reason_code === ''
      ? ''
      : summary.reason_text.trim() ||
        strings.reasonCodes[summary.reason_code] ||
        strings.reasonFallback;

  return (
    <section className="location-panel night-details" data-testid={`night-details-${locationId}`} {...story.revealProps}>
      <div className="location-header">
        <h2>{summary.display_name}</h2>
        <button type="button" onClick={onBack}>
          {strings.backToMap}
        </button>
      </div>
      {summary.status_text && (
        <p className="night-status" data-testid="night-status">
          {summary.status_text}
        </p>
      )}
      {summary.desc && (
        <p className="story night-desc" data-testid="night-desc">
          {story.visibleLines[0]}
        </p>
      )}
      {reason && (
        <p className="reason night-reason" data-testid="night-reason">
          {reason}
        </p>
      )}
      {summary.warning && (
        <p className="reason night-warning" role="note" data-testid="night-warning">
          {summary.warning}
        </p>
      )}
      <div className="night-actions">
        <button
          type="button"
          data-testid="night-enter"
          disabled={!summary.can_enter}
          onClick={() => onEnter(locationId)}
        >
          {strings.nightEnter}
        </button>
      </div>
    </section>
  );
}
