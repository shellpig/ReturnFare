import { useEffect, useRef } from 'react';

export function BackgroundMusic({ src }: { src: string }) {
  const ref = useRef<HTMLAudioElement>(null);

  useEffect(() => {
    const audio = ref.current!;
    const resume = () => {
      if (audio.paused) void audio.play().catch(() => {});
    };
    // 瀏覽器拒絕自動播放時，在下一次使用者操作同步重試。
    document.addEventListener('pointerdown', resume);
    document.addEventListener('keydown', resume);
    return () => {
      document.removeEventListener('pointerdown', resume);
      document.removeEventListener('keydown', resume);
      audio.pause();
    };
  }, []);

  useEffect(() => {
    void ref.current!.play().catch(() => {});
  }, [src]);

  return <audio ref={ref} src={src} loop preload="metadata" />;
}
