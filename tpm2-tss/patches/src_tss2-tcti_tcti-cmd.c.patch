$NetBSD$

Add placeholder for set_exit_with_parent on illumos.

--- src/tss2-tcti/tcti-cmd.c.orig	2024-03-17 19:29:14.865160044 +0000
+++ src/tss2-tcti/tcti-cmd.c
@@ -18,7 +18,7 @@
 
 #if defined (__FreeBSD__)
 #include <sys/procctl.h>
-#else
+#elif defined (__linux__)
 #include <sys/prctl.h>
 #endif
 #include <sys/types.h>
@@ -192,11 +192,17 @@ static int set_exit_with_parent (void)
     const int sig = SIGTERM;
     return procctl (P_PID, 0, PROC_PDEATHSIG_CTL, (void *)&sig);
 }
-#else
+#elif defined (__linux__)
 static int set_exit_with_parent (void)
 {
     return prctl (PR_SET_PDEATHSIG, SIGTERM);
 }
+#elif defined (__illumos__)
+static int set_exit_with_parent (void)
+{
+    /* TODO */
+    return 0;
+}
 #endif
 
 static void __attribute__((__noreturn__))
