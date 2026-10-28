/// A Today card on a phone previews at most three rows.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tigerhub/widgets/bounded_list.dart';

void main() {
  Future<({int? plain, int? calendar})> caps(WidgetTester tester, double width) async {
    late int? plain;
    late int? calendar;
    await tester.pumpWidget(MediaQuery(
      data: MediaQueryData(size: Size(width, 844)),
      child: Builder(builder: (context) {
        plain = phoneRowCap(context);
        // the week strip takes one row
        calendar = phoneRowCap(context, reserved: 1);
        return const SizedBox();
      }),
    ));
    return (plain: plain, calendar: calendar);
  }

  testWidgets('three rows on a phone, two beside the calendar strip', (tester) async {
    expect(phonePreviewRows, 3);
    final phone = await caps(tester, 390);
    expect(phone.plain, 3);
    expect(phone.calendar, 2);
  });

  testWidgets('no cap from 600 wide, the cell bounds the list', (tester) async {
    final wide = await caps(tester, 600);
    expect(wide.plain, isNull);
    expect(wide.calendar, isNull);
  });
}
