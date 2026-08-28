/// Campus tab: the mailing address lookup on its own, with room to breathe.
library;

import 'package:flutter/material.dart';

import '../cards/housing_card.dart';
import '../models/api_models.dart';
import '../services/api.dart';

class CampusScreen extends StatelessWidget {
  const CampusScreen({super.key, required this.api, required this.areas});

  final ApiClient api;
  final Result<Collection<HousingArea>> areas;

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.fromLTRB(14, 4, 14, 20),
        children: [HousingCard(areas: areas, api: api)],
      );
}
