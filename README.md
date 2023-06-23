# garbage compactor

![shut down all the garbage compactors on the detention level](shutdown.jpg)

Work in progress build scripts as we decide how much of other people's software
to use while building the product.

## testing

To test your packages, use the `-g` flag of pkg to install from the generated
p5p file:

    pfexec pkg install -g ./work/libxmlsec1-1.2.33.p5p library/libxmlsec1

Clean up when done:

    pfexec pkg uninstall library/libxmlsec1

