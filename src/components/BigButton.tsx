import { ActivityIndicator, Pressable, StyleSheet, Text } from 'react-native';

import { colors, fontSize, minTouchTarget, spacing } from '@/theme';

type Props = {
  label: string;
  onPress: () => void;
  variant?: 'primary' | 'secondary';
  disabled?: boolean;
  loading?: boolean;
};

export function BigButton({ label, onPress, variant = 'primary', disabled, loading }: Props) {
  const primary = variant === 'primary';
  return (
    <Pressable
      accessibilityRole="button"
      onPress={onPress}
      disabled={disabled || loading}
      style={({ pressed }) => [
        styles.button,
        primary ? styles.primary : styles.secondary,
        (disabled || loading) && styles.disabled,
        pressed && styles.pressed,
      ]}>
      {loading ? (
        <ActivityIndicator color={primary ? colors.primaryText : colors.primary} />
      ) : (
        <Text style={[styles.label, { color: primary ? colors.primaryText : colors.primary }]}>
          {label}
        </Text>
      )}
    </Pressable>
  );
}

const styles = StyleSheet.create({
  button: {
    minHeight: minTouchTarget,
    borderRadius: 12,
    paddingHorizontal: spacing.lg,
    alignItems: 'center',
    justifyContent: 'center',
  },
  primary: {
    backgroundColor: colors.primary,
  },
  secondary: {
    backgroundColor: colors.background,
    borderWidth: 2,
    borderColor: colors.primary,
  },
  disabled: {
    opacity: 0.5,
  },
  pressed: {
    opacity: 0.8,
  },
  label: {
    fontSize: fontSize.button,
    fontWeight: '600',
  },
});
