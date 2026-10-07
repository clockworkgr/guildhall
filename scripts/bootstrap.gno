// Bootstrap Guildhall after deployment.
//
//  1. Seed the first trusted reviewers.
//  2. Optionally hand the reputation admin role to a multisig.
//  3. Optionally hand the bounty council seat to an arbitration committee.
//
// Leave an address empty to keep that role with the deployer. Fill in the
// values, then run from the deployer's key (g1lnkytfqcjwllws63gvf0mv9yt04aswy4y9amhm):
//
//	gnokey maketx run -gas-fee 1000000ugnot -gas-wanted 50000000 \
//	  -broadcast -chainid gnoland1 -remote https://rpc.gno.land:443 \
//	  DEPLOYER_KEY scripts/bootstrap.gno
package main

import (
	"gno.land/r/g1lnkytfqcjwllws63gvf0mv9yt04aswy4y9amhm/guildhall/bounties"
	"gno.land/r/g1lnkytfqcjwllws63gvf0mv9yt04aswy4y9amhm/guildhall/reputation"
)

var initialSeeds = []address{
	// "g1...",
}

const (
	adminMultisig        address = "" // new reputation admin; empty keeps the deployer
	arbitrationCommittee address = "" // new bounty council; empty keeps the deployer
)

func main(cur realm) {
	for _, s := range initialSeeds {
		reputation.AddSeed(cross(cur), s)
	}
	if arbitrationCommittee != "" {
		bounties.TransferCouncil(cross(cur), arbitrationCommittee)
	}
	if adminMultisig != "" {
		reputation.TransferAdmin(cross(cur), adminMultisig)
	}
	println("seeds added:", len(initialSeeds))
	println("reputation admin:", reputation.Admin().String())
	println("bounties council:", bounties.Council().String())
}
