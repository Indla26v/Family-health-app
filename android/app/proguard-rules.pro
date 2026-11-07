# ML Kit text recognition: only the Latin model is bundled. The plugin also
# references the Chinese/Devanagari/Japanese/Korean models, which aren't shipped.
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**

# ML Kit finds its parts by class name at runtime (component registrars, the
# bundled model's native bridge). If R8 renames or strips them, recognising text
# crashes with "getClass() on a null object reference" in release builds only.
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_** { *; }
-keep class com.google_mlkit_commons.** { *; }
-keep class com.google_mlkit_text_recognition.** { *; }
-keep class * implements com.google.firebase.components.ComponentRegistrar { *; }
-keepclassmembers class * {
    native <methods>;
}
