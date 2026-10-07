package bounties

import (
	"chain"
	"chain/banker"
	"strings"
	"testing"

	"gno.land/p/nt/testutils/v0"
	"gno.land/p/nt/uassert/v0"
	"gno.land/p/nt/urequire/v0"
	"gno.land/r/g1lnkytfqcjwllws63gvf0mv9yt04aswy4y9amhm/guildhall/reputation"
	"gno.land/r/g1lnkytfqcjwllws63gvf0mv9yt04aswy4y9amhm/guildhall/testing/gld20"
)

var (
	pkgAddr  = chain.PackageAddress("gno.land/r/g1lnkytfqcjwllws63gvf0mv9yt04aswy4y9amhm/guildhall/bounties")
	poster   = testutils.TestAddress("poster")
	worker   = testutils.TestAddress("worker")
	worker2  = testutils.TestAddress("worker2")
	seedRev  = testutils.TestAddress("seed-reviewer")
	peerRev  = testutils.TestAddress("peer-reviewer")
	arbiter  = testutils.TestAddress("arbiter")
	stranger = testutils.TestAddress("stranger")
)

const tst20 = gld20.Key

func ugnot(addr address) int64 {
	return banker.NewReadonlyBanker().GetCoins(addr).AmountOf("ugnot")
}

func seed(cur realm, addr address) {
	if reputation.IsSeed(addr) {
		return
	}
	testing.SetRealm(testing.NewUserRealm(reputation.Admin()))
	reputation.AddSeed(cross(cur), addr)
}

func postNative(cur realm, amount int64, reviewers string, quorum int, milestones, arb string) uint64 {
	testing.IssueCoins(pkgAddr, chain.Coins{{"ugnot", amount}})
	testing.SetRealm(testing.NewUserRealm(poster))
	testing.SetOriginSend(chain.Coins{{"ugnot", amount}})
	id := PostBounty(cross(cur), "Port the faucet", "Rewrite **r/faucet** for interrealm v2.",
		"https://github.com/gnolang/gno/issues/1", "realm, faucet", reviewers, quorum, milestones, arb, 0)
	testing.SetOriginSend(nil)
	return id
}

func TestNativeLifecycle(cur realm, t *testing.T) {
	seed(cur, seedRev)
	reviewers := seedRev.String() + "," + peerRev.String()
	id := postNative(cur, 5_000_000, reviewers, 2, "Design=1000000;Build=4000000", "")

	b := getBounty(id)
	urequire.True(t, b != nil)
	uassert.Equal(t, int64(5_000_000), b.Total())
	uassert.Equal(t, int64(5_000_000), Escrowed("ugnot"))
	uassert.Equal(t, 1, CountByStatus("open"))
	uassert.True(t, strings.Contains(Render(""), "Port the faucet"))

	testing.SetRealm(testing.NewUserRealm(worker))
	Apply(cross(cur), id, "I wrote the first faucet")
	uassert.True(t, strings.Contains(Render(itoa(id)), "I wrote the first faucet"))

	testing.SetRealm(testing.NewUserRealm(stranger))
	uassert.AbortsWithMessage(t, cur, "bounty: unauthorized", func() { Assign(cross(cur), id, stranger) })

	testing.SetRealm(testing.NewUserRealm(poster))
	Assign(cross(cur), id, worker)
	uassert.Equal(t, 1, CountByStatus("active"))

	testing.SetRealm(testing.NewUserRealm(worker))
	Submit(cross(cur), id, 1, "https://github.com/gnolang/gno/pull/100")

	testing.SetRealm(testing.NewUserRealm(worker))
	uassert.AbortsWithMessage(t, cur, "bounty: unauthorized", func() { Approve(cross(cur), id, 1) })

	before := ugnot(worker)
	testing.SetRealm(testing.NewUserRealm(seedRev))
	Approve(cross(cur), id, 1)
	uassert.Equal(t, before, ugnot(worker), "one approval is below quorum")

	testing.SetRealm(testing.NewUserRealm(peerRev))
	Approve(cross(cur), id, 1)
	uassert.Equal(t, before+1_000_000, ugnot(worker))
	uassert.Equal(t, int64(4_000_000), Escrowed("ugnot"))

	// Seed at full trust, peer at zero: the record is worth half of Base.
	uassert.Equal(t, int64(50), reputation.Score(worker))
	uassert.Equal(t, 1, reputation.CompletedCount(worker))
	uassert.Equal(t, 1, reputation.ReviewCount(seedRev))
	uassert.Equal(t, int64(1_000_000), reputation.Earned(worker, "ugnot"))

	testing.SetRealm(testing.NewUserRealm(worker))
	Submit(cross(cur), id, 2, "https://github.com/gnolang/gno/pull/101")
	testing.SetRealm(testing.NewUserRealm(seedRev))
	RequestChanges(cross(cur), id, 2, "needs tests")
	uassert.True(t, strings.Contains(Render(itoa(id)), "needs tests"))
	testing.SetRealm(testing.NewUserRealm(worker))
	Submit(cross(cur), id, 2, "https://github.com/gnolang/gno/pull/102")
	testing.SetRealm(testing.NewUserRealm(seedRev))
	Approve(cross(cur), id, 2)
	testing.SetRealm(testing.NewUserRealm(peerRev))
	Approve(cross(cur), id, 2)

	uassert.Equal(t, before+5_000_000, ugnot(worker))
	uassert.Equal(t, int64(0), Escrowed("ugnot"))
	uassert.Equal(t, 1, CountByStatus("completed"))
	uassert.Equal(t, 0, CountByStatus("active"))
	uassert.Equal(t, int64(100), reputation.Score(worker))

	page := Render(itoa(id))
	uassert.True(t, strings.Contains(page, "COMPLETED"))
	uassert.True(t, strings.Contains(page, "pull/102"))
	uassert.True(t, strings.Contains(Render("u/"+worker.String()), "assignee"))
}

func TestDisputeGoesToCouncil(cur realm, t *testing.T) {
	id := postNative(cur, 2_000_000, "", 0, "", "")
	b := getBounty(id)
	uassert.Equal(t, poster.String(), b.Reviewers[0].String(), "poster reviews alone by default")
	uassert.Equal(t, Council().String(), b.Arbiter.String())

	testing.SetRealm(testing.NewUserRealm(poster))
	Assign(cross(cur), id, worker2)
	testing.SetRealm(testing.NewUserRealm(worker2))
	Submit(cross(cur), id, 1, "https://github.com/gnolang/gno/pull/200")
	testing.SetRealm(testing.NewUserRealm(poster))
	RequestChanges(cross(cur), id, 1, "not what I asked for")
	testing.SetRealm(testing.NewUserRealm(worker2))
	OpenDispute(cross(cur), id, 1, "the issue said exactly this")

	testing.SetRealm(testing.NewUserRealm(poster))
	uassert.AbortsWithMessage(t, cur, "bounty: unauthorized", func() { Resolve(cross(cur), id, 1, 5000, "") })
	testing.SetRealm(testing.NewUserRealm(worker2))
	uassert.AbortsWithMessage(t, cur, "bounty: a milestone is awaiting review or arbitration", func() { Unassign(cross(cur), id) })

	posterBefore, workerBefore := ugnot(poster), ugnot(worker2)
	testing.SetRealm(testing.NewUserRealm(Council()))
	Resolve(cross(cur), id, 1, 7500, "mostly delivered")
	uassert.Equal(t, workerBefore+1_500_000, ugnot(worker2))
	uassert.Equal(t, posterBefore+500_000, ugnot(poster))
	uassert.Equal(t, "completed", b.Status.String())

	// The council is not a seed, so arbitrated work records but earns nothing
	// until the admin makes the council a seed.
	uassert.Equal(t, 1, reputation.CompletedCount(worker2))
	rec, ok := reputation.GetRecord(uint64(reputation.RecordCount()))
	urequire.True(t, ok)
	uassert.True(t, rec.Arbitrated)
	uassert.Equal(t, int64(7500), rec.ShareBps)
	uassert.True(t, strings.Contains(Render(itoa(id)), "mostly delivered"))
}

func TestExplicitArbiterAndCancel(cur realm, t *testing.T) {
	id := postNative(cur, 3_000_000, peerRev.String(), 1, "A=1000000;B=2000000", arbiter.String())
	uassert.Equal(t, arbiter.String(), getBounty(id).Arbiter.String())

	testing.SetRealm(testing.NewUserRealm(poster))
	uassert.AbortsWithMessage(t, cur, "bounty: posters, reviewers and the arbiter cannot be assigned",
		func() { Assign(cross(cur), id, arbiter) })
	Assign(cross(cur), id, worker)
	uassert.AbortsWithMessage(t, cur, "bounty: invalid state for this action", func() { Cancel(cross(cur), id) })

	testing.SetRealm(testing.NewUserRealm(worker))
	Submit(cross(cur), id, 1, "https://example.com/a")
	testing.SetRealm(testing.NewUserRealm(peerRev))
	Approve(cross(cur), id, 1)
	testing.SetRealm(testing.NewUserRealm(worker))
	Unassign(cross(cur), id)

	posterBefore := ugnot(poster)
	testing.SetRealm(testing.NewUserRealm(poster))
	Cancel(cross(cur), id)
	uassert.Equal(t, posterBefore+2_000_000, ugnot(poster))
	uassert.Equal(t, "cancelled", getBounty(id).Status.String())
}

func TestPostValidation(cur realm, t *testing.T) {
	testing.IssueCoins(pkgAddr, chain.Coins{{"ugnot", 1_000}})
	testing.SetRealm(testing.NewUserRealm(poster))
	testing.SetOriginSend(chain.Coins{{"ugnot", 1_000}})
	uassert.AbortsWithMessage(t, cur, "bounties: milestones add up to 900 but 1000ugnot was sent", func() {
		PostBounty(cross(cur), "t", "", "", "", "", 0, "a=900", "", 0)
	})
	uassert.AbortsWithMessage(t, cur, "bounties: work window must be 0..365 days", func() {
		PostBounty(cross(cur), "t", "", "", "", "", 0, "", "", 400)
	})
	testing.SetOriginSend(nil)
	uassert.AbortsWithMessage(t, cur, "bounties: send exactly one coin denomination to fund the bounty", func() {
		PostBounty(cross(cur), "t", "", "", "", "", 0, "", "", 0)
	})

	testing.SetRealm(testing.NewUserRealm(stranger))
	uassert.AbortsWithMessage(t, cur, "ownable: caller is not owner", func() { SetPaused(cross(cur), true) })
	testing.SetRealm(testing.NewUserRealm(Council()))
	SetPaused(cross(cur), true)
	testing.SetRealm(testing.NewUserRealm(poster))
	testing.SetOriginSend(chain.Coins{{"ugnot", 1_000}})
	uassert.AbortsWithMessage(t, cur, "bounties: posting is paused by the council", func() {
		PostBounty(cross(cur), "t", "", "", "", "", 0, "", "", 0)
	})
	testing.SetRealm(testing.NewUserRealm(Council()))
	SetPaused(cross(cur), false)
}

func TestGRC20Bounty(cur realm, t *testing.T) {
	gld20.Ledger.Mint(poster, 10_000)
	gld20.Ledger.Approve(poster, pkgAddr, 6_000)

	testing.SetRealm(testing.NewUserRealm(poster))
	id := PostBountyGRC20(cross(cur), tst20, "Write docs", "", "", "docs", "", 0, "Draft=2000;Final=4000", "", 0)
	uassert.Equal(t, int64(4_000), gld20.Token.BalanceOf(poster))
	uassert.Equal(t, int64(6_000), gld20.Token.BalanceOf(pkgAddr))
	uassert.Equal(t, int64(6_000), Escrowed(tst20))
	uassert.True(t, strings.Contains(Render(itoa(id)), "0.6 GLD"))

	testing.SetRealm(testing.NewUserRealm(poster))
	uassert.AbortsWithMessage(t, cur, "insufficient allowance", func() {
		PostBountyGRC20(cross(cur), tst20, "Again", "", "", "", "", 0, "x=1", "", 0)
	})
	uassert.AbortsWithMessage(t, cur, "bounties: unknown token \"nope\"", func() {
		PostBountyGRC20(cross(cur), "nope", "Again", "", "", "", "", 0, "x=1", "", 0)
	})

	Assign(cross(cur), id, worker)
	testing.SetRealm(testing.NewUserRealm(worker))
	Submit(cross(cur), id, 1, "https://example.com/draft")
	testing.SetRealm(testing.NewUserRealm(poster))
	Approve(cross(cur), id, 1)
	uassert.Equal(t, int64(2_000), gld20.Token.BalanceOf(worker))

	testing.SetRealm(testing.NewUserRealm(worker))
	Unassign(cross(cur), id)
	testing.SetRealm(testing.NewUserRealm(poster))
	Cancel(cross(cur), id)
	uassert.Equal(t, int64(8_000), gld20.Token.BalanceOf(poster))
	uassert.Equal(t, int64(0), Escrowed(tst20))
}

func TestRenderRoutes(cur realm, t *testing.T) {
	uassert.True(t, strings.Contains(Render("post"), "PostBounty"))
	uassert.True(t, strings.Contains(Render("?status=all"), "Port the faucet"))
	uassert.True(t, strings.Contains(Render("?status=all&tag=docs"), "Write docs"))
	uassert.False(t, strings.Contains(Render("?status=all&tag=docs"), "Port the faucet"))
	uassert.True(t, strings.Contains(Render("999"), "Not found"))
	uassert.True(t, strings.Contains(Render("u/nope"), "Not found"))
	uassert.True(t, strings.Contains(Render("u/"+stranger.String()), "Not involved"))
}

func itoa(id uint64) string {
	return strings.TrimLeft(idKey(id), "0")
}

func TestAPI(cur realm, t *testing.T) {
	stats := Render("api/stats")
	uassert.True(t, strings.HasPrefix(stats, `{"total":`))
	uassert.True(t, strings.Contains(stats, `"symbol":"GNOT","decimals":6`) || strings.Contains(stats, `"escrow":[]`))

	list := Render("api/bounties?status=all&limit=2")
	uassert.True(t, strings.Contains(list, `"more":true`), "more than two bounties exist")
	uassert.True(t, strings.Contains(Render("api/bounties?tag=docs"), `"title":"Write docs"`))
	uassert.True(t, strings.Contains(Render("api/bounties?status=nope"), `"error":"unknown status"`))

	one := Render("api/bounty/1")
	uassert.True(t, strings.Contains(one, `"id":1,"title":"Port the faucet"`))
	uassert.True(t, strings.Contains(one, `"description":"Rewrite **r/faucet** for interrealm v2."`))
	uassert.True(t, strings.Contains(one, `"submission":"https://github.com/gnolang/gno/pull/102"`))
	uassert.True(t, strings.Contains(Render("api/bounty/999"), `"error":"not found"`))

	uassert.True(t, strings.Contains(Render("api/user/"+worker.String()), `"roles":["assignee"]`))
	uassert.True(t, strings.Contains(Render("api/tokens"), `"symbol":"GLD","decimals":4`))
	uassert.True(t, strings.Contains(Render("api/nope"), `"error":"unknown endpoint"`))
}
