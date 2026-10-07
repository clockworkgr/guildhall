// PKGPATH: gno.land/r/test/home
package home

import "gno.land/r/g1lnkytfqcjwllws63gvf0mv9yt04aswy4y9amhm/guildhall"

func main() {
	out := guildhall.Render("")
	println(len(out) > 0)
}

// Output:
// true
