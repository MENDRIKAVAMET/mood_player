# Règles R8 pour le build release (isMinifyEnabled = true).
# Si un plugin plante uniquement en release, c'est ici qu'il faut ajouter
# une règle -keep (le stack trace donnera le nom de la classe manquante).

# Flutter
-keep class io.flutter.** { *; }
-dontwarn io.flutter.embedding.**
-dontwarn com.google.android.play.core.**

# Code natif de l'app (CrashHandlerApplication, MainActivity, channels)
-keep class com.example.mood_player.** { *; }

# audio_service / just_audio (ryanheise) + Media3 / ExoPlayer
-keep class com.ryanheise.** { *; }
-dontwarn androidx.media3.**
-dontwarn com.google.android.exoplayer2.**

# flutter_local_notifications (désérialisation Gson par réflexion)
-keep class com.dexterous.** { *; }
-keepattributes *Annotation*, Signature, InnerClasses, EnclosingMethod
-keep class com.google.gson.reflect.TypeToken { *; }
-keep class * extends com.google.gson.reflect.TypeToken

# Isar
-keep class dev.isar.** { *; }
-dontwarn dev.isar.**

# on_audio_query
-keep class com.lucasjosino.** { *; }

# permission_handler, file_picker, share_plus, path_provider
-keep class com.baseflow.permissionhandler.** { *; }
-keep class com.mr.flutter.plugin.filepicker.** { *; }
-keep class dev.fluttercommunity.plus.share.** { *; }
