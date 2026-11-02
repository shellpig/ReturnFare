import { useEffect, useState } from 'react';
import type { KeyboardEvent, MouseEvent } from 'react';

/** 純呈現速度，約每秒 33 字；不進入遊戲狀態或存檔。 */
const CHARACTER_INTERVAL_MS = 30;

export function preserveStoryInput(target: EventTarget | null): boolean {
  return Boolean(document.querySelector('dialog[open]')) || (target instanceof Element && Boolean(target.closest(
    '[data-art-control], [data-art-dragged="true"], .save-panel button, .save-panel input, dialog, a, input, textarea, select',
  )));
}

export function useStoryText(lines: readonly string[], identity: string) {
  const key = JSON.stringify([identity, ...lines]);
  const characters = lines.map(line => Array.from(line));
  const length = characters.reduce((sum, line) => sum + line.length, 0);
  const [progress, setProgress] = useState({ key, count: 0 });
  const count = progress.key === key ? progress.count : 0;
  const typing = count < length;

  useEffect(() => {
    if (!typing) return;
    const startedAt = Date.now();
    const initialCount = count;
    const timer = window.setInterval(() => {
      setProgress({ key, count: Math.min(length,
        initialCount + Math.floor((Date.now() - startedAt) / CHARACTER_INTERVAL_MS)) });
    }, CHARACTER_INTERVAL_MS);
    return () => window.clearInterval(timer);
    // 同一段文字只建立一個計時器；換段、補完或卸載時清除。
  }, [key, typing, length]);

  useEffect(() => {
    if (!typing) return;
    const onClick = (event: globalThis.MouseEvent) => reveal(event);
    document.addEventListener('click', onClick, true);
    return () => document.removeEventListener('click', onClick, true);
  }, [key, typing, length]);

  let remaining = count;
  const visibleLines = characters.map(line => {
    const text = line.slice(0, Math.max(0, remaining)).join('');
    remaining -= line.length;
    return text;
  });

  function reveal(event: MouseEvent | KeyboardEvent | globalThis.MouseEvent) {
    if (!typing) return;
    if (preserveStoryInput(event.target)) return;
    event.preventDefault();
    event.stopPropagation();
    setProgress({ key, count: length });
  }

  return {
    visibleLines,
    typing,
    revealProps: {
      'data-typing': typing,
      onClickCapture: reveal,
      onKeyDownCapture: (event: KeyboardEvent) => {
        if ([' ', 'Enter'].includes(event.key)) reveal(event);
      },
      tabIndex: typing ? 0 : undefined,
    },
  };
}
