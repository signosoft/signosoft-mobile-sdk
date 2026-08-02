# The signing shell calls this across the WebView bridge by name. R8 has no way
# to see the call site, so without this the release build strips it and every
# ceremony ends in loadTimeout.
-keepclassmembers class com.signosoft.signer.SignosoftBridge {
    @android.webkit.JavascriptInterface <methods>;
}
