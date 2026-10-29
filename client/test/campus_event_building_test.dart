import 'package:flutter_test/flutter_test.dart';
import 'package:tigerhub/data/merge_events.dart';
import 'package:tigerhub/data/sources/campusgroups.dart';
import 'package:tigerhub/data/sources/drupal_events.dart';
import 'package:tigerhub/models/api_models.dart';

Map<String, dynamic> raw(String uid, String source, {String? building, String? room, String? location}) => {
  'uid': uid,
  'source': source,
  'title': 'Co-op Connections',
  'starts_at': '2026-09-16T19:00:00Z',
  'building': building,
  'room': room,
  'location': location,
};

void main() {
  test('fromJson reads building and room', () {
    final event = CampusEvent.fromJson(raw('a', 'test', building: 'Gleason Hall', room: '2000'));
    expect(event.building, 'Gleason Hall');
    expect(event.room, '2000');
  });

  test('missing building and room stay null', () {
    final event = CampusEvent.fromJson(raw('a', 'test'));
    expect(event.building, isNull);
    expect(event.room, isNull);
  });

  test('merged Drupal and CampusGroups copy keeps the Drupal building', () {
    final merged = mergeDuplicateEvents([
      raw('d', drupalSource, building: 'Gleason Hall', room: '2000'),
      raw('c', campusGroupsSource, location: 'GLE atrium'),
    ]);
    final event = CampusEvent.fromJson(merged.single);
    expect(event.building, 'Gleason Hall');
    expect(event.room, '2000');
    expect(event.location, 'GLE atrium');
  });
}
