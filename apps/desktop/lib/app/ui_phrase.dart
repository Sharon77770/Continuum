import 'package:flutter/material.dart';

import 'app_strings.dart';

/// Resolves a bundled interface phrase using the active Material locale.
String uiPhrase(BuildContext context, String phrase) =>
    AppStrings(Localizations.localeOf(context)).phrase(phrase);
