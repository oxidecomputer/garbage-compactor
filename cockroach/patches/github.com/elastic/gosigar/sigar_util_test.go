package gosigar

import (
	"github.com/stretchr/testify/assert"
	"testing"
)

func TestByteArrayToString(t *testing.T) {
	testIn := [16]int8{97, 112, 102, 115, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0}
	output := byteListToString(testIn[:])
	assert.Equal(t, "apfs", output)

}
