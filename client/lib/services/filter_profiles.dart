/// Filter profiles.
///
/// Tuning ten keyword rules by hand is more work than most people will do, so
/// the app ships a few presets that encode a whole taste in one tap. The
/// preset list is deliberately opinionated rather than generic: a preset that
/// says nothing is no easier than starting from scratch.
///
/// Editing while a preset is active forks to Custom rather than silently
/// mutating the preset, so switching back is always possible.
library;

import 'package:flutter/material.dart';

import 'preferences.dart';

class FilterProfile {
  const FilterProfile({
    required this.id,
    required this.name,
    required this.description,
    required this.icon,
    required this.hide,
    required this.boost,
    this.keywordsEnabled = true,
  });

  final String id;
  final String name;
  final String description;
  final IconData icon;
  final List<String> hide;
  final List<String> boost;
  final bool keywordsEnabled;

  /// The user's own edits. Its rules live in Preferences, not here.
  static const String customId = 'custom';
}

const List<FilterProfile> builtInProfiles = [
  FilterProfile(
    id: 'free_and_fun',
    name: 'Free and fun',
    description: 'Free food, games, tournaments. Hides info sessions, career '
        'fairs, religious services and tutoring.',
    icon: Icons.celebration_rounded,
    hide: [
      'tutoring',
      'info session',
      'information session',
      'workshop',
      'seminar',
      'career fair',
      'club fair',
      'recruitment',
      'bible study',
      'mass',
      'worship',
      'prayer',
      'study abroad',
      'resume',
    ],
    boost: [
      'free',
      'food',
      'ice cream',
      'pizza',
      'game',
      'tournament',
      'trivia',
      'movie',
      'concert',
      'festival',
    ],
  ),
  FilterProfile(
    id: 'academic',
    name: 'Academic and career',
    description: 'The opposite. Workshops, info sessions, career events and '
        'tutoring come first.',
    icon: Icons.school_rounded,
    hide: [],
    boost: [
      'workshop',
      'info session',
      'seminar',
      'career',
      'resume',
      'tutoring',
      'research',
      'co-op',
    ],
  ),
  FilterProfile(
    id: 'quiet',
    name: 'Low key',
    description: 'Hides the high volume recurring stuff so one-off events are '
        'visible.',
    icon: Icons.nightlight_round,
    hide: [
      'attendance tracking',
      'tabling',
      'meeting',
      'office hours',
      'drop-in',
      'weekly',
    ],
    boost: [],
  ),
  FilterProfile(
    id: 'everything',
    name: 'Everything',
    description: 'No keyword rules at all. Organizer mutes still apply.',
    icon: Icons.all_inclusive_rounded,
    hide: [],
    boost: [],
    keywordsEnabled: false,
  ),
];

FilterProfile? profileById(String id) {
  for (final profile in builtInProfiles) {
    if (profile.id == id) return profile;
  }
  return null;
}

/// Does the stored rule set still match this preset?
///
/// Used to detect that the user has edited away from a preset, so the UI can
/// show Custom rather than claiming a preset that is no longer in force.
bool matchesProfile(FilterProfile profile, Preferences prefs) {
  bool sameSet(List<String> a, List<String> b) =>
      a.length == b.length && a.toSet().containsAll(b);
  return prefs.keywordRulesEnabled == profile.keywordsEnabled &&
      sameSet(prefs.hideKeywords, profile.hide) &&
      sameSet(prefs.boostKeywords, profile.boost);
}

/// The preset currently in force, or null when the rules are the user's own.
FilterProfile? activeProfile(Preferences prefs) {
  for (final profile in builtInProfiles) {
    if (matchesProfile(profile, prefs)) return profile;
  }
  return null;
}
