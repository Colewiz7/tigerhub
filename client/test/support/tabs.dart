/// Finds a tab by its label inside the tab bar, never a card title.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:tigerhub/widgets/tab_bar.dart';

Finder tabLabel(String label) => find.descendant(of: find.byType(AppTabBar), matching: find.text(label));
