/// One switch for reduced motion.
library;

import 'package:flutter/widgets.dart';

// ios reduce motion never reaches MediaQuery
bool reduceMotion(BuildContext context) => (MediaQuery.maybeDisableAnimationsOf(context) ?? false) || (MediaQuery.maybeAccessibleNavigationOf(context) ?? false) || (View.maybeOf(context)?.platformDispatcher.accessibilityFeatures.reduceMotion ?? false);
