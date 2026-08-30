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

/// One resolved open period on the current day. All of it computed server
/// side, so the client only formats it.
class OpenSpan {
  const OpenSpan({required this.opensAt, required this.closesAt, this.isException = false});

  final DateTime opensAt;
  final DateTime closesAt;
  final bool isException;

  factory OpenSpan.fromJson(Map<String, dynamic> json) => OpenSpan(
        opensAt: _date(json['opens_at']) ?? DateTime.now(),
        closesAt: _date(json['closes_at']) ?? DateTime.now(),
        isException: json['is_exception'] as bool? ?? false,
      );
}

class DiningLocation {
  const DiningLocation({
    required this.id,
    required this.name,
    required this.isOpen,
    this.category = 'other',
    this.categoryName = 'Everything else',
    this.categoryOrder = 999,
    this.summary,
    this.description,
    this.mapsUrl,
    this.today = const [],
    this.opensAt,
    this.closesAt,
    this.nextTransition,
    this.occupancy,
  });

  final int id;
  final String name;

  /// From the server's static config. TigerCenter publishes no category.
  final String category;
  final String categoryName;
  final int categoryOrder;

  final String? summary;

  /// HTML from TigerCenter, flattened at the point of display.
  final String? description;

  final String? mapsUrl;

  /// Today's resolved open periods. A location can open twice in a day.
  final List<OpenSpan> today;

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
        category: json['category'] as String? ?? 'other',
        categoryName: json['category_name'] as String? ?? 'Everything else',
        categoryOrder: json['category_order'] as int? ?? 999,
        summary: json['summary'] as String?,
        description: json['description'] as String?,
        mapsUrl: json['maps_url'] as String?,
        today: (json['today'] as List<dynamic>? ?? const [])
            .map((e) => OpenSpan.fromJson(e as Map<String, dynamic>))
            .toList(),
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
    this.endsAt,
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

  /// Used to decide whether an event has already finished, so past and future
  /// can be told apart visually.
  final DateTime? endsAt;

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
        endsAt: _date(json['ends_at']),
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

class HoursRule {
  const HoursRule({
    required this.days,
    required this.opensAt,
    required this.closesAt,
    this.season = 'academic',
    this.service = 'general',
  });

  final List<String> days;
  final String opensAt;
  final String closesAt;
  final String season;

  /// Post offices run a package counter and a shipping window on different
  /// hours, so a rule is per service.
  final String service;

  factory HoursRule.fromJson(Map<String, dynamic> json) => HoursRule(
        days: (json['days'] as List<dynamic>? ?? const [])
            .map((e) => e as String)
            .toList(),
        opensAt: json['opens_at'] as String? ?? '',
        closesAt: json['closes_at'] as String? ?? '',
        season: json['season'] as String? ?? 'academic',
        service: json['service'] as String? ?? 'general',
      );
}

class PostOffice {
  const PostOffice({
    required this.id,
    required this.name,
    required this.side,
    required this.building,
    required this.street,
    required this.city,
    required this.state,
    required this.zip,
    required this.hours,
    this.locationNote,
    this.email,
    this.phone,
  });

  final String id;
  final String name;
  final String side;
  final String building;
  final String street;
  final String city;
  final String state;
  final String zip;
  final String? locationNote;
  final String? email;
  final String? phone;
  final List<HoursRule> hours;

  factory PostOffice.fromJson(Map<String, dynamic> json) => PostOffice(
        id: json['id'] as String,
        name: json['name'] as String,
        side: json['side'] as String? ?? '',
        building: json['building'] as String? ?? '',
        street: json['street'] as String? ?? '',
        city: json['city'] as String? ?? '',
        state: json['state'] as String? ?? '',
        zip: json['zip'] as String? ?? '',
        locationNote: json['location_note'] as String?,
        email: json['email'] as String?,
        phone: json['phone'] as String?,
        hours: (json['hours'] as List<dynamic>? ?? const [])
            .map((e) => HoursRule.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class Dish {
  const Dish({
    required this.name,
    this.category,
    this.allergens = const [],
    this.dietary = const [],
    this.calories,
  });

  final String name;
  final String? category;

  /// Exactly as RIT publishes them. Never interpreted or extended.
  final List<String> allergens;
  final List<String> dietary;
  final double? calories;

  factory Dish.fromJson(Map<String, dynamic> json) => Dish(
        name: json['name'] as String? ?? '',
        category: json['category'] as String?,
        allergens: (json['allergens'] as List<dynamic>? ?? const [])
            .map((e) => e as String)
            .toList(),
        dietary: (json['dietary'] as List<dynamic>? ?? const [])
            .map((e) => e as String)
            .toList(),
        calories: (json['calories'] as num?)?.toDouble(),
      );

  bool get isVegan => dietary.any((d) => d.toLowerCase() == 'vegan');
  bool get isVegetarian =>
      dietary.any((d) => d.toLowerCase().contains('vegetarian')) || isVegan;

  /// A "may contain traces" note is a weaker claim than a listed allergen, so
  /// the two are separated rather than merged.
  bool mentions(String allergen) =>
      allergens.any((a) => a.toLowerCase().contains(allergen.toLowerCase()));
}

class MenuDay {
  const MenuDay({
    required this.locationId,
    required this.serviceDate,
    required this.dishes,
  });

  final int locationId;
  final DateTime serviceDate;
  final List<Dish> dishes;

  factory MenuDay.fromJson(Map<String, dynamic> json) => MenuDay(
        locationId: json['location_id'] as int? ?? 0,
        serviceDate:
            DateTime.tryParse(json['service_date'] as String? ?? '') ?? DateTime.now(),
        dishes: (json['dishes'] as List<dynamic>? ?? const [])
            .map((e) => Dish.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class OccupancyHour {
  const OccupancyHour({
    required this.hour,
    required this.today,
    required this.oneWeekAgo,
    required this.average,
  });

  final int hour;
  final int today;
  final int oneWeekAgo;
  final int average;

  factory OccupancyHour.fromJson(Map<String, dynamic> json) => OccupancyHour(
        hour: json['hour'] as int? ?? 0,
        today: json['today'] as int? ?? 0,
        oneWeekAgo: json['one_week_ago'] as int? ?? 0,
        average: json['average'] as int? ?? 0,
      );
}

class OccupancyHistory {
  const OccupancyHistory({
    required this.mdoId,
    required this.hourly,
    this.count,
    this.maxOcc,
    this.openStatus,
  });

  final int mdoId;
  final List<OccupancyHour> hourly;
  final int? count;
  final int? maxOcc;
  final String? openStatus;

  factory OccupancyHistory.fromJson(Map<String, dynamic> json) => OccupancyHistory(
        mdoId: json['mdo_id'] as int? ?? 0,
        count: json['count'] as int?,
        maxOcc: json['max_occ'] as int?,
        openStatus: json['open_status'] as String?,
        hourly: (json['hourly'] as List<dynamic>? ?? const [])
            .map((e) => OccupancyHour.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class RecreationSpan {
  const RecreationSpan({required this.opensAt, required this.closesAt});

  final String opensAt;
  final String closesAt;

  factory RecreationSpan.fromJson(Map<String, dynamic> json) => RecreationSpan(
        opensAt: json['opens_at'] as String? ?? '',
        closesAt: json['closes_at'] as String? ?? '',
      );
}

class RecreationDay {
  const RecreationDay({
    required this.serviceDate,
    required this.closed,
    required this.spans,
    this.note,
  });

  final DateTime serviceDate;
  final bool closed;

  /// Several sessions in one day is normal. The pool runs a morning lap swim,
  /// a lunch block and an evening block.
  final List<RecreationSpan> spans;
  final String? note;

  factory RecreationDay.fromJson(Map<String, dynamic> json) => RecreationDay(
        serviceDate:
            DateTime.tryParse(json['service_date'] as String? ?? '') ?? DateTime.now(),
        closed: json['closed'] as bool? ?? false,
        note: json['note'] as String?,
        spans: (json['spans'] as List<dynamic>? ?? const [])
            .map((e) => RecreationSpan.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class RecreationFacility {
  const RecreationFacility({required this.name, required this.days});

  final String name;
  final List<RecreationDay> days;

  factory RecreationFacility.fromJson(Map<String, dynamic> json) =>
      RecreationFacility(
        name: json['name'] as String? ?? '',
        days: (json['days'] as List<dynamic>? ?? const [])
            .map((e) => RecreationDay.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class MakerSpaceHours {
  const MakerSpaceHours({
    required this.id,
    required this.name,
    required this.location,
    required this.hours,
  });

  final String id;
  final String name;
  final String location;
  final List<HoursRule> hours;

  factory MakerSpaceHours.fromJson(Map<String, dynamic> json) => MakerSpaceHours(
        id: json['id'] as String,
        name: json['name'] as String,
        location: json['location'] as String? ?? '',
        hours: (json['hours'] as List<dynamic>? ?? const [])
            .map((e) => HoursRule.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class RoomSummary {
  const RoomSummary({
    required this.room,
    required this.machines,
    required this.available,
    required this.inUse,
  });

  final String room;
  final int machines;
  final int available;
  final int inUse;

  factory RoomSummary.fromJson(Map<String, dynamic> json) => RoomSummary(
        room: json['room'] as String? ?? 'Other',
        machines: json['machines'] as int? ?? 0,
        available: json['available'] as int? ?? 0,
        inUse: json['in_use'] as int? ?? 0,
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
