import { useEffect, useRef, useState } from 'react';
import type { ReactNode, RefObject } from 'react';
import { strings } from './strings';

export function ZoomableArt({ children, className, canvasRef }: {
  children: ReactNode;
  className: string;
  canvasRef?: RefObject<HTMLDivElement>;
}) {
  const viewport = useRef<HTMLDivElement>(null);
  const gesture = useRef<{ id: number; x: number; y: number; startX: number; startY: number; moved: boolean; active: boolean } | null>(null);
  const [zoomed, setZoomed] = useState(false);
  const [offset, setOffset] = useState({ x: 0, y: 0 });

  useEffect(() => {
    const mobile = window.matchMedia('(max-width: 520px)');
    const reset = () => {
      if (!mobile.matches) { setZoomed(false); setOffset({ x: 0, y: 0 }); }
    };
    mobile.addEventListener('change', reset);
    return () => mobile.removeEventListener('change', reset);
  }, []);

  return <div className={`zoomable-art ${className}`} data-zoomed={zoomed}>
    <div className="art-toolbar">
    <button type="button" className="art-zoom-toggle" data-art-control="true"
      aria-pressed={zoomed} onClick={() => {
        const box = viewport.current;
        setOffset(!zoomed && box ? { x: -box.clientWidth / 2, y: -box.clientHeight / 2 } : { x: 0, y: 0 });
        setZoomed(!zoomed);
        gesture.current = null;
      }}>{zoomed ? strings.restoreArt : strings.zoomArt}</button>
    </div>
    <div className="art-viewport" ref={viewport}
      onPointerDownCapture={event => {
        if (!zoomed || !event.isPrimary || event.button !== 0) return;
        event.currentTarget.dataset.artDragged = 'false';
        gesture.current = { id: event.pointerId, x: event.clientX, y: event.clientY,
          startX: offset.x, startY: offset.y, moved: false, active: true };
      }}
      onPointerMove={event => {
        const drag = gesture.current;
        const box = viewport.current;
        if (!zoomed || !drag?.active || !box || drag.id !== event.pointerId) return;
        const dx = event.clientX - drag.x;
        const dy = event.clientY - drag.y;
        if (!drag.moved && Math.hypot(dx, dy) < 6) return;
        drag.moved = true;
        box.dataset.artDragged = 'true';
        box.setPointerCapture(event.pointerId);
        event.preventDefault();
        setOffset({ x: Math.max(-box.clientWidth, Math.min(0, drag.startX + dx)),
          y: Math.max(-box.clientHeight, Math.min(0, drag.startY + dy)) });
      }}
      onPointerUp={event => {
        const box = viewport.current;
        if (gesture.current?.id === event.pointerId) gesture.current.active = false;
        if (box?.hasPointerCapture(event.pointerId)) box.releasePointerCapture(event.pointerId);
      }}
      onPointerCancel={event => { gesture.current = null; event.currentTarget.dataset.artDragged = 'false'; }}
      onClickCapture={event => {
        if (gesture.current?.moved) {
          event.preventDefault();
          event.stopPropagation();
          gesture.current = null;
        }
      }}>
      <div className="art-canvas" ref={canvasRef}
        style={zoomed ? { transform: `translate(${offset.x}px, ${offset.y}px) scale(2)` } : undefined}>
        {children}
      </div>
    </div>
  </div>;
}
