# garbage compactor

![shut down all the garbage compactors on the detention level](shutdown.jpg)

Work in progress build scripts as we decide how much of other people's software
to use while building the product.

## Important Details About Version Numbers

When making a change to a package that does not change the version number, you
**MUST** bump the branch version of the package.  By default, the branch
version of any package is generally **2.0**.  If you make a change that
introduces a new patch or rearranges a package, but does not change the
upstream version that is packaged, you would bump it to **2.1** as part of your
change.

By way of example, look at commit `320bcf7f97ba8c1782066634e5b83502adce82aa`
which introduces new patches to libusb and bumps the branch version from
**2.0** to **2.1** accordingly.

## Licence

Copyright 2024 Oxide Computer Company

Unless otherwise noted, all components are licenced under the [Mozilla Public
License Version 2.0](./LICENSE).
