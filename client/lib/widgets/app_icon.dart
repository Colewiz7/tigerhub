/// App icons: Cupertino on iOS, Material everywhere else.
///
/// One enum per meaning, so a section names what it is and the platform picks
/// the drawing. SF Symbol files are never bundled, Apple's license forbids it,
/// so iOS gets the CupertinoIcons font, which follows the same style.
library;

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';

enum AppIconKind {
  // --- sections ---
  events(CupertinoIcons.tickets, Icons.event_note_rounded),
  calendar(CupertinoIcons.calendar, Icons.calendar_month_rounded),
  academicDates(CupertinoIcons.calendar_circle, Icons.event_available_rounded),
  mail(CupertinoIcons.envelope, Icons.local_post_office_rounded),
  find(CupertinoIcons.map_pin_ellipse, Icons.travel_explore_rounded),
  makerspace(CupertinoIcons.hammer, Icons.construction_rounded),
  buildings(CupertinoIcons.building_2_fill, Icons.apartment_rounded),
  shuttle(CupertinoIcons.bus, Icons.directions_bus_rounded),
  safety(CupertinoIcons.checkmark_shield, Icons.health_and_safety_rounded),
  link(CupertinoIcons.arrow_up_right_square, Icons.open_in_new_rounded),
  gym(CupertinoIcons.sportscourt, Icons.fitness_center_rounded),
  appearance(CupertinoIcons.paintbrush, Icons.palette_rounded),
  wallpaper(CupertinoIcons.photo, Icons.wallpaper_rounded),
  info(CupertinoIcons.info_circle, Icons.info_outline_rounded),
  map(CupertinoIcons.map, Icons.map_rounded),
  mailbox(CupertinoIcons.envelope_badge, Icons.markunread_mailbox_rounded),
  widgets(CupertinoIcons.rectangle_grid_2x2, Icons.widgets_rounded),
  walk(CupertinoIcons.person_alt, Icons.directions_walk_rounded),

  // --- events ---
  event(CupertinoIcons.calendar_today, Icons.event_rounded),
  day(CupertinoIcons.calendar, Icons.calendar_today_rounded),
  upcoming(CupertinoIcons.hourglass, Icons.upcoming_rounded),
  noEvents(CupertinoIcons.calendar_badge_minus, Icons.event_busy_rounded),
  time(CupertinoIcons.clock, Icons.schedule_rounded),
  location(CupertinoIcons.location, Icons.location_on_rounded),
  hidden(CupertinoIcons.eye_slash, Icons.visibility_off_rounded),
  past(CupertinoIcons.arrow_counterclockwise, Icons.history_rounded),
  boost(CupertinoIcons.star_fill, Icons.star_rounded),
  celebration(CupertinoIcons.star, Icons.celebration_rounded),
  school(CupertinoIcons.book, Icons.school_rounded),
  groups(CupertinoIcons.person_3, Icons.groups_rounded),
  muted(CupertinoIcons.bell_slash, Icons.notifications_off_rounded),
  tune(CupertinoIcons.slider_horizontal_3, Icons.tune_rounded),
  night(CupertinoIcons.moon, Icons.nightlight_round),
  everything(CupertinoIcons.infinite, Icons.all_inclusive_rounded),
  spiritual(CupertinoIcons.heart, Icons.self_improvement_rounded),
  blood(CupertinoIcons.drop_fill, Icons.bloodtype_rounded),
  outreach(CupertinoIcons.speaker_3, Icons.campaign_rounded),
  volunteer(CupertinoIcons.hand_raised, Icons.volunteer_activism_rounded),
  housing(CupertinoIcons.house, Icons.home_rounded),

  // --- sport, cupertino has one court for all of them ---
  athletics(CupertinoIcons.flag, Icons.sports_score_rounded),
  basketball(CupertinoIcons.sportscourt_fill, Icons.sports_basketball_rounded),
  soccer(CupertinoIcons.sportscourt_fill, Icons.sports_soccer_rounded),
  volleyball(CupertinoIcons.sportscourt_fill, Icons.sports_volleyball_rounded),
  hockey(CupertinoIcons.sportscourt_fill, Icons.sports_hockey_rounded),
  tennis(CupertinoIcons.sportscourt_fill, Icons.sports_tennis_rounded),
  baseball(CupertinoIcons.sportscourt_fill, Icons.sports_baseball_rounded),
  rowing(CupertinoIcons.sportscourt_fill, Icons.rowing_rounded),
  climbing(CupertinoIcons.triangle, Icons.terrain_rounded),
  running(CupertinoIcons.hare, Icons.directions_run_rounded),
  swimming(CupertinoIcons.waveform, Icons.pool_rounded),
  office(CupertinoIcons.person_crop_rectangle, Icons.badge_rounded),

  // --- dining. cupertino has no food glyphs at all, so these stay material ---
  dining(Icons.restaurant_rounded, Icons.restaurant_rounded),
  cutlery(Icons.local_dining_rounded, Icons.local_dining_rounded),
  menu(Icons.restaurant_menu_rounded, Icons.restaurant_menu_rounded),
  visitingChef(Icons.soup_kitchen_rounded, Icons.soup_kitchen_rounded),
  roomService(Icons.room_service_rounded, Icons.room_service_rounded),
  cafe(Icons.local_cafe_rounded, Icons.local_cafe_rounded),
  iceCream(Icons.icecream_rounded, Icons.icecream_rounded),
  salad(Icons.eco_rounded, Icons.eco_rounded),
  breakfast(Icons.egg_alt_rounded, Icons.egg_alt_rounded),
  bakery(Icons.bakery_dining_rounded, Icons.bakery_dining_rounded),
  market(CupertinoIcons.cart, Icons.storefront_rounded),
  globe(CupertinoIcons.globe, Icons.public_rounded),
  truck(CupertinoIcons.car, Icons.local_shipping_rounded),
  pinned(CupertinoIcons.pin, Icons.push_pin_rounded),

  // --- places and safety ---
  emergency(CupertinoIcons.staroflife, Icons.emergency_rounded),
  text(CupertinoIcons.chat_bubble_text, Icons.sms_rounded),
  support(CupertinoIcons.headphones, Icons.support_agent_rounded),
  water(CupertinoIcons.drop, Icons.water_drop_rounded),
  aed(CupertinoIcons.waveform_path_ecg, Icons.monitor_heart_rounded),
  restroom(CupertinoIcons.person_2, Icons.wc_rounded),
  entrance(CupertinoIcons.square_arrow_right, Icons.door_front_door_rounded),
  atm(CupertinoIcons.money_dollar_circle, Icons.local_atm_rounded),
  evCharge(CupertinoIcons.bolt_fill, Icons.ev_station_rounded),
  card(CupertinoIcons.creditcard, Icons.credit_card_rounded),
  place(CupertinoIcons.map_pin, Icons.place_rounded),
  campus(CupertinoIcons.building_2_fill, Icons.location_city_rounded),
  allPlaces(CupertinoIcons.square_grid_2x2, Icons.apps_rounded),
  blueLight(CupertinoIcons.staroflife_fill, Icons.emergency_share_rounded),
  reload(CupertinoIcons.creditcard_fill, Icons.add_card_rounded),
  timeClock(CupertinoIcons.clock_fill, Icons.punch_clock_rounded),
  printer(CupertinoIcons.printer, Icons.print_rounded),
  study(CupertinoIcons.book_fill, Icons.menu_book_rounded),
  computer(CupertinoIcons.desktopcomputer, Icons.computer_rounded),
  hub(CupertinoIcons.antenna_radiowaves_left_right, Icons.hub_rounded),
  recycling(CupertinoIcons.leaf_arrow_circlepath, Icons.recycling_rounded),
  // no wheelchair, bicycle, baby or drink in cupertino
  accessible(Icons.accessible_rounded, Icons.accessible_rounded),
  accessibleEntrance(Icons.accessible_forward_rounded, Icons.accessible_forward_rounded),
  bike(Icons.pedal_bike_rounded, Icons.pedal_bike_rounded),
  changingTable(Icons.baby_changing_station_rounded, Icons.baby_changing_station_rounded),
  lactation(Icons.child_care_rounded, Icons.child_care_rounded),
  drink(Icons.local_drink_rounded, Icons.local_drink_rounded),

  // --- shed ---
  machines(CupertinoIcons.gear, Icons.precision_manufacturing_rounded),
  printer3d(CupertinoIcons.cube, Icons.view_in_ar_rounded),
  laser(CupertinoIcons.bolt, Icons.blur_on_rounded),
  wood(CupertinoIcons.hammer_fill, Icons.carpenter_rounded),
  metal(CupertinoIcons.wrench_fill, Icons.hardware_rounded),
  textile(CupertinoIcons.scissors_alt, Icons.checkroom_rounded),
  electronics(CupertinoIcons.device_laptop, Icons.memory_rounded),
  vinyl(CupertinoIcons.scissors, Icons.content_cut_rounded),
  tools(CupertinoIcons.wrench, Icons.build_rounded),

  // --- empty states ---
  notFound(CupertinoIcons.search, Icons.search_off_rounded),
  offline(CupertinoIcons.wifi_slash, Icons.cloud_off_rounded),
  sourceDown(CupertinoIcons.exclamationmark_triangle, Icons.sync_problem_rounded);

  const AppIconKind(this.cupertino, this.material);

  final IconData cupertino;
  final IconData material;

  IconData of(BuildContext context) => on(Theme.of(context).platform);

  // painters have no context
  IconData on(TargetPlatform platform) => platform == TargetPlatform.iOS ? cupertino : material;
}

class AppIcon extends StatelessWidget {
  const AppIcon(this.kind, {super.key, this.size = 18, this.color});

  final AppIconKind kind;
  final double size;

  /// Defaults to the surrounding text colour, so the icon matches its label.
  final Color? color;

  @override
  Widget build(BuildContext context) => Icon(
    kind.of(context),
    size: size,
    color: color ?? DefaultTextStyle.of(context).style.color,
  );
}
