import 'package:flutter/material.dart';

/// Global keys for the MaterialApp — used by action sheets and snackbars
/// that need to outlive the widget context that created them.
final navigatorKey = GlobalKey<NavigatorState>();
final scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();
