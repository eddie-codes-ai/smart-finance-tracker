package com.smartfinance.smart_finance_tracker

import io.flutter.embedding.android.FlutterFragmentActivity

// FlutterFragmentActivity, not FlutterActivity: local_auth shows the system
// biometric prompt through a Fragment, and throws "no_fragment_activity" at
// runtime on a plain FlutterActivity. Nothing else depends on the base class.
class MainActivity : FlutterFragmentActivity()
