// PKGPATH: gno.land/r/test/guildhall
package guildhall

import (
	"testing"

	"gno.land/p/nt/testutils/v0"
	guild "gno.land/r/g1lnkytfqcjwllws63gvf0mv9yt04aswy4y9amhm/guildhall/govdao"
	"gno.land/r/g1lnkytfqcjwllws63gvf0mv9yt04aswy4y9amhm/guildhall/reputation"
	"gno.land/r/gov/dao"
	"gno.land/r/gov/dao/impl/v0"
	"gno.land/r/gov/dao/memberstore/v0"
)

const member address = "g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5"

var (
	candidate = testutils.TestAddress("candidate")
	seed      = testutils.TestAddress("seed")
	funder    = testutils.TestAddress("funder")
)

func init(cur realm) {
	memberstore.Get(0, cur).DeleteAll()
	memberstore.Get(0, cur).SetTier(memberstore.T1)
	memberstore.Get(0, cur).SetTier(memberstore.T2)
	memberstore.Get(0, cur).SetMember(memberstore.T1, member, memberstore.NewMember(3))
	dao.UpdateImpl(cross(cur), dao.NewUpdateRequest(impl.NewGovDAO(), nil))
}

func main(cur realm) {
	// The Guildhall admin makes a seed reviewer.
	testing.SetRealm(testing.NewUserRealm(reputation.Admin()))
	reputation.AddSeed(cross(cur), seed)

	// The candidate completes nine seed-reviewed milestones through the
	// bounty escrow.
	testing.SetRealm(testing.NewCodeRealm(reputation.BountiesPath))
	for i := 0; i < 9; i++ {
		reputation.AddRecord(cross(cur), candidate, funder, []address{seed}, 10000, 2_500_000, "ugnot",
			"Port the faucet — milestone", "https://github.com/gnolang/gno/pull/9000", "1/1", false)
	}

	ok, why := guild.Eligible(candidate, memberstore.T1)
	println("T1:", ok, why)
	ok, _ = guild.Eligible(candidate, memberstore.T2)
	println("T2:", ok)

	// A GovDAO member proposes the candidate with the generated portfolio.
	testing.SetRealm(testing.NewUserRealm(member))
	req := guild.NewMemberRequest(cross(cur), candidate, memberstore.T2)
	pid := dao.MustCreateProposal(cross(cur), req)
	dao.MustVoteOnProposalSimple(cross(cur), int64(pid), "YES")
	println("executed:", dao.ExecuteProposal(cross(cur), pid))

	_, tier := memberstore.Get(0, cur).GetMember(candidate)
	println("candidate tier:", tier)

	// Guildhall, not GovDAO, decides how high its bar is.
	testing.SetRealm(testing.NewUserRealm(reputation.Admin()))
	guild.SetThreshold(cross(cur), memberstore.T2, 1000)
	println("T2 threshold:", guild.Threshold(memberstore.T2))

	println(guild.Portfolio(candidate))
}

// Output:
// T1: false reputation 900 is below the T1 threshold of 2000
// T2: true
// executed: true
// candidate tier: T2
// T2 threshold: 1000
// **Guildhall reputation: 900 (Artisan)**, ranked #1
//
// - Paid work records: 9
// - Reviews given: 0
// - Earned through bounties: 22.5 GNOT
// - Full profile: https://gno.land/r/g1lnkytfqcjwllws63gvf0mv9yt04aswy4y9amhm/guildhall/reputation:u/g1vdskuerfv3shge2lta047h6lta047h6l8wvty4
//
// Most recent work:
//
// - Port the faucet — milestone (+100, record #9) · [work](https://github.com/gnolang/gno/pull/9000)
// - Port the faucet — milestone (+100, record #8) · [work](https://github.com/gnolang/gno/pull/9000)
// - Port the faucet — milestone (+100, record #7) · [work](https://github.com/gnolang/gno/pull/9000)
// - Port the faucet — milestone (+100, record #6) · [work](https://github.com/gnolang/gno/pull/9000)
// - Port the faucet — milestone (+100, record #5) · [work](https://github.com/gnolang/gno/pull/9000)
// - Port the faucet — milestone (+100, record #4) · [work](https://github.com/gnolang/gno/pull/9000)
// - Port the faucet — milestone (+100, record #3) · [work](https://github.com/gnolang/gno/pull/9000)
// - Port the faucet — milestone (+100, record #2) · [work](https://github.com/gnolang/gno/pull/9000)
// - Port the faucet — milestone (+100, record #1) · [work](https://github.com/gnolang/gno/pull/9000)
//
// _Generated from on-chain records by gno.land/r/g1lnkytfqcjwllws63gvf0mv9yt04aswy4y9amhm/guildhall/govdao._
