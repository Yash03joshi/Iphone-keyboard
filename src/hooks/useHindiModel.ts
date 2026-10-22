import { useCallback, useEffect, useState } from 'react';

import HindiInk from '@/modules/hindi-ink';

export type ModelStatus = 'checking' | 'missing' | 'downloading' | 'ready' | 'error';

/** Tracks whether the Hindi handwriting model is on the device and downloads it on request. */
export function useHindiModel() {
  const [status, setStatus] = useState<ModelStatus>('checking');
  const [error, setError] = useState<string | null>(null);

  const refresh = useCallback(
    () =>
      HindiInk.isModelDownloaded().then(
        (downloaded) => setStatus(downloaded ? 'ready' : 'missing'),
        (e) => {
          setError(String(e));
          setStatus('error');
        }
      ),
    []
  );

  const check = useCallback(() => {
    setError(null);
    setStatus('checking');
    return refresh();
  }, [refresh]);

  const download = useCallback(async () => {
    setError(null);
    setStatus('downloading');
    try {
      await HindiInk.downloadModel();
      setStatus('ready');
    } catch (e) {
      setError(String(e));
      setStatus('error');
    }
  }, []);

  useEffect(() => {
    refresh();
  }, [refresh]);

  return { status, error, download, check };
}
