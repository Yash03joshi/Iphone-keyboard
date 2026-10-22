import { Stack } from 'expo-router';
import { StatusBar } from 'expo-status-bar';

import { colors, fontSize } from '@/theme';

export default function RootLayout() {
  return (
    <>
      <StatusBar style="dark" />
      <Stack
        screenOptions={{
          headerTitleStyle: { fontSize: fontSize.button },
          contentStyle: { backgroundColor: colors.background },
        }}>
        <Stack.Screen name="index" options={{ title: 'Keshu Keyboard' }} />
        <Stack.Screen name="practice" options={{ title: 'Try writing' }} />
      </Stack>
    </>
  );
}
