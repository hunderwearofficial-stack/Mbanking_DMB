import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;

class DefaultFirebaseOptions {
  static FirebaseOptions? get currentPlatform {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
      return null;
    }
    return android;
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyBalSouFKjPFbYIjZvB08xmfZJzisouQQU',
    appId: '1:838418342818:android:713603eb170f47740b48fb',
    messagingSenderId: '838418342818',
    projectId: 'mbanking-dmb',
    storageBucket: 'mbanking-dmb.firebasestorage.app',
  );
}
