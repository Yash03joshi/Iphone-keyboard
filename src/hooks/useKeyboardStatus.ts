import { useEffect, useState } from 'react';

import HindiInk, { type KeyboardStatus } from '@/modules/hindi-ink';

const POLL_MS = 1000;

/**
 * Whether our keyboard is enabled / selected. Polls because the system settings screen and
 * the keyboard picker dialog give no callback when the user changes something.
 */
export function useKeyboardStatus(): KeyboardStatus {
  const [status, setStatus] = useState<KeyboardStatus>(() => HindiInk.getKeyboardStatus());

  useEffect(() => {
    const timer = setInterval(() => {
      const next = HindiInk.getKeyboardStatus();
      setStatus((prev) =>
        prev.enabled === next.enabled && prev.selected === next.selected ? prev : next
      );
    }, POLL_MS);
    return () => clearInterval(timer);
  }, []);

  return status;
}
