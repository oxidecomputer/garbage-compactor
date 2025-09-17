$NetBSD$

Limit tpmrm0 device to Linux

--- src/tss2-tcti/tctildr-dl.c.orig	2024-03-30 06:08:30.049085491 +0000
+++ src/tss2-tcti/tctildr-dl.c
@@ -37,11 +37,13 @@ struct {
         .file = "libtss2-tcti-tabrmd.so.0",
         .description = "Access libtss2-tcti-tabrmd.so",
     },
+#ifdef __linux__
     {
         .file = "libtss2-tcti-device.so.0",
         .conf = "/dev/tpmrm0",
         .description = "Access libtss2-tcti-device.so.0 with /dev/tpmrm0",
     },
+#endif
     {
         .file = "libtss2-tcti-device.so.0",
         .conf = "/dev/tpm0",
