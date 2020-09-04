// Copyright (c) 2012 VMware, Inc.

// +build freebsd linux illumos

package gosigar

import (
	"bufio"
	"bytes"
	"io"
	"io/ioutil"
)

func readFile(file string, handler func(string) bool) error {
	contents, err := ioutil.ReadFile(file)
	if err != nil {
		return err
	}

	reader := bufio.NewReader(bytes.NewBuffer(contents))

	for {
		line, _, err := reader.ReadLine()
		if err == io.EOF {
			break
		}
		if !handler(string(line)) {
			break
		}
	}

	return nil
}
