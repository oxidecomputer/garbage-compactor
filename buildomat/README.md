# building a package with buildomat

This is experimental!  The `build.sh` program will copy the current local clone
(sans any `work/`, `cache/`, or `artefact/` directories) into a buildomat job
and arrange for the build of a specific package.  The resultant IPS archive
will be the sole output of the job.  The target for the build is a version of
Helios old enough that the resultant binary should run on any system currently
in use.

```
$ ./buildomat/build.sh humility
1313 blocks
-rw-r--r--   1 jclulow  staff       174K Aug  5 15:22 /tmp/tmp.9eaGaJ/input.cpio.gz
watching job 01K1Y57HFDS8RDKE0F6W95P3QN ...
polling for job output...
STATE CHANGE:  -> running
|=| job dependencies complete; ready to run (waiting for 0 s)
|=| job assigned to worker 01K1Y4VX4DRDXZX6DPS0TZB4DN [factory aws, i-0e17eba8b654e9b84] (queued for 0 s)
...
+ cd /work/humility
+ ./build.sh
...
===== RESOLVED DEPENDENCIES: =====
depend fmri=pkg:/library/libusb@1.0.25-2.0 type=require
depend fmri=pkg:/system/library/gcc-runtime@13-2.0 type=require
depend fmri=pkg:/system/library/math@0.5.11-2.0.22451 type=require
depend fmri=pkg:/system/library@0.5.11-2.0.22451 type=require
==================================
% creating repository...
% publishing...
pkg://helios-dev/developer/debug/humility@0.12.7.581,5.11-2.0:20250805T223228Z
PUBLISHED
...
+ zstd -o /out/humility-0.12.7.581.p5p.zst -k -7 /work/humility/work/humility-0.12.7.581.p5p
/work/humility/work/humility-0.12.7.581.p5p : 99.74%   (  91.6 MiB =>   91.3 MiB, /out/humility-0.12.7.581.p5p.zst)
+ find /out -type f -ls
    2    1 -rw-r--r--   1 root     root     95786462 Aug  5 22:33 /out/humility-0.12.7.581.p5p.zst
|T| process exited: duration 680450 ms, exit code 0
|W| found 1 output files
|W| uploading: /out/humility-0.12.7.581.p5p.zst (95786462 bytes)
|W| uploaded: /out/humility-0.12.7.581.p5p.zst
STATE CHANGE: running -> completed
job 01K1Y57HFDS8RDKE0F6W95P3QN complete!
PATH                                                                 SIZE
/out/humility-0.12.7.581.p5p.zst                                     91.35M
```

You can then download the package output, unpack it, and install it:

```
$ buildomat job copy 01K1Y57HFDS8RDKE0F6W95P3QN \
    /out/humility-0.12.7.581.p5p.zst /dev/stdout |
    zstd -d -o /tmp/humility-0.12.7.581.p5p

$ pkgrepo list -s /tmp/humility-0.12.7.581.p5p
PUBLISHER  NAME                       O VERSION
helios-dev developer/debug/humility     0.12.7.581-2.0:20250805T223228Z
```

You can then import this archive into a repository; e.g.,

```
pkg0 $ pfexec pkgrecv -s /tmp/humility-0.12.7.581.p5p \
    -d /data/pkg/helios/2/dev -v -m latest '*'

Processing packages for publisher helios-dev ...
Retrieving and evaluating 1 package(s)...

Retrieving packages ...
        Packages to add:        1
      Files to retrieve:        1
Estimated transfer size: 91.57 MB

Packages to transfer:
developer/debug/humility@0.12.7.581,5.11-2.0:20250805T223228Z

PROCESS                                         ITEMS    GET (MB)   SEND (MB)
Completed                                         1/1   91.6/91.6   91.6/91.6
```
