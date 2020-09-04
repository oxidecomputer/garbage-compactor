// Copyright 2020 Oxide Computer Company

package gosigar

import (
	"runtime"
	"strings"

	"golang.org/x/sys/unix"
)

func (c *Cpu) Get() error {
	return ErrNotImplemented{runtime.GOOS}
}

func (l *LoadAverage) Get() error {
	return ErrNotImplemented{runtime.GOOS}
}

func (m *Mem) Get() error {
	return ErrNotImplemented{runtime.GOOS}
}

func (s *Swap) Get() error {
	return ErrNotImplemented{runtime.GOOS}
}

func (s *HugeTLBPages) Get() error {
	return ErrNotImplemented{runtime.GOOS}
}

func (f *FDUsage) Get() error {
	return ErrNotImplemented{runtime.GOOS}
}

func (p *ProcTime) Get(int) error {
	return ErrNotImplemented{runtime.GOOS}
}

func (self *CpuList) Get() error {
	return ErrNotImplemented{runtime.GOOS}
}

func (p *ProcState) Get(int) error {
	return ErrNotImplemented{runtime.GOOS}
}

func (p *ProcExe) Get(int) error {
	return ErrNotImplemented{runtime.GOOS}
}

func (p *ProcMem) Get(int) error {
	return ErrNotImplemented{runtime.GOOS}
}

func (p *ProcFDUsage) Get(int) error {
	return ErrNotImplemented{runtime.GOOS}
}

func (p *ProcEnv) Get(int) error {
	return ErrNotImplemented{runtime.GOOS}
}

func (p *ProcList) Get() error {
	return ErrNotImplemented{runtime.GOOS}
}

func (p *ProcArgs) Get(int) error {
	return ErrNotImplemented{runtime.GOOS}
}

func (self *Rusage) Get(int) error {
	return ErrNotImplemented{runtime.GOOS}
}

func (self *FileSystemList) Get() error {
	capacity := len(self.List)
	if capacity == 0 {
		capacity = 10
	}

	fslist := make([]FileSystem, 0, capacity)

	err := readFile("/etc/mnttab", func(line string) bool {
		fields := strings.Fields(line)

		fs := FileSystem{}
		fs.DevName = fields[0]
		fs.DirName = fields[1]
		fs.SysTypeName = fields[2]
		fs.Options = fields[3]

		fslist = append(fslist, fs)

		return true
	})

	if err == nil {
		self.List = fslist
	}
	return err
}

func (self *FileSystemUsage) Get(path string) error {
	var fs unix.Statvfs_t
	if err := unix.Statvfs(path, &fs); err != nil {
		return err
	}

	self.Total = uint64(fs.Blocks) * uint64(fs.Frsize)
	self.Free = uint64(fs.Bfree) * uint64(fs.Frsize)
	self.Avail = uint64(fs.Bavail) * uint64(fs.Frsize)
	self.Used = self.Total - self.Free
	self.Files = fs.Files
	self.FreeFiles = fs.Ffree

	return nil
}
