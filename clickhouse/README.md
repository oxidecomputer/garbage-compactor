# clickhouse

Patches and notes for building ClickHouse on illumos.

## Building

```bash
$ ./build.sh
```

## Patches

Most patches have been upstreamed into their various homes. The remaining are
mostly related to some C++ standard library wierdness. The files in
`patches/direct` are applied to the source (after cloning submodules), and
those in `patches/cmake` are applied after running `cmake` as they apply to
some of the generated build files.

## Upstreaming

In general, ClickHouse was very responsive to PRs, so additional work to
upstream things should be straightforward. The only bit to record is how to
handle updates to any of the repos cloned as submodules.

After things have been upstreamed, say to `contrib/project-a`, run

```bash
$ git submodule update --checkout --remote contrib/project-a
```

This records the latest commit of the remote submodule into the superproject.
Once all submodules have been updated like this, make a commit and put up
a PR against ClickHouse as usual.

## Errors

If you see errors complaining about a submodule not having a particular
commit or branch, you may need to specify the `branch` in the `.gitmodules`
file. It should be whatever the remote uses as the default branch. Git
defaults to using `master`, but many remotes don't use that name, hence
the errors.
