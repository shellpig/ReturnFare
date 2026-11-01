import { useState } from 'react';
import type { Game } from '../core/state-types';
import { CardDetail } from './CardDetail';
import { ModalDialog } from './ModalDialog';
import { strings } from './strings';

export interface EncounterPanelProps {
  readonly game: Game;
  readonly introLines?: readonly string[];
  readonly lastActionLines?: readonly string[];
  readonly onAckIntro: () => void;
  readonly onRespond: (cardId: string) => void;
  readonly onDiscard: (cardId: string) => void;
  readonly onEscape: (cardIds: readonly string[]) => void;
}

export function EncounterPanel({
  game,
  introLines = [],
  lastActionLines = [],
  onAckIntro,
  onRespond,
  onDiscard,
  onEscape,
}: EncounterPanelProps) {
  const [introIndex, setIntroIndex] = useState(0);
  const [detailCardId, setDetailCardId] = useState<string | null>(null);
  const [pendingRespond, setPendingRespond] = useState<{
    cardId: string;
    cardName: string;
  } | null>(null);
  const [pendingDiscard, setPendingDiscard] = useState<{
    cardId: string;
    cardName: string;
  } | null>(null);
  const [pendingEscape, setPendingEscape] = useState<{
    cardIds: readonly string[];
    summary: string;
  } | null>(null);

  const view = game.encounterView();
  if (!('stage' in view)) {
    return null;
  }

  if (view.stage === 'intro') {
    const readingIntro = introLines.length > 0 && introIndex < introLines.length - 1;
    const displayedLines =
      introLines.length > 0
        ? introLines.slice(0, introIndex + 1)
        : [];

    return (
      <section
        className="encounter-panel encounter-intro"
        aria-label={strings.encounterRegion}
        data-testid="encounter-panel"
      >
        <div className="encounter-intro-text">
          {displayedLines.map((line, idx) => (
            <p key={idx} className="story intro-line">
              {line}
            </p>
          ))}
        </div>
        <div className="encounter-intro-actions">
          {readingIntro ? (
            <button
              type="button"
              data-testid="encounter-intro-continue"
              onClick={() => setIntroIndex((i) => i + 1)}
            >
              {strings.continue}
            </button>
          ) : (
            <button
              type="button"
              data-testid="encounter-intro-ack"
              data-meta="encounter_intro_ack"
              onClick={onAckIntro}
              autoFocus
            >
              {strings.encounterIntroAck}
            </button>
          )}
        </div>
      </section>
    );
  }

  // Round 階段
  const payableCards = view.candidates.filter(
    (c) => c.source === 'hand' && c.discardable,
  );
  const escCost = view.escape_cost ?? 0;

  return (
    <section
      className="encounter-panel encounter-round"
      aria-label={strings.encounterRegion}
      data-testid="encounter-panel"
    >
      {lastActionLines.length > 0 && (
        <div className="encounter-action-lines">
          {lastActionLines.map((line, idx) => (
            <p key={idx} className="story action-line">
              {line}
            </p>
          ))}
        </div>
      )}

      <div
        className="encounter-demand story"
        data-testid="encounter-demand"
        data-meta="encounter_demand"
      >
        {view.demand}
      </div>

      <div
        className="encounter-capacity"
        data-testid="encounter-capacity"
        data-meta="encounter_capacity"
      >
        {strings.encounterCapacity(
          view.available_slots,
          view.capacity,
          view.blocked_slots,
        )}
      </div>

      {view.blocked_slots > 0 && (
        <div
          className="encounter-blocked-container"
          data-testid="encounter-blocked-container"
        >
          {Array.from({ length: view.blocked_slots }, (_, i) => (
            <span
              key={i}
              className="encounter-blocked-slot"
              data-testid={`encounter-blocked-${i}`}
              data-meta={`encounter_blocked::${i}`}
            >
              ■
            </span>
          ))}
        </div>
      )}

      <div
        className="encounter-candidate-list"
        data-testid="encounter-candidate-list"
      >
        {view.candidates.map((cand) => {
          const displayName =
            cand.source === 'knowledge'
              ? strings.encounterCandidateKnowledge(cand.name)
              : cand.name;
          const reasonText =
            !cand.submittable && cand.disabled_reason
              ? strings.reasonCodes[cand.disabled_reason] || strings.reasonFallback
              : '';
          const labelWithReason = reasonText
            ? `${displayName}  [${reasonText}]`
            : displayName;

          return (
            <div key={cand.card_id} className="encounter-candidate-row">
              <button
                type="button"
                className="encounter-candidate-btn"
                data-testid={`encounter-candidate-${cand.card_id}`}
                data-meta={`encounter_candidate::${cand.card_id}`}
                disabled={!cand.submittable}
                onClick={() =>
                  setPendingRespond({
                    cardId: cand.card_id,
                    cardName: cand.name,
                  })
                }
              >
                {labelWithReason}
              </button>

              <button
                type="button"
                className="encounter-detail-btn"
                data-testid={`encounter-detail-${cand.card_id}`}
                data-meta={`encounter_detail::${cand.card_id}`}
                onClick={() => setDetailCardId(cand.card_id)}
              >
                {strings.encounterDetail}
              </button>

              {view.allow_discard &&
                cand.source === 'hand' &&
                cand.discardable && (
                  <button
                    type="button"
                    className="encounter-discard-btn"
                    data-testid={`encounter-discard-${cand.card_id}`}
                    data-meta={`encounter_discard::${cand.card_id}`}
                    onClick={() =>
                      setPendingDiscard({
                        cardId: cand.card_id,
                        cardName: cand.name,
                      })
                    }
                  >
                    {strings.encounterDiscardBtn(cand.name)}
                  </button>
                )}
            </div>
          );
        })}
      </div>

      {view.can_escape && (
        <div
          className="encounter-action-row"
          data-testid="encounter-action-row"
        >
          {escCost === 0 ? (
            <button
              type="button"
              data-testid="encounter-escape"
              data-meta="encounter_escape"
              onClick={() =>
                setPendingEscape({
                  cardIds: [],
                  summary: '',
                })
              }
            >
              {strings.encounterEscapeFree}
            </button>
          ) : escCost === 1 ? (
            payableCards.map((p) => (
              <button
                key={p.card_id}
                type="button"
                data-testid={`encounter-escape-pay-${p.card_id}`}
                data-meta={`encounter_escape_pay::${p.card_id}`}
                onClick={() =>
                  setPendingEscape({
                    cardIds: [p.card_id],
                    summary: p.name,
                  })
                }
              >
                {strings.encounterEscapePay(p.name)}
              </button>
            ))
          ) : payableCards.length >= escCost ? (
            <button
              type="button"
              data-testid="encounter-escape"
              data-meta="encounter_escape"
              onClick={() => {
                const chosen = payableCards.slice(0, escCost);
                setPendingEscape({
                  cardIds: chosen.map((c) => c.card_id),
                  summary: chosen.map((c) => c.name).join('、'),
                });
              }}
            >
              {strings.encounterEscapeCost(escCost)}
            </button>
          ) : null}
        </div>
      )}

      {/* 對話框：回應確認 */}
      {pendingRespond && (
        <ModalDialog
          className="encounter-respond-dialog"
          labelledBy="encounter-respond-title"
          onClose={() => setPendingRespond(null)}
        >
          <h3 id="encounter-respond-title">{strings.encounterRespondTitle}</h3>
          <p className="story">
            {strings.encounterRespondText(pendingRespond.cardName)}
          </p>
          <div className="dialog-actions">
            <button
              type="button"
              data-testid="dialog-cancel-encounter-respond"
              data-meta="dialog_cancel::encounter_respond"
              onClick={() => setPendingRespond(null)}
            >
              {strings.cancel}
            </button>
            <button
              type="button"
              data-testid="dialog-confirm-encounter-respond"
              data-meta="dialog_confirm::encounter_respond"
              onClick={() => {
                const cid = pendingRespond.cardId;
                setPendingRespond(null);
                onRespond(cid);
              }}
              autoFocus
            >
              {strings.confirm}
            </button>
          </div>
        </ModalDialog>
      )}

      {/* 對話框：丟棄確認 */}
      {pendingDiscard && (
        <ModalDialog
          className="encounter-discard-dialog"
          labelledBy="encounter-discard-title"
          onClose={() => setPendingDiscard(null)}
        >
          <h3 id="encounter-discard-title">{strings.encounterDiscardTitle}</h3>
          <p className="story">
            {strings.encounterDiscardText(pendingDiscard.cardName)}
          </p>
          <div className="dialog-actions">
            <button
              type="button"
              data-testid="dialog-cancel-encounter-discard"
              data-meta="dialog_cancel::encounter_discard"
              onClick={() => setPendingDiscard(null)}
            >
              {strings.cancel}
            </button>
            <button
              type="button"
              data-testid="dialog-confirm-encounter-discard"
              data-meta="dialog_confirm::encounter_discard"
              onClick={() => {
                const cid = pendingDiscard.cardId;
                setPendingDiscard(null);
                onDiscard(cid);
              }}
              autoFocus
            >
              {strings.confirm}
            </button>
          </div>
        </ModalDialog>
      )}

      {/* 對話框：逃離確認 */}
      {pendingEscape && (
        <ModalDialog
          className="encounter-escape-dialog"
          labelledBy="encounter-escape-title"
          onClose={() => setPendingEscape(null)}
        >
          <h3 id="encounter-escape-title">{strings.encounterEscapeTitle}</h3>
          <p className="story">
            {pendingEscape.summary
              ? strings.encounterEscapeText(pendingEscape.summary)
              : strings.encounterEscapeFreeText}
          </p>
          <div className="dialog-actions">
            <button
              type="button"
              data-testid="dialog-cancel-encounter-escape"
              data-meta="dialog_cancel::encounter_escape"
              onClick={() => setPendingEscape(null)}
            >
              {strings.cancel}
            </button>
            <button
              type="button"
              data-testid="dialog-confirm-encounter-escape"
              data-meta="dialog_confirm::encounter_escape"
              onClick={() => {
                const ids = pendingEscape.cardIds;
                setPendingEscape(null);
                onEscape(ids);
              }}
              autoFocus
            >
              {strings.confirm}
            </button>
          </div>
        </ModalDialog>
      )}

      {/* 卡片詳情 */}
      {detailCardId && (
        <CardDetail
          card={game.cardView(detailCardId)}
          onClose={() => setDetailCardId(null)}
        />
      )}
    </section>
  );
}
