import type { StyleProp, ViewStyle } from 'react-native';

export type KeyboardStatus = {
  /** Turned on in system settings. */
  enabled: boolean;
  /** The current default keyboard. */
  selected: boolean;
};

export type StrokesChangeEvent = { count: number };
export type RecognizedEvent = { candidates: string[] };
export type RecognitionErrorEvent = { message: string };

export type HindiInkViewProps = {
  style?: StyleProp<ViewStyle>;
  /** Ink thickness in dp. */
  strokeWidth?: number;
  /** Recognize automatically this long after the last stroke; 0 disables. */
  recognizeDelayMs?: number;
  /** Text just before the cursor; improves accuracy and word spacing. */
  preContext?: string;
  onStrokesChange?: (event: { nativeEvent: StrokesChangeEvent }) => void;
  onRecognized?: (event: { nativeEvent: RecognizedEvent }) => void;
  onRecognitionError?: (event: { nativeEvent: RecognitionErrorEvent }) => void;
};

/** Methods available on a ref to `HindiInkView`. */
export type HindiInkViewRef = {
  clear(): Promise<void>;
  undo(): Promise<void>;
  /** Returns candidate texts, best first. */
  recognize(): Promise<string[]>;
};
