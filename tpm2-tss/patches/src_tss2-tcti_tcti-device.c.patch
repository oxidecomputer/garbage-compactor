$NetBSD$

--- src/tss2-tcti/tcti-device.c.orig	2024-05-21 12:44:23.000000000 +0000
+++ src/tss2-tcti/tcti-device.c
@@ -58,7 +58,7 @@
 #include "util/log.h"
 
 static char *default_conf[] = {
-#ifdef __VXWORKS__
+#if defined(__VXWORKS__) || defined(__illumos__)
     "/tpm0"
 #else
     "/dev/tpmrm0",
