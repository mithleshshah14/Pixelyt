import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

/// Bridge to the native Android side that lets this app act as an image
/// source for other apps (via ACTION_GET_CONTENT / ACTION_PICK).
class PickerChannel {
  static const MethodChannel _channel = MethodChannel('removetrack/picker');

  static final StreamController<String?> _actionController =
      StreamController<String?>.broadcast();
  static bool _handlerInstalled = false;

  /// Fires whenever this already-running app receives a new picker intent
  /// (e.g. another app asks the system chooser to pick a photo while
  /// Pixelyt is warm in the background). Android delivers that as
  /// onNewIntent rather than a fresh launch, so a one-time startup check
  /// alone would miss it.
  static Stream<String?> get onLaunchAction => _actionController.stream;

  static void _ensureHandler() {
    if (_handlerInstalled || !Platform.isAndroid) return;
    _handlerInstalled = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onNewIntent') {
        _actionController.add(call.arguments as String?);
      }
    });
  }

  /// Returns the intent action this app was launched with (Android only),
  /// or null on other platforms / a normal launcher start.
  static Future<String?> getLaunchAction() async {
    if (!Platform.isAndroid) return null;
    _ensureHandler();
    try {
      return await _channel.invokeMethod<String>('getLaunchAction');
    } on PlatformException {
      return null;
    }
  }

  /// Hands the cleaned image at [path] back to whichever app asked this one
  /// to pick a photo, then finishes this activity.
  static Future<void> returnPickedImage(String path) async {
    await _channel.invokeMethod('returnPickedImage', {'path': path});
  }

  /// Cancels the pick request and finishes this activity.
  static Future<void> cancelPicker() async {
    await _channel.invokeMethod('cancelPicker');
  }

  static const String actionGetContent = 'android.intent.action.GET_CONTENT';
  static const String actionPick = 'android.intent.action.PICK';
}
