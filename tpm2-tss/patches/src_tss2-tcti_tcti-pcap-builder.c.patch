$NetBSD$

Add correct clock source for Solaris/illumos

--- src/tss2-tcti/tcti-pcap-builder.c.orig	2024-03-17 19:26:43.990977063 +0000
+++ src/tss2-tcti/tcti-pcap-builder.c
@@ -24,8 +24,10 @@
 #define LOGMODULE tcti
 #include "util/log.h"
 
-#ifdef __FreeBSD__
+#if defined (__FreeBSD__)
 #define CLOCK_MONOTONIC_RAW CLOCK_MONOTONIC
+#elif defined (__illumos__)
+#define	CLOCK_MONOTONIC_RAW CLOCK_HIGHRES
 #endif
 
 /* constants used */
