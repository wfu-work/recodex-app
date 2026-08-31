# Keep the Android entry point and generated Flutter plugin registration code.
# Plugin-specific consumer rules are merged into this configuration by R8.
-keep class com.xiaoxi.recodex.MainActivity { *; }
-keep class io.flutter.plugins.GeneratedPluginRegistrant { *; }

# Preserve metadata used by JSON adapters and other reflection-based libraries.
-keepattributes Signature,InnerClasses,EnclosingMethod
-keepattributes RuntimeVisibleAnnotations,RuntimeInvisibleAnnotations,AnnotationDefault
