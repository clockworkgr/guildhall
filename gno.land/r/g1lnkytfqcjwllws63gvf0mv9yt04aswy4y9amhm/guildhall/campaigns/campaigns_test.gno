package campaigns

import (
	"chain"
	"chain/banker"
	"strconv"
	"strings"
	"testing"

	"gno.land/p/nt/testutils/v0"
	"gno.land/p/nt/uassert/v0"
	"gno.land/p/nt/urequire/v0"
	"gno.land/r/g1lnkytfqcjwllws63gvf0mv9yt04aswy4y9amhm/guildhall/reputation"
	"gno.land/r/g1lnkytfqcjwllws63gvf0mv9yt04aswy4y9amhm/guildhall/testing/gld20"
)

var (
	pkgAddr  = chain.PackageAddress(realmPath)
	poster   = testutils.TestAddress("poster")
	seedRev  = testutils.TestAddress("seed-reviewer")
	alice    = testutils.TestAddress("alice")
	bob      = testutils.TestAddress("bob")
	carol    = testutils.TestAddress("carol")
	stranger = testutils.TestAddress("stranger")
)

func ugnot(addr address) int64 {
	return banker.NewReadonlyBanker().GetCoins(addr).AmountOf("ugnot")
}

// setup lets this realm write reputation records and makes seedRev a seed.
func setup(cur realm) {
	if !reputation.IsWriter(realmPath) {
		testing.SetRealm(testing.NewUserRealm(reputation.Admin()))
		reputation.AddWriter(cross(cur), realmPath)
	}
	if !reputation.IsSeed(seedRev) {
		testing.SetRealm(testing.NewUserRealm(reputation.Admin()))
		reputation.AddSeed(cross(cur), seedRev)
	}
}

func postNative(cur realm, reward int64, slots int, reviewers string) uint64 {
	total := reward * int64(slots)
	testing.IssueCoins(pkgAddr, chain.Coins{{"ugnot", total}})
	testing.SetRealm(testing.NewUserRealm(poster))
	testing.SetOriginSend(chain.Coins{{"ugnot", total}})
	id := PostCampaign(cross(cur), "Write about Guildhall", "Post about **Guildhall** with a link to it.",
		"https://guildhall.clockwork.gr", "social, outreach", reviewers, reward, slots, 30)
	testing.SetOriginSend(nil)
	return id
}

func TestNativeCampaign(cur realm, t *testing.T) {
	setup(cur)
	id := postNative(cur, 10_000_000, 3, seedRev.String())
	uassert.Equal(t, int64(30_000_000), Escrowed("ugnot"))
	uassert.Equal(t, 1, CountByStatus("open"))
	uassert.True(t, strings.Contains(Render(""), "Write about Guildhall"))

	testing.SetRealm(testing.NewUserRealm(alice))
	n := Claim(cross(cur), id, "https://x.com/alice/status/1")
	uassert.Equal(t, 1, n)
	testing.SetRealm(testing.NewUserRealm(alice))
	uassert.AbortsWithMessage(t, cur, "campaign: you already have a pending claim (#1)", func() {
		Claim(cross(cur), id, "https://x.com/alice/status/2")
	})
	testing.SetRealm(testing.NewUserRealm(seedRev))
	uassert.AbortsWithMessage(t, cur, "campaign: the poster and reviewers cannot claim", func() {
		Claim(cross(cur), id, "https://x.com/rev/status/1")
	})
	testing.SetRealm(testing.NewUserRealm(bob))
	Claim(cross(cur), id, "https://x.com/bob/status/1")

	// Only reviewers decide; the poster isn't one here.
	testing.SetRealm(testing.NewUserRealm(poster))
	uassert.AbortsWithMessage(t, cur, "campaign: unauthorized", func() { ApproveClaim(cross(cur), id, 1) })

	before := ugnot(alice)
	testing.SetRealm(testing.NewUserRealm(seedRev))
	ApproveClaim(cross(cur), id, 1)
	uassert.Equal(t, before+10_000_000, ugnot(alice))
	uassert.Equal(t, int64(20_000_000), Escrowed("ugnot"))

	// A seed vouched at full trust; the claim is worth ClaimShareBps of Base.
	uassert.Equal(t, int64(100*ClaimShareBps/10000), reputation.Score(alice))
	recs := reputation.RecordsOf(alice, 0, 10)
	urequire.Equal(t, 1, len(recs))
	uassert.Equal(t, realmPath, recs[0].Source)
	uassert.Equal(t, "c"+strconv.FormatUint(id, 10)+"/1", recs[0].Ref)
	uassert.Equal(t, "https://x.com/alice/status/1", recs[0].Link)
	uassert.Equal(t, seedRev.String(), recs[0].Reviewers[0].String())

	testing.SetRealm(testing.NewUserRealm(seedRev))
	RejectClaim(cross(cur), id, 2, "the post is private")
	uassert.Equal(t, int64(0), reputation.Score(bob))
	uassert.True(t, strings.Contains(Render(itoa(id)), "the post is private"))

	// The poster closes early: the two free slots come back.
	posterBefore := ugnot(poster)
	testing.SetRealm(testing.NewUserRealm(stranger))
	uassert.AbortsWithMessage(t, cur, "campaign: unauthorized", func() { Close(cross(cur), id) })
	testing.SetRealm(testing.NewUserRealm(poster))
	Close(cross(cur), id)
	uassert.Equal(t, posterBefore+20_000_000, ugnot(poster))
	uassert.Equal(t, int64(0), Escrowed("ugnot"))
	uassert.Equal(t, 0, CountByStatus("open"))
	uassert.Equal(t, 1, CountByStatus("closed"))
	testing.SetRealm(testing.NewUserRealm(carol))
	uassert.AbortsWithMessage(t, cur, "campaign: closed to new claims", func() {
		Claim(cross(cur), id, "https://x.com/carol/status/1")
	})

	page := Render(itoa(id))
	uassert.True(t, strings.Contains(page, "CLOSED"))
	uassert.True(t, strings.Contains(Render("u/"+alice.String()), "#1 approved"))
}

func TestPendingClaimAfterClose(cur realm, t *testing.T) {
	setup(cur)
	id := postNative(cur, 1_000_000, 2, "")

	testing.SetRealm(testing.NewUserRealm(carol))
	Claim(cross(cur), id, "https://x.com/carol/status/9")
	testing.SetRealm(testing.NewUserRealm(poster))
	Close(cross(cur), id)
	uassert.Equal(t, int64(1_000_000), Escrowed("ugnot"), "carol's pending slot stays escrowed")

	// The poster reviews alone by default and can still pay the pending claim.
	before := ugnot(carol)
	testing.SetRealm(testing.NewUserRealm(poster))
	ApproveClaim(cross(cur), id, 1)
	uassert.Equal(t, before+1_000_000, ugnot(carol))
	uassert.Equal(t, int64(0), Escrowed("ugnot"))
}

func TestFillingEverySlotCloses(cur realm, t *testing.T) {
	setup(cur)
	id := postNative(cur, 500_000, 1, seedRev.String())
	testing.SetRealm(testing.NewUserRealm(bob))
	Claim(cross(cur), id, "https://x.com/bob/status/7")
	testing.SetRealm(testing.NewUserRealm(carol))
	uassert.AbortsWithMessage(t, cur, "campaign: every slot is taken or awaiting review", func() {
		Claim(cross(cur), id, "https://x.com/carol/status/7")
	})
	testing.SetRealm(testing.NewUserRealm(seedRev))
	ApproveClaim(cross(cur), id, 1)
	c := getCampaign(id)
	uassert.Equal(t, "closed", c.Status.String())
}

func TestPostValidation(cur realm, t *testing.T) {
	testing.SetRealm(testing.NewUserRealm(poster))
	testing.SetOriginSend(chain.Coins{{"ugnot", 5}})
	uassert.AbortsWithMessage(t, cur, "campaigns: 3 slots × 2 is 6ugnot but 5ugnot was sent", func() {
		PostCampaign(cross(cur), "x", "", "", "", "", 2, 3, 0)
	})
	uassert.AbortsWithMessage(t, cur, "campaign: slots must be within 1..1000", func() {
		PostCampaign(cross(cur), "x", "", "", "", "", 5, 0, 0)
	})
	uassert.AbortsWithMessage(t, cur, "campaigns: deadline must be 0..365 days", func() {
		PostCampaign(cross(cur), "x", "", "", "", "", 5, 1, 400)
	})
	testing.SetOriginSend(nil)

	testing.SetRealm(testing.NewUserRealm(Council()))
	SetPaused(cross(cur), true)
	testing.SetRealm(testing.NewUserRealm(poster))
	testing.SetOriginSend(chain.Coins{{"ugnot", 5}})
	uassert.AbortsWithMessage(t, cur, "campaigns: posting is paused by the council", func() {
		PostCampaign(cross(cur), "x", "", "", "", "", 5, 1, 0)
	})
	testing.SetOriginSend(nil)
	testing.SetRealm(testing.NewUserRealm(Council()))
	SetPaused(cross(cur), false)
}

func TestGRC20Campaign(cur realm, t *testing.T) {
	setup(cur)
	gld20.Ledger.Mint(poster, 10_000)
	gld20.Ledger.Approve(poster, pkgAddr, 3_000)

	testing.SetRealm(testing.NewUserRealm(poster))
	id := PostCampaignGRC20(cross(cur), gld20.Key, "Translate the docs", "", "", "docs", "", 1_000, 3, 0)
	uassert.Equal(t, int64(3_000), gld20.Token.BalanceOf(pkgAddr))
	uassert.Equal(t, int64(3_000), Escrowed(gld20.Key))
	uassert.True(t, strings.Contains(Render(itoa(id)), "0.1 GLD each"))

	testing.SetRealm(testing.NewUserRealm(alice))
	Claim(cross(cur), id, "https://example.com/fr")
	testing.SetRealm(testing.NewUserRealm(poster))
	ApproveClaim(cross(cur), id, 1)
	uassert.Equal(t, int64(1_000), gld20.Token.BalanceOf(alice))

	testing.SetRealm(testing.NewUserRealm(poster))
	Close(cross(cur), id)
	uassert.Equal(t, int64(9_000), gld20.Token.BalanceOf(poster))
	uassert.Equal(t, int64(0), Escrowed(gld20.Key))
}

func TestAPI(cur realm, t *testing.T) {
	setup(cur)
	id := postNative(cur, 2_000_000, 4, seedRev.String())
	testing.SetRealm(testing.NewUserRealm(alice))
	Claim(cross(cur), id, "https://x.com/alice/status/\"quoted\"")

	sid := itoa(id)
	stats := Render("api/stats")
	uassert.True(t, strings.Contains(stats, `"claimShareBps":500`), stats)
	uassert.True(t, strings.Contains(stats, `"realmAddress":"`+pkgAddr.String()+`"`), stats)

	list := Render("api/campaigns?status=open")
	uassert.True(t, strings.Contains(list, `"id":`+sid+`,`), list)
	uassert.True(t, strings.Contains(list, `"freeSlots":3`), list)
	uassert.True(t, strings.Contains(list, `"symbol":"GNOT","decimals":6`), list)

	one := Render("api/campaign/" + sid)
	uassert.True(t, strings.Contains(one, `"reviewers":["`+seedRev.String()+`"]`), one)
	uassert.True(t, strings.Contains(one, `"description":"Post about **Guildhall** with a link to it."`), one)

	claims := Render("api/campaign/" + sid + "/claims?status=pending")
	uassert.True(t, strings.Contains(claims, `"proof":"https://x.com/alice/status/\"quoted\""`), claims)
	uassert.True(t, strings.Contains(claims, `"reviewedBy":""`), claims)

	mine := Render("api/campaign/" + sid + "/claimant/" + alice.String())
	uassert.True(t, strings.Contains(mine, `"claim":{"number":1,`), mine)
	uassert.Equal(t, `{"claim":null}`, Render("api/campaign/"+sid+"/claimant/"+carol.String()))
	uassert.Equal(t, `{"error":"invalid address"}`, Render("api/campaign/"+sid+"/claimant/nope"))

	user := Render("api/user/" + alice.String())
	uassert.True(t, strings.Contains(user, `"roles":["claimant"]`), user)

	uassert.Equal(t, `{"error":"unknown status"}`, Render("api/campaigns?status=nope"))
	uassert.Equal(t, `{"error":"not found"}`, Render("api/campaign/999"))
	uassert.Equal(t, `{"error":"unknown endpoint"}`, Render("api/campaign/"+sid+"/nope"))
	uassert.Equal(t, `{"error":"invalid address"}`, Render("api/user/nope"))
	uassert.True(t, strings.Contains(Render("post"), "PostCampaign"))
	uassert.True(t, strings.Contains(Render("nope/x/y"), "Not found"))
}

func itoa(id uint64) string {
	return strconv.FormatUint(id, 10)
}
