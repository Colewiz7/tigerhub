/// Campus layout: diffs from the shipped sections, and the saved copy.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:tigerhub/data/campus_layout.dart';
import 'package:tigerhub/services/cache.dart';
import 'package:tigerhub/services/preferences.dart';

const _defaults = ['a', 'b', 'c', 'd'];

void main() {
  group('defaults', () {
    test('an untouched layout is empty and encodes to nothing', () {
      expect(CampusLayout.empty.isEmpty, isTrue);
      expect(CampusLayout.empty.encode(), isNull);
      expect(CampusLayout.empty.sectionOrder(_defaults), _defaults);
      expect(CampusLayout.empty.allOffices, isFalse);
    });

    test('the shipped sections have no Shuttles row', () {
      expect(campusSectionIds, isNot(contains('shuttles')));
      expect(campusSectionIds.length, 7);
    });
  });

  group('storage format', () {
    test('only differences are written', () {
      final layout = CampusLayout.empty.hideSection('b').hideOffice('dsp');
      expect(layout.encode(), '{"v":1,"hidden":["b"],"offices":["dsp"]}');
    });

    test('a layout survives a round trip', () {
      final layout = CampusLayout.empty
          .moveSection('c', -1, _defaults)
          .hideSection('d')
          .hideOffice('dsp')
          .hideFacility('Aquatic Center')
          .withAllOffices(true)
          .markSafetyAsked();
      final back = CampusLayout.parse(layout.encode());
      expect(back.order, ['a', 'c', 'b', 'd']);
      expect(back.hidden, {'d'});
      expect(back.hiddenOffices, {'dsp'});
      expect(back.hiddenFacilities, {'Aquatic Center'});
      expect(back.allOffices, isTrue);
      expect(back.safetyAsked, isTrue);
    });

    test('corrupt, empty and newer data load as the defaults', () {
      expect(CampusLayout.parse(null).isEmpty, isTrue);
      expect(CampusLayout.parse('').isEmpty, isTrue);
      expect(CampusLayout.parse('{not json').isEmpty, isTrue);
      expect(CampusLayout.parse('[1]').isEmpty, isTrue);
      expect(CampusLayout.parse('{"v":2,"hidden":["a"]}').isEmpty, isTrue);
      expect(CampusLayout.parse('{"v":1,"hidden":[1]}').isEmpty, isTrue);
    });
  });

  group('order', () {
    test('a section id that no longer ships is ignored and a new one lands last', () {
      final layout = CampusLayout.parse('{"v":1,"order":["gone","c"]}');
      expect(layout.sectionOrder(_defaults), ['c', 'a', 'b', 'd']);
    });

    test('Move up and Move down swap neighbours', () {
      final up = CampusLayout.empty.moveSection('c', -1, _defaults);
      expect(up.sectionOrder(_defaults), ['a', 'c', 'b', 'd']);
      expect(up.moveSection('c', 1, _defaults).sectionOrder(_defaults), _defaults);
    });

    test('moving back to the shipped order stores nothing', () {
      final layout = CampusLayout.empty.moveSection('b', 1, _defaults).moveSection('b', -1, _defaults);
      expect(layout.order, isEmpty);
      expect(layout.isEmpty, isTrue);
    });

    test('the ends do not move off the list', () {
      expect(CampusLayout.empty.moveSection('a', -1, _defaults).isEmpty, isTrue);
      expect(CampusLayout.empty.moveSection('d', 1, _defaults).isEmpty, isTrue);
      expect(CampusLayout.empty.moveSection('nope', 1, _defaults).isEmpty, isTrue);
    });

    test('a move steps over hidden rows so it is always seen', () {
      final layout = CampusLayout.empty.hideSection('b').moveSection('c', -1, _defaults);
      expect(layout.visibleSections(_defaults), ['c', 'a', 'd']);
    });
  });

  group('hiding', () {
    test('hide and show are inverse and idempotent', () {
      final hid = CampusLayout.empty.hideSection('b').hideSection('b');
      expect(hid.hidden, {'b'});
      expect(hid.visibleSections(_defaults), ['a', 'c', 'd']);
      expect(hid.showSection('b').isEmpty, isTrue);
    });

    test('offices and facilities hide on their own', () {
      final layout = CampusLayout.empty.hideOffice('dsp').hideFacility('Pool');
      expect(layout.hidden, isEmpty);
      expect(layout.hasHidden, isTrue);
      expect(layout.showOffice('dsp').showFacility('Pool').isEmpty, isTrue);
    });

    test('Unhide all keeps the order, the office choice and the Safety note', () {
      final layout = CampusLayout.empty
          .moveSection('c', -1, _defaults)
          .hideSection('a')
          .hideOffice('dsp')
          .hideFacility('Pool')
          .withAllOffices(true)
          .markSafetyAsked()
          .unhideAll();
      expect(layout.hasHidden, isFalse);
      expect(layout.order, ['a', 'c', 'b', 'd']);
      expect(layout.allOffices, isTrue);
      expect(layout.safetyAsked, isTrue);
    });
  });

  group('storage', () {
    setUp(() {
      SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
      Preferences.instance.resetForTests();
    });
    tearDown(Preferences.instance.resetForTests);

    test('the layout survives a reload', () async {
      final prefs = Preferences.instance;
      await prefs.setCampusLayout(CampusLayout.empty.hideSection('links').withAllOffices(true));
      prefs.resetForTests();
      expect(prefs.campusLayout.isEmpty, isTrue);
      await prefs.load();
      expect(prefs.campusLayout.hidden, {'links'});
      expect(prefs.campusLayout.allOffices, isTrue);
    });

    test('a corrupt saved layout loads as the defaults', () async {
      await ResponseCache.instance.writeOrder('campus_layout', ['{not json']);
      await Preferences.instance.load();
      expect(Preferences.instance.campusLayout.isEmpty, isTrue);
    });

    test('reset clears the saved copy and tells listeners', () async {
      final prefs = Preferences.instance;
      await prefs.setCampusLayout(CampusLayout.empty.hideSection('links'));
      var heard = 0;
      prefs.addListener(() => heard++);
      await prefs.resetCampus();
      expect(heard, 1);
      prefs.resetForTests();
      await prefs.load();
      expect(prefs.campusLayout.isEmpty, isTrue);
      expect(await ResponseCache.instance.readOrder('campus_layout'), isEmpty);
    });
  });
}
