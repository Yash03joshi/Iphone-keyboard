import { NativeModule, requireNativeModule } from 'expo';

import { KeyboardStatus } from './HindiInk.types';

declare class HindiInkModule extends NativeModule {
  isModelDownloaded(): Promise<boolean>;
  downloadModel(): Promise<void>;
  deleteModel(): Promise<void>;
  getKeyboardStatus(): KeyboardStatus;
  /** Opens the system screen where the keyboard is turned on. */
  openKeyboardSettings(): void;
  /** Shows the system "choose keyboard" dialog. */
  showKeyboardPicker(): void;
}

export default requireNativeModule<HindiInkModule>('HindiInk');
