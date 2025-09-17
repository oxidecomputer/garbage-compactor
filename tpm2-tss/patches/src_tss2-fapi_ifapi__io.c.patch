$NetBSD$

--- src/tss2-fapi/ifapi_io.c.orig	2024-05-17 08:04:10.000000000 +0000
+++ src/tss2-fapi/ifapi_io.c
@@ -31,6 +31,39 @@
 #include "util/log.h"
 #include "util/aux_util.h"
 
+#ifdef __illumos__
+#define	DT_UNKNOWN	0
+#define	DT_REG		1
+#define DT_DIR		2
+
+static inline int
+dent_type(DIR *d, struct dirent *e)
+{
+    struct stat sb = { 0 };
+    int dfd = dirfd(d);
+
+    if (fstatat(dfd, e->d_name, &sb, 0) < 0)
+        return -1;
+    switch (sb.st_mode & S_IFMT) {
+    case S_IFREG:
+        return DT_REG;
+    case S_IFDIR:
+        return DT_DIR;
+    default:
+        break;
+    }
+
+    return DT_UNKNOWN;
+}    
+#else
+static inline int
+dent_type(DIR *d, struct dirent *e)
+{
+     return (e->d_type);
+}
+#endif
+
+
 /** Start reading a file's complete content into memory in an asynchronous way.
  *
  * @param[in,out] io The input/output context being used for file I/O.
@@ -409,7 +442,7 @@ ifapi_io_remove_directories(
             continue;
 
         /* If an entry is a directory then we call ourself recursively to remove those */
-        if (entry->d_type == DT_DIR) {
+        if (dent_type(dir, entry) == DT_DIR) {
             r = ifapi_asprintf(&path, "%s/%s", dirname, entry->d_name);
             goto_if_error(r, "Out of memory", error_cleanup);
 
@@ -482,6 +515,10 @@ ifapi_io_dirfiles(
     int numentries = 0;
     struct dirent **namelist;
     size_t numpaths = 0;
+#ifdef __illumos__
+    int dirfd;
+    struct stat sb;
+#endif
     check_not_null(dirname);
     check_not_null(files);
     check_not_null(numfiles);
@@ -497,11 +534,25 @@ ifapi_io_dirfiles(
     paths = calloc(numentries, sizeof(*paths));
     check_oom(paths);
 
+#ifdef __illumos__
+    if ((dirfd = open(dirname, O_RDONLY|O_DIRECTORY)) < 0) {
+        return_error2(TSS2_FAPI_RC_IO_ERROR, "Could not open directory: %s",
+                      dirname);
+    }
+#endif
+
     /* Iterating through the list of entries inside the directory. */
     for (size_t i = 0; i < (size_t) numentries; i++) {
         LOG_TRACE("Looking at %s", namelist[i]->d_name);
+#ifdef __illumos__
+        if (fstatat(dirfd, namelist[i]->d_name, &sb, 0) < 0)
+            continue;
+        if (!S_ISREG(sb.st_mode))
+            continue;
+#else
         if (namelist[i]->d_type != DT_REG)
             continue;
+#endif
 
         paths[numpaths] = strdup(namelist[i]->d_name);
         if (!paths[numpaths])
@@ -519,6 +570,10 @@ ifapi_io_dirfiles(
     }
     free(namelist);
 
+#ifdef __illumos__
+    (void) close(dirfd);
+#endif
+
     return TSS2_RC_SUCCESS;
 
 error_oom:
@@ -530,6 +585,9 @@ error_oom:
     for (size_t i = 0; i < numpaths; i++)
         free(paths[i]);
     free(paths);
+#ifdef __illumos__
+    (void) close(dirfd);
+#endif
     return TSS2_FAPI_RC_MEMORY;
 }
 
@@ -559,7 +617,7 @@ dirfiles_all(const char *dir_name, NODE_
     /* Iterating through the list of entries inside the directory. */
     while ((entry = readdir(dir)) != NULL) {
         path = NULL;
-        if (entry->d_type == DT_DIR) {
+        if (dent_type(dir, entry) == DT_DIR) {
             /* Recursive call for sub directories */
             if (strcmp(entry->d_name, ".") == 0 || strcmp(entry->d_name, "..") == 0)
                 continue;
