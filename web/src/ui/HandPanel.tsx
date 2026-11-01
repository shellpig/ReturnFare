import { useState } from 'react';
import type { CardView, Game } from '../core/state-types';
import { CardDetail } from './CardDetail';
import { strings } from './strings';

export function HandPanel({ game }: { game: Game }) {
  const [selectedCard, setSelectedCard] = useState<CardView | null>(null);
  const [showKnowledge, setShowKnowledge] = useState(false);

  const hand = game.handView();
  const knowledge = game.knowledgeView();
  const slotsUsed = game.handSlotsUsed();
  const capacity = game.handCapacity();

  return (
    <section className="hand-panel" aria-label="手牌與知識">
      <div className="hand-header">
        <span className="hand-slots" data-testid="hand-slots">
          {strings.handSlots(slotsUsed, capacity)}
        </span>
        <button
          type="button"
          className="knowledge-btn"
          data-testid="knowledge-btn"
          onClick={() => setShowKnowledge(true)}
        >
          {strings.knowledgeCount(knowledge.length)}
        </button>
      </div>
      <div className="hand-cards">
        {hand.map((card) => {
          let label =
            card.countdown !== undefined
              ? strings.cardCountdown(card.name, card.countdown)
              : card.name;
          if (card.type === 'person') {
            const status = game.delegationStatus(card.instanceId);
            if (status.delegated_today) {
              label = `${label}${strings.delegatedTodaySuffix}`;
            }
          }
          return (
            <button
              type="button"
              key={card.instanceId}
              className="card-btn"
              data-testid={`card-${card.instanceId}`}
              onClick={() => setSelectedCard(card)}
              title={label}
            >
              {label}
            </button>
          );
        })}
      </div>

      {selectedCard && (
        <CardDetail
          card={selectedCard}
          onClose={() => setSelectedCard(null)}
        />
      )}

      {showKnowledge && (
        <CardDetail
          knowledgeList={knowledge}
          onClose={() => setShowKnowledge(false)}
        />
      )}
    </section>
  );
}
