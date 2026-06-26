package main

/*
#include <stdlib.h>
#include <stdio.h>
static void greet(const char* who) { printf("hello from Go+cgo (musl): %s\n", who); }
*/
import "C"
import "unsafe"

func main() {
	s := C.CString("cgo works")
	defer C.free(unsafe.Pointer(s))
	C.greet(s)
}
