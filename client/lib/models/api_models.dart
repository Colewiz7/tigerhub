/// Response models mirroring the backend contract.
///
/// The client does zero date math. `isOpen`, `opensAt`, `closesAt`, and
/// `nextTransition` are computed server side and only displayed here.
library;

/// Envelope returned by every list endpoint.
class Collection<T> {
  const Collection({required this.data, required this.stale, this.lastUpdated});

  final List<T> data;
  final bool stale;
  final DateTime? lastUpdated;

  factory Collection.fromJson(
    Map<String, dynamic> json,
    T Function(Map<String, dynamic>) parse,
  ) {
    final raw = (json['data'] as List<dynamic>? ?? const []);
    return Collection<T>(
      data: raw.map((e) => parse(e as Map<String, dynamic>)).toList(),
      stale: json['stale'] as bool? ?? false,
      lastUpdated: _date(json['last_updated']),
    );
  }

  Collection<T> copyWith({bool? stale}) =>
      Collection<T>(data: data, stale: stale ?? this.stale, lastUpdated: lastUpdated);
}

DateTime? _date(Object? value) =>
    value is String ? DateTime.tryParse(value)?.toLocal() : null;

class Occupancy {
  const Occupancy({
    this.count,
    this.maxOcc,
    this.openStatus,
    this.percentFull,
    this.overCapacity = false,
  });

  final int? count;
  final int? maxOcc;
  final String? openStatus;
  final int? percentFull;

  /// The live count exceeds RIT's published capacity, so the percentage is not
  /// trustworthy and the chip shows a qualitative label instead.
  final bool overCapacity;

  factory Occupancy.fromJson(Map<String, dynamic> json) => Occupancy(
        count: json['count'] as int?,
        maxOcc: json['max_occ'] as int?,
        openStatus: json['open_status'] as String?,
        percentFull: json['percent_full'] as int?,
        overCapacity: json['over_capacity'] as bool? ?? false,
      );
}

class DiningLocation {
  const DiningLocation({
    required this.id,
    required this.name,
    required this.isOpen,
    this.summary,
    this.opensAt,
    this.closesAt,
    this.nextTransition,
    this.occupancy,
  });

  final int id;
  final String name;
  final String? summary;
  final bool isOpen;
  final DateTime? opensAt;
  final DateTime? closesAt;
  final DateTime? nextTransition;

  /// Null for the 19 locations with no sensor. Nothing is rendered for those,
  /// not a placeholder and not a "no data" label.
  final Occupancy? occupancy;

  factory DiningLocation.fromJson(Map<String, dynamic> json) => DiningLocation(
        id: json['id'] as int,
        name: json['name'] as String,
        summary: json['summary'] as String?,
        isOpen: json['is_open'] as bool? ?? false,
        opensAt: _date(json['opens_at']),
        closesAt: _date(json['closes_at']),
        nextTransition: _date(json['next_transition']),
        occupancy: json['occupancy'] == null
            ? null
            : Occupancy.fromJson(json['occupancy'] as Map<String, dynamic>),
      );
}

class MenuItem {
  const MenuItem({
    required this.id,
    required this.locationName,
    required this.name,
    this.description,
    this.category,
  });

  final int id;
  final String locationName;
  final String name;
  final String? description;
  final String? category;

  factory MenuItem.fromJson(Map<String, dynamic> json) => MenuItem(
        id: json['id'] as int,
        locationName: json['location_name'] as String? ?? '',
        name: json['name'] as String? ?? '',
        description: json['description'] as String?,
        category: json['category'] as String?,
      );
}

class CampusEvent {
  const CampusEvent({
    required this.uid,
    required this.source,
    required this.title,
    required this.startsAt,
    this.location,
    this.organizer,
    this.organizerKey,
    this.eventType,
    this.url,
    this.allDay = false,
  });

  final String uid;
  final String source;
  final String title;
  final DateTime startsAt;
  final String? location;
  final String? organizer;
  final String? organizerKey;
  final String? eventType;
  final String? url;
  final bool allDay;

  factory CampusEvent.fromJson(Map<String, dynamic> json) => CampusEvent(
        uid: json['uid'] as String,
        source: json['source'] as String? ?? '',
        title: json['title'] as String? ?? '',
        startsAt: _date(json['starts_at']) ?? DateTime.now(),
        location: json['location'] as String?,
        organizer: json['organizer'] as String?,
        organizerKey: json['organizer_key'] as String?,
        eventType: json['event_type'] as String?,
        url: json['url'] as String?,
        allDay: json['all_day'] as bool? ?? false,
      );
}

class HousingArea {
  const HousingArea({
    required this.id,
    required this.name,
    this.directDelivery = false,
    this.line2Example,
  });

  final String id;
  final String name;
  final bool directDelivery;
  final String? line2Example;

  factory HousingArea.fromJson(Map<String, dynamic> json) => HousingArea(
        id: json['id'] as String,
        name: json['name'] as String,
        directDelivery: json['direct_delivery'] as bool? ?? false,
        line2Example: json['line2_example'] as String?,
      );
}

class MailingAddress {
  const MailingAddress({
    required this.areaId,
    required this.areaName,
    required this.lines,
    required this.verified,
    required this.unitSupplied,
    this.directDelivery = false,
    this.line2Format,
    this.line2Example,
    this.note,
    this.postOfficeName,
  });

  final String areaId;
  final String areaName;
  final List<String> lines;
  final bool verified;
  final bool unitSupplied;
  final bool directDelivery;
  final String? line2Format;
  final String? line2Example;
  final String? note;
  final String? postOfficeName;

  factory MailingAddress.fromJson(Map<String, dynamic> json) => MailingAddress(
        areaId: json['area_id'] as String,
        areaName: json['area_name'] as String,
        lines: (json['lines'] as List<dynamic>? ?? const [])
            .map((e) => e as String)
            .toList(),
        verified: json['verified'] as bool? ?? false,
        unitSupplied: json['unit_supplied'] as bool? ?? false,
        directDelivery: json['direct_delivery'] as bool? ?? false,
        line2Format: json['line2_format'] as String?,
        line2Example: json['line2_example'] as String?,
        note: json['note'] as String?,
        postOfficeName: (json['post_office'] as Map<String, dynamic>?)?['name'] as String?,
      );
}
