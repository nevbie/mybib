# Nothing reflective in mybib itself (JSON via kotlinx JsonElement, no @Serializable classes).
# Libraries (CameraX, ML Kit, Coil/OkHttp) ship their own consumer rules.
-dontwarn org.bouncycastle.**
-dontwarn org.conscrypt.**
-dontwarn org.openjsse.**
-dontwarn com.google.errorprone.annotations.**
-dontwarn javax.annotation.**
