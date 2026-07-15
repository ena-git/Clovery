import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/core/platform/generated/clovery_platform.g.dart',
    dartOptions: DartOptions(),
    dartPackageName: 'clovery_mobile',
    kotlinOut:
        'android/app/src/main/kotlin/com/clovery/app/CloveryPlatform.g.kt',
    kotlinOptions: KotlinOptions(package: 'com.clovery.app'),
    swiftOut: 'ios/Runner/CloveryPlatform.g.swift',
    swiftOptions: SwiftOptions(),
  ),
)
@HostApi()
abstract class CloveryPlatform {
  String getPlatformVersion();

  void writeWidgetSnapshot(String json);
}
