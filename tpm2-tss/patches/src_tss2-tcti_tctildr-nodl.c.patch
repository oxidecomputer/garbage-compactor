$NetBSD$

Limit tpmrm0 device to Linux

--- src/tss2-tcti/tctildr-nodl.c.orig	2024-03-30 06:09:01.060093743 +0000
+++ src/tss2-tcti/tctildr-nodl.c
@@ -80,6 +80,7 @@ struct {
     },
 #else /* _WIN32 */
 #ifdef TCTI_DEVICE
+#ifdef __linux__
     {
         .names = {
             "libtss2-tcti-device.so.0",
@@ -90,6 +91,7 @@ struct {
         .conf = "/dev/tpmrm0",
         .description = "Access to /dev/tpmrm0",
     },
+#endif
     {
         .names = {
             "libtss2-tcti-device.so.0",
