// Copyright 2017 Raphael 'kena' Poss
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or
// implied. See the License for the specific language governing
// permissions and limitations under the License.

package main

import (
	"fmt"
	"io"
	"log"
	"strings"
	"time"

	libedit "github.com/knz/go-libedit"
)

type example struct{}

func (_ example) GetCompletions(word string) []string {
	if strings.HasPrefix(word, "he") {
		return []string{"hello!"}
	}
	return nil
}

func main() {
	// Open and immediately close a libedit instance to test that nonzero editor
	// IDs are tracked correctly.
	el, err := libedit.Init("example", true)
	if err != nil {
		log.Fatal(err)
	}
	el.Close()

	el, err = libedit.Init("example", true)
	if err != nil {
		log.Fatal(err)
	}
	defer el.Close()

	// RebindControlKeys ensures that Ctrl+C, Ctrl+Z, Ctrl+R and Tab are
	// properly bound even if the user's .editrc has used bind -e or
	// bind -v to load a predefined keymap.
	el.RebindControlKeys()

	el.UseHistory(-1, true)
	el.LoadHistory("hist")
	el.SetAutoSaveHistory("hist", true)
	el.SetCompleter(example{})
	el.SetLeftPrompt("hello> ")
	el.SetRightPrompt("(-:")
	for {
		s, err := el.GetLine()
		if err != nil {
			if err == io.EOF {
				break
			}
			if err == libedit.ErrInterrupted {
				fmt.Printf("interrupted! (%q)\n", s)
				continue
			}
			log.Fatal(err)
		}
		fmt.Printf("echo %q\n", s)
		time.Sleep(2 * time.Second)
		fmt.Println("ok")
		if err := el.AddHistory(s); err != nil {
			log.Fatal(err)
		}
	}
	fmt.Println("goodbye!")
}
