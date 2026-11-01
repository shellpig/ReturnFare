import { useEffect, useRef, type ReactNode } from 'react';

/** 與 CardDetail 相同以 showModal 開啟，Escape 走 onCancel 關閉。 */
export function ModalDialog({
  className,
  labelledBy,
  onClose,
  children,
}: {
  className: string;
  labelledBy: string;
  onClose: () => void;
  children: ReactNode;
}) {
  const dialogRef = useRef<HTMLDialogElement>(null);

  useEffect(() => {
    const el = dialogRef.current;
    if (el && !el.open) {
      el.showModal();
    }
  }, []);

  return (
    <dialog
      ref={dialogRef}
      className={className}
      onCancel={(e) => {
        e.preventDefault();
        onClose();
      }}
      aria-labelledby={labelledBy}
    >
      {children}
    </dialog>
  );
}
