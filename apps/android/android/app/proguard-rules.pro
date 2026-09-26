# mobile_scanner 自带 bundled ML Kit（无需 GMS，国行设备可用）。
# 其 ComponentDiscovery 通过反射实例化 *Registrar 的默认构造器，
# R8 full mode 会把这些构造器裁掉，导致 release 包扫码静默失效
#（2026-09-16 真机 Xiaomi Pad 实测：相机预览区黑屏报错，
#  logcat 报 NoSuchMethodException: BarcodeRegistrar.<init>）。
-keep class com.google.mlkit.** { *; }
-dontwarn com.google.mlkit.**
