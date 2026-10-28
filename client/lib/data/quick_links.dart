class QuickLink {
  const QuickLink({required this.label, required this.url, required this.lastVerified, this.subtitle});

  final String label;
  final String url;
  final String lastVerified;
  final String? subtitle;
}

const quickLinks = <QuickLink>[
  QuickLink(label: 'Tiger Spend', url: 'https://tigerspend.rit.edu/', lastVerified: '2026-10-14'),
  QuickLink(label: 'SIS', url: 'https://campus.ps.rit.edu/', lastVerified: '2026-10-14'),
  QuickLink(label: 'myCourses', url: 'https://mycourses.rit.edu/', lastVerified: '2026-10-14'),
  QuickLink(label: 'eServices', url: 'https://eservices.rit.edu/', lastVerified: '2026-10-14'),
  QuickLink(label: 'Tiger Chat', url: 'https://tigerchat.app/', lastVerified: '2026-10-14'),
  QuickLink(label: 'Service Center', url: 'https://help.rit.edu/', lastVerified: '2026-10-14'),
  QuickLink(label: 'FMS requests', url: 'https://www.rit.edu/facilitiesmanagement/request-service', lastVerified: '2026-10-14', subtitle: 'Facilities requests'),
  QuickLink(label: 'Reserve', url: 'https://reserve.rit.edu/', lastVerified: '2026-10-20', subtitle: 'Sign in with RIT'),
];
