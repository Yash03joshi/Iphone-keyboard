import { requireNativeView } from 'expo';
import * as React from 'react';

import { HindiInkViewProps, HindiInkViewRef } from './HindiInk.types';

const NativeView: React.ComponentType<HindiInkViewProps & React.RefAttributes<HindiInkViewRef>> =
  requireNativeView('HindiInk');

export default function HindiInkView(
  props: HindiInkViewProps & { ref?: React.Ref<HindiInkViewRef> }
) {
  return <NativeView {...props} />;
}
