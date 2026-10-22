import { router } from 'expo-router';
import type { ReactNode } from 'react';
import { ScrollView, StyleSheet, Text, View } from 'react-native';

import { BigButton } from '@/components/BigButton';
import { useHindiModel } from '@/hooks/useHindiModel';
import { useKeyboardStatus } from '@/hooks/useKeyboardStatus';
import HindiInk from '@/modules/hindi-ink';
import { colors, fontSize, spacing } from '@/theme';

export default function HomeScreen() {
  const { status, error, download, check } = useHindiModel();
  const keyboard = useKeyboardStatus();

  return (
    <ScrollView contentContainerStyle={styles.container}>
      <Text style={styles.title}>Keshu Keyboard</Text>
      <Text style={styles.body}>Write with your finger and it gets typed in Hindi.</Text>

      <View style={styles.card}>
        <Text style={styles.cardTitle}>Hindi handwriting recognition</Text>
        {status === 'checking' && <Text style={styles.body}>Checking…</Text>}
        {status === 'ready' && <Text style={[styles.body, styles.success]}>✓ Ready</Text>}
        {status === 'missing' && (
          <>
            <Text style={styles.body}>
              A one-time download (about 20 MB). After that it works without internet.
            </Text>
            <BigButton label="Download" onPress={download} />
          </>
        )}
        {status === 'downloading' && (
          <>
            <Text style={styles.body}>Downloading… please wait.</Text>
            <BigButton label="Download" onPress={download} loading />
          </>
        )}
        {status === 'error' && (
          <>
            <Text style={[styles.body, styles.danger]}>
              Something went wrong. Turn on the internet and try again.
            </Text>
            {error && <Text style={styles.muted}>{error}</Text>}
            <BigButton label="Try again" onPress={download} />
            <BigButton label="Check again" variant="secondary" onPress={check} />
          </>
        )}
      </View>

      <View style={styles.card}>
        <Text style={styles.cardTitle}>Turn on the keyboard</Text>
        <Step done={keyboard.enabled} number={1} text="Turn on “Keshu Keyboard” in Settings">
          <BigButton label="Open Settings" onPress={() => HindiInk.openKeyboardSettings()} />
        </Step>
        <Step done={keyboard.selected} number={2} text="Choose “Keshu Keyboard” as your keyboard">
          <BigButton
            label="Choose keyboard"
            onPress={() => HindiInk.showKeyboardPicker()}
            disabled={!keyboard.enabled}
          />
        </Step>
        {keyboard.enabled && keyboard.selected && (
          <Text style={[styles.body, styles.success]}>✓ Keyboard is ready. Try it in WhatsApp!</Text>
        )}
      </View>

      <BigButton
        label="Try writing"
        onPress={() => router.push('/practice')}
        disabled={status !== 'ready'}
      />
    </ScrollView>
  );
}

function Step({
  done,
  number,
  text,
  children,
}: {
  done: boolean;
  number: number;
  text: string;
  children: ReactNode;
}) {
  return (
    <View style={styles.step}>
      <Text style={[styles.body, done && styles.success]}>
        {done ? '✓' : `${number}.`} {text}
      </Text>
      {!done && children}
    </View>
  );
}

const styles = StyleSheet.create({
  step: {
    gap: spacing.sm,
  },
  container: {
    padding: spacing.lg,
    gap: spacing.md,
  },
  title: {
    fontSize: fontSize.title,
    fontWeight: '700',
    color: colors.text,
  },
  body: {
    fontSize: fontSize.body,
    color: colors.text,
    lineHeight: fontSize.body * 1.5,
  },
  muted: {
    fontSize: fontSize.body - 4,
    color: colors.muted,
  },
  success: {
    color: colors.success,
    fontWeight: '700',
  },
  danger: {
    color: colors.danger,
  },
  card: {
    borderWidth: 1,
    borderColor: colors.border,
    borderRadius: 12,
    padding: spacing.md,
    gap: spacing.md,
  },
  cardTitle: {
    fontSize: fontSize.button,
    fontWeight: '700',
    color: colors.text,
  },
});
