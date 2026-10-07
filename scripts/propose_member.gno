// Propose a Guildhall contributor for GovDAO membership, with a portfolio
// generated from their on-chain work records.
//
// Edit candidate and tier, then run from a GovDAO member's key:
//
//	gnokey maketx run -gas-fee 1000000ugnot -gas-wanted 100000000 \
//	  -broadcast -chainid gnoland1 -remote https://rpc.gno.land:443 \
//	  MEMBER_KEY scripts/propose_member.gno
package main

import (
	"gno.land/r/gov/dao"
	guild "gno.land/r/g1lnkytfqcjwllws63gvf0mv9yt04aswy4y9amhm/guildhall/govdao"
)

const (
	candidate address = "g1..." // the contributor to propose
	tier              = "T2"
)

func main(cur realm) {
	req := guild.NewMemberRequest(cross(cur), candidate, tier)
	pid := dao.MustCreateProposal(cross(cur), req)
	println("created proposal", pid.String())
}
