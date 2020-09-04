// Copyright (c) 2012 VMware, Inc.

package main

import (
	"fmt"
	"strings"

	"github.com/elastic/gosigar"
)

func main() {
	pids := gosigar.ProcList{}
	err := pids.Get()

	if err != nil {
		fmt.Printf("proclist get: %v\n", err)
	}

	// ps -eo pid,ppid,stime,time,rss,user,state,command
	fmt.Print("  PID  PPID STIME     TIME    RSS USER            S COMMAND\n")

	for _, pid := range pids.List {
		state := gosigar.ProcState{}
		mem := gosigar.ProcMem{}
		time := gosigar.ProcTime{}
		args := gosigar.ProcArgs{}

		if err := state.Get(pid); err != nil {
			fmt.Printf("state get: %v\n", err)
			continue
		}
		if err := mem.Get(pid); err != nil {
			fmt.Printf("mem get: %v\n", err)
			continue
		}
		if err := time.Get(pid); err != nil {
			fmt.Printf("time get: %v\n", err)
			continue
		}
		if err := args.Get(pid); err != nil {
			fmt.Printf("args get: %v\n", err)
			continue
		}

		fmt.Printf("%5d %5d %s %s %6d %-15s %c %s\n",
			pid, state.Ppid,
			time.FormatStartTime(), time.FormatTotal(),
			mem.Resident/1024, state.Username, state.State,
			strings.Join(args.List, " "))
	}
}
