import { useEffect, useLayoutEffect, useRef, useState } from 'react';

export type DayNightDirection = 'night' | 'day';

export function useDayNightTransition(gameKey: number) {
  const [transition, setTransition] = useState<{
    direction: DayNightDirection;
    revealing: boolean;
  } | null>(null);
  const contentRef = useRef<HTMLDivElement>(null);
  const busy = useRef(false);
  const timers = useRef<ReturnType<typeof setTimeout>[]>([]);

  useEffect(() => {
    busy.current = false;
    setTransition(null);
    return () => { timers.current.forEach(clearTimeout); timers.current = []; };
  }, [gameKey]);

  useLayoutEffect(() => {
    const content = contentRef.current;
    if (!content || !transition) return;
    content.inert = true;
    const blockKey = (event: KeyboardEvent) => {
      event.preventDefault();
      event.stopImmediatePropagation();
    };
    document.addEventListener('keydown', blockKey, true);
    return () => {
      content.inert = false;
      document.removeEventListener('keydown', blockKey, true);
    };
  }, [transition !== null]);

  function start(direction: DayNightDirection, advance: () => void) {
    if (busy.current) return;
    if (window.matchMedia('(prefers-reduced-motion: reduce)').matches) {
      advance();
      return;
    }
    busy.current = true;
    setTransition({ direction, revealing: false });
    timers.current = [
      setTimeout(() => {
        advance();
        setTransition({ direction, revealing: true });
      }, 400),
      setTimeout(() => {
        setTransition(null);
        busy.current = false;
        timers.current = [];
      }, 800),
    ];
  }

  return {
    start,
    contentRef,
    overlay: transition && <div
      className={`day-night-transition to-${transition.direction}${transition.revealing ? ' revealing' : ''}`}
      data-testid="day-night-transition"
      aria-hidden="true"
    />,
  };
}
