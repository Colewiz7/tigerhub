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
  walk(Icons.directions_walk_rounded, Icons.directions_walk_rounded),

  // --- events ---
  event(CupertinoIcons.calendar_today, Icons.event_rounded),
  day(CupertinoIcons.calendar, Icons.calendar_today_rounded),
  upcoming(CupertinoIcons.hourglass, Icons.upcoming_rounded),
  noEvents(CupertinoIcons.calendar_badge_minus, Icons.event_busy_rounded),
  time(CupertinoIcons.clock, Icons.schedule_rounded),
  location(CupertinoIcons.location, Icons.location_on_rounded),
  hidden(CupertinoIcons.eye_slash, Icons.visibility_off_rounded),
  boost(CupertinoIcons.star_fill, Icons.star_rounded),
  celebration(CupertinoIcons.sparkles, Icons.celebration_rounded),
  school(CupertinoIcons.book, Icons.school_rounded),
  groups(CupertinoIcons.person_3, Icons.groups_rounded),
  muted(CupertinoIcons.bell_slash, Icons.notifications_off_rounded),
  tune(CupertinoIcons.slider_horizontal_3, Icons.tune_rounded),
  night(CupertinoIcons.moon, Icons.nightlight_round),
  everything(CupertinoIcons.infinite, Icons.all_inclusive_rounded),
  spiritual(CupertinoIcons.heart, Icons.self_improvement_rounded),
  blood(CupertinoIcons.drop_fill, Icons.bloodtype_rounded),
  outreach(Icons.campaign_rounded, Icons.campaign_rounded),
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
  swimming(Icons.pool_rounded, Icons.pool_rounded),
  office(CupertinoIcons.person_crop_rectangle, Icons.badge_rounded),

  // --- dining. cupertino has no food glyphs at all, so these stay material ---
  dining(Icons.restaurant_rounded, Icons.restaurant_rounded),
  cutlery(Icons.local_dining_rounded, Icons.local_dining_rounded),
  menu(Icons.restaurant_menu_rounded, Icons.restaurant_menu_rounded),
  visitingChef(Icons.soup_kitchen_rounded, Icons.soup_kitchen_rounded),
  roomService(Icons.room_service_rounded, Icons.room_service_rounded),
  cafe(Icons.local_cafe_rounded, Icons.local_cafe_rounded),
  iceCream(Icons.icecream_rounded, Icons.icecream_rounded),
  plant(Icons.eco_rounded, Icons.eco_rounded),
  meat(Icons.kebab_dining_rounded, Icons.kebab_dining_rounded),
  fish(Icons.set_meal_rounded, Icons.set_meal_rounded),
  breakfast(Icons.egg_alt_rounded, Icons.egg_alt_rounded),
  bakery(Icons.bakery_dining_rounded, Icons.bakery_dining_rounded),
  market(CupertinoIcons.cart, Icons.storefront_rounded),
  globe(CupertinoIcons.globe, Icons.public_rounded),
  truck(Icons.local_shipping_rounded, Icons.local_shipping_rounded),
  grocery(Icons.local_grocery_store_rounded, Icons.local_grocery_store_rounded),
  diningHall(Icons.dinner_dining_rounded, Icons.dinner_dining_rounded),
  smoothie(Icons.blender_rounded, Icons.blender_rounded),
  deli(Icons.lunch_dining_rounded, Icons.lunch_dining_rounded),
  soup(Icons.soup_kitchen_rounded, Icons.soup_kitchen_rounded),
  restaurant(Icons.room_service_rounded, Icons.room_service_rounded),
  patio(Icons.deck_rounded, Icons.deck_rounded),
  // material so it matches the other dining rows
  diningOffice(Icons.info_outline_rounded, Icons.info_outline_rounded),
  pinned(CupertinoIcons.pin_fill, Icons.push_pin_rounded),

  // --- places and safety ---
  emergency(CupertinoIcons.staroflife, Icons.emergency_rounded),
  text(CupertinoIcons.chat_bubble_text, Icons.sms_rounded),
  support(CupertinoIcons.headphones, Icons.support_agent_rounded),
  water(CupertinoIcons.drop, Icons.water_drop_rounded),
  aed(CupertinoIcons.waveform_path_ecg, Icons.monitor_heart_rounded),
  restroom(Icons.wc_rounded, Icons.wc_rounded),
  entrance(CupertinoIcons.square_arrow_right, Icons.door_front_door_rounded),
  atm(CupertinoIcons.money_dollar_circle, Icons.local_atm_rounded),
  evCharge(CupertinoIcons.bolt_fill, Icons.ev_station_rounded),
  card(CupertinoIcons.creditcard, Icons.credit_card_rounded),
  place(CupertinoIcons.map_pin, Icons.place_rounded),
  campus(CupertinoIcons.building_2_fill, Icons.location_city_rounded),
  allPlaces(CupertinoIcons.square_grid_2x2, Icons.apps_rounded),
  // a call box, not a medical post
  blueLight(CupertinoIcons.phone_circle_fill, Icons.emergency_share_rounded),
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

  // --- tabs, outline then selected ---
  todayTab(CupertinoIcons.square_grid_2x2, Icons.grid_view_outlined),
  todayTabSelected(CupertinoIcons.square_grid_2x2_fill, Icons.grid_view_rounded),
  diningTab(Icons.restaurant_outlined, Icons.restaurant_outlined),
  eventsTab(CupertinoIcons.tickets, Icons.event_note_outlined),
  eventsTabSelected(CupertinoIcons.tickets_fill, Icons.event_note_rounded),
  mapTab(CupertinoIcons.map, Icons.map_outlined),
  mapTabSelected(CupertinoIcons.map_fill, Icons.map_rounded),
  campusTab(CupertinoIcons.compass, Icons.location_city_outlined),
  campusTabSelected(CupertinoIcons.compass_fill, Icons.location_city_rounded),

  // --- chrome: buttons, trailing marks, menus ---
  close(CupertinoIcons.xmark, Icons.close_rounded),
  settings(CupertinoIcons.gear_alt, Icons.settings_rounded),
  lock(CupertinoIcons.lock, Icons.lock_outline_rounded),
  add(CupertinoIcons.add, Icons.add_rounded),
  minus(CupertinoIcons.minus, Icons.remove_rounded),
  check(CupertinoIcons.checkmark, Icons.check_rounded),
  checkCircle(CupertinoIcons.checkmark_circle_fill, Icons.check_circle_rounded),
  // the framework defaults, so android draws exactly what it did
  selected(CupertinoIcons.checkmark, Icons.check),
  dropdown(CupertinoIcons.chevron_down, Icons.arrow_drop_down),
  navBack(CupertinoIcons.back, Icons.arrow_back),
  back(CupertinoIcons.back, Icons.arrow_back_rounded),
  forward(CupertinoIcons.forward, Icons.arrow_forward_rounded),
  chevron(CupertinoIcons.chevron_right, Icons.chevron_right_rounded),
  expand(CupertinoIcons.chevron_down, Icons.expand_more_rounded),
  dragHandle(CupertinoIcons.line_horizontal_3, Icons.drag_indicator_rounded),
  more(CupertinoIcons.ellipsis, Icons.more_horiz_rounded),
  edit(CupertinoIcons.pencil, Icons.edit_rounded),
  arrowUp(CupertinoIcons.arrow_up, Icons.arrow_upward_rounded),
  arrowDown(CupertinoIcons.arrow_down, Icons.arrow_downward_rounded),
  delete(CupertinoIcons.trash, Icons.delete_outline_rounded),
  search(CupertinoIcons.search, Icons.search_rounded),
  copy(CupertinoIcons.doc_on_doc, Icons.copy_rounded),
  share(CupertinoIcons.share, Icons.ios_share_rounded),
  linkChain(CupertinoIcons.link, Icons.link_rounded),
  call(CupertinoIcons.phone, Icons.call_rounded),
  email(CupertinoIcons.envelope, Icons.mail_rounded),
  visible(CupertinoIcons.eye, Icons.visibility_rounded),
  unpinned(CupertinoIcons.pin, Icons.push_pin_outlined),
  today(CupertinoIcons.calendar_today, Icons.today_rounded),
  speakerOn(CupertinoIcons.speaker_2, Icons.volume_up_rounded),
  speakerOff(CupertinoIcons.speaker_slash, Icons.volume_off_rounded),
  warning(CupertinoIcons.exclamationmark_triangle, Icons.warning_amber_rounded),
  error(CupertinoIcons.exclamationmark_circle, Icons.error_outline_rounded),
  navigation(CupertinoIcons.location_north_fill, Icons.navigation_rounded),
  route(CupertinoIcons.arrow_branch, Icons.route_rounded),
  recenter(CupertinoIcons.scope, Icons.center_focus_strong_rounded),

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

  /// Kinds that stay Material on iOS because CupertinoIcons has nothing for
  /// them: no food or drink, no wheelchair, bicycle or baby, no toilet sign,
  /// walker, truck, pool or megaphone. Tests hold every other kind, and every
  /// icon iOS renders, to the Cupertino font.
  static const materialOnIos = {
    dining,
    diningTab,
    cutlery,
    menu,
    visitingChef,
    roomService,
    cafe,
    iceCream,
    plant,
    meat,
    fish,
    breakfast,
    bakery,
    grocery,
    diningHall,
    smoothie,
    deli,
    soup,
    restaurant,
    patio,
    diningOffice,
    drink,
    accessible,
    accessibleEntrance,
    bike,
    changingTable,
    lactation,
    restroom,
    walk,
    truck,
    swimming,
    outreach,
  };
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
