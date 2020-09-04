// Copyright 2020 The LevelDB-Go and Pebble Authors. All rights reserved. Use
// of this source code is governed by a BSD-style license that can be found in
// the LICENSE file.

// +build illumos

package vfs

import (
	"golang.org/x/sys/unix"
)

func (defaultFS) GetFreeSpace(path string) (uint64, error) {
	stat := unix.Statvfs_t{}
	if err := unix.Statvfs(path, &stat); err != nil {
		return 0, err
	}
	return uint64(stat.Bsize) * stat.Bfree, nil
}
