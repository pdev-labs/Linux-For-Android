# The Termux bridge is loaded by name from app_process.
-keep class io.github.pdevlabs.lfadisplay.BridgeMain { public static void main(java.lang.String[]); }
-keep class io.github.pdevlabs.lfadisplay.BridgeBinder { *; }
-keep class io.github.pdevlabs.lfadisplay.IWaylandBridge { *; }
