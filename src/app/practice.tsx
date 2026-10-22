import { useRef, useState } from 'react';
import { Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';

import { BigButton } from '@/components/BigButton';
import { HindiInkView, type HindiInkViewRef } from '@/modules/hindi-ink';
import { colors, fontSize, minTouchTarget, spacing } from '@/theme';

const RECOGNIZE_DELAY_MS = 900;

// The last auto-inserted word, so a different candidate can replace it.
type LastInsert = { before: string; candidates: string[]; chosen: number };

export default function PracticeScreen() {
  const inkRef = useRef<HindiInkViewRef>(null);
  const [text, setText] = useState('');
  const [strokeCount, setStrokeCount] = useState(0);
  const [lastInsert, setLastInsert] = useState<LastInsert | null>(null);
  const [error, setError] = useState<string | null>(null);

  const onRecognized = (candidates: string[]) => {
    setError(null);
    if (candidates.length === 0) return;
    setLastInsert({ before: text, candidates, chosen: 0 });
    setText(text + candidates[0] + ' ');
    inkRef.current?.clear();
  };

  const chooseCandidate = (index: number) => {
    if (!lastInsert) return;
    setText(lastInsert.before + lastInsert.candidates[index] + ' ');
    setLastInsert({ ...lastInsert, chosen: index });
  };

  const backspace = () => {
    setLastInsert(null);
    setText(text.slice(0, -1));
  };

  const clearAll = () => {
    setLastInsert(null);
    setText('');
    inkRef.current?.clear();
  };

  return (
    <View style={styles.container}>
      <View style={styles.output}>
        <Text style={text ? styles.outputText : styles.placeholder}>
          {text || 'Your text will appear here'}
        </Text>
      </View>

      <ScrollView horizontal contentContainerStyle={styles.candidates} style={styles.candidateBar}>
        {lastInsert?.candidates.slice(0, 5).map((candidate, index) => (
          <Pressable
            key={`${index}-${candidate}`}
            accessibilityRole="button"
            onPress={() => chooseCandidate(index)}
            style={[styles.candidate, index === lastInsert.chosen && styles.candidateChosen]}>
            <Text style={styles.candidateText}>{candidate}</Text>
          </Pressable>
        ))}
      </ScrollView>

      <View style={styles.canvasWrap}>
        <HindiInkView
          ref={inkRef}
          style={StyleSheet.absoluteFill}
          strokeWidth={6}
          recognizeDelayMs={RECOGNIZE_DELAY_MS}
          preContext={text}
          onStrokesChange={(e) => setStrokeCount(e.nativeEvent.count)}
          onRecognized={(e) => onRecognized(e.nativeEvent.candidates)}
          onRecognitionError={(e) => setError(e.nativeEvent.message)}
        />
        {strokeCount === 0 && (
          <Text style={styles.hint}>
            Write here with your finger
          </Text>
        )}
      </View>

      {error && <Text style={styles.error}>{error}</Text>}

      <View style={styles.row}>
        <View style={styles.flex}>
          <BigButton
            label="Undo stroke"
            variant="secondary"
            disabled={strokeCount === 0}
            onPress={() => inkRef.current?.undo()}
          />
        </View>
        <View style={styles.flex}>
          <BigButton label="⌫" variant="secondary" disabled={!text} onPress={backspace} />
        </View>
        <View style={styles.flex}>
          <BigButton label="Clear all" variant="secondary" onPress={clearAll} />
        </View>
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    padding: spacing.md,
    gap: spacing.sm,
  },
  output: {
    minHeight: 100,
    borderWidth: 1,
    borderColor: colors.border,
    borderRadius: 12,
    padding: spacing.md,
  },
  outputText: {
    fontSize: 28,
    color: colors.text,
  },
  placeholder: {
    fontSize: fontSize.body,
    color: colors.muted,
  },
  candidateBar: {
    flexGrow: 0,
  },
  candidates: {
    gap: spacing.sm,
    minHeight: minTouchTarget,
  },
  candidate: {
    minHeight: minTouchTarget,
    minWidth: minTouchTarget,
    paddingHorizontal: spacing.md,
    borderRadius: 12,
    borderWidth: 2,
    borderColor: colors.border,
    alignItems: 'center',
    justifyContent: 'center',
  },
  candidateChosen: {
    borderColor: colors.primary,
    backgroundColor: '#E8F0FE',
  },
  candidateText: {
    fontSize: 26,
    color: colors.text,
  },
  canvasWrap: {
    flex: 1,
    minHeight: 240,
    borderWidth: 2,
    borderColor: colors.primary,
    borderRadius: 12,
    overflow: 'hidden',
    backgroundColor: '#FFFDF5',
    alignItems: 'center',
    justifyContent: 'center',
  },
  hint: {
    pointerEvents: 'none',
    fontSize: fontSize.title,
    color: colors.border,
  },
  error: {
    fontSize: fontSize.body - 2,
    color: colors.danger,
  },
  row: {
    flexDirection: 'row',
    gap: spacing.sm,
  },
  flex: {
    flex: 1,
  },
});
