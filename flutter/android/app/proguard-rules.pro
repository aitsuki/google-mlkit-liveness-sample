# firebase-components 16.1.0 does not explicitly preserve registrar constructors.
# AGP 9 enables strict full-mode keep-rule semantics by default.
-keep class * implements com.google.firebase.components.ComponentRegistrar {
    void <init>();
}
-keep,allowshrinking interface com.google.firebase.components.ComponentRegistrar
