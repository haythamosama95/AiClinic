import 'package:flutter/material.dart';

import 'package:ai_clinic/app/presentation/placeholder_page.dart';
import 'package:ai_clinic/app/shell/navigation/shell_route_meta.dart';

/// Clinic home workspace.
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return PlaceholderPage(title: ShellRouteMeta.titleFor('home'), description: ShellRouteMeta.descriptionFor('home'));
  }
}
