// Package gld20 is a throwaway GRC20 token used by Guildhall's tests to
// exercise token-funded bounties. It exports its ledger so tests can mint and
// approve freely; never deploy it anywhere that matters.
package gld20

import (
	"gno.land/p/nt/grc20/v0"
	"gno.land/r/nt/grc20reg/v0"
)

// Key is the token's grc20reg key.
const Key = "gno.land/r/g1lnkytfqcjwllws63gvf0mv9yt04aswy4y9amhm/guildhall/testing/gld20.GLD"

var (
	Token  *grc20.Token
	Ledger *grc20.PrivateLedger
)

func init(cur realm) {
	Token, Ledger = grc20.NewToken("Guildhall Test Token", "GLD", 4, 0, cur)
	grc20reg.Register(cross(cur), Token, "")
}
