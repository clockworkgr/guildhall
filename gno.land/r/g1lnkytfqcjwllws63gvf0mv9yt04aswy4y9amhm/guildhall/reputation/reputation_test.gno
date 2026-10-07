package reputation

import (
	"strings"
	"testing"

	"gno.land/p/nt/testutils/v0"
	"gno.land/p/nt/uassert/v0"
	"gno.land/p/nt/urequire/v0"
)

var (
	alice  = testutils.TestAddress("alice")
	bob    = testutils.TestAddress("bob")
	carol  = testutils.TestAddress("carol")
	dave   = testutils.TestAddress("dave")
	sybil1 = testutils.TestAddress("sybil1")
	sybil2 = testutils.TestAddress("sybil2")
	funder = testutils.TestAddress("funder")
	seedA  = testutils.TestAddress("seedA")
)

// write records a full-share ugnot payment as the bounty realm would.
func write(cur realm, worker address, reviewers ...address) uint64 {
	testing.SetRealm(testing.NewCodeRealm(BountiesPath))
	return AddRecord(cross(cur), worker, funder, reviewers, 10000, 1_000_000, "ugnot", "Some work", "https://github.com/gnolang/gno/pull/1", "1/1", false)
}

func TestWriterAllowlist(cur realm, t *testing.T) {
	testing.SetRealm(testing.NewUserRealm(alice))
	uassert.AbortsWithMessage(t, cur, `reputation: "" is not an allowed writer`, func() {
		AddRecord(cross(cur), alice, funder, []address{bob}, 10000, 1, "ugnot", "", "", "", false)
	})
	testing.SetRealm(testing.NewCodeRealm("gno.land/r/evil/minter"))
	uassert.AbortsWithMessage(t, cur, `reputation: "gno.land/r/evil/minter" is not an allowed writer`, func() {
		AddRecord(cross(cur), alice, funder, []address{bob}, 10000, 1, "ugnot", "", "", "", false)
	})
	testing.SetRealm(testing.NewCodeRealm(BountiesPath))
	uassert.AbortsWithMessage(t, cur, "reputation: a record needs 1..16 reviewers", func() {
		AddRecord(cross(cur), alice, funder, nil, 10000, 1, "ugnot", "", "", "", false)
	})
	uassert.True(t, IsWriter(BountiesPath))
}

func TestTrustFlowsFromSeeds(cur realm, t *testing.T) {
	// A ring of fresh accounts vouching for each other earns nothing.
	write(cur, sybil1, sybil2)
	write(cur, sybil2, sybil1)
	uassert.Equal(t, int64(0), Score(sybil1))
	uassert.Equal(t, int64(0), Score(sybil2))
	uassert.Equal(t, 1, CompletedCount(sybil1), "the work is still on record")

	testing.SetRealm(testing.NewUserRealm(alice))
	uassert.AbortsWithMessage(t, cur, "ownable: caller is not owner", func() { AddSeed(cross(cur), alice) })

	testing.SetRealm(testing.NewUserRealm(InitialAdmin))
	AddSeed(cross(cur), seedA)
	uassert.True(t, IsSeed(seedA))

	// Work approved by a seed earns full points.
	for i := 0; i < 5; i++ {
		write(cur, alice, seedA)
	}
	uassert.Equal(t, int64(500), Score(alice))
	uassert.Equal(t, "Journeyman", Level(alice))
	uassert.True(t, HasScore(alice, 500))
	uassert.Equal(t, int64(5_000_000), Earned(alice, "ugnot"))

	// Alice has reached the trust threshold, so her approval is as good as a
	// seed's.
	write(cur, bob, alice)
	uassert.Equal(t, int64(100), Score(bob))

	// Bob is at 20% of the threshold; his approval carries 20% trust.
	write(cur, carol, bob)
	uassert.Equal(t, int64(20), Score(carol))

	// Mixed quorum averages trust: (100% + 0%) / 2.
	write(cur, dave, seedA, sybil1)
	uassert.Equal(t, int64(50), Score(dave))

	// Nobody can vouch for themselves.
	write(cur, alice, alice)
	uassert.Equal(t, int64(500), Score(alice))

	uassert.Equal(t, 1, Rank(alice))
	uassert.Equal(t, 2, Rank(bob))
	uassert.Equal(t, 0, Rank(sybil1))
	top := Top(3)
	urequire.Equal(t, 3, len(top))
	uassert.Equal(t, alice.String(), top[0].Addr.String())
	uassert.Equal(t, dave.String(), top[2].Addr.String())
	uassert.Equal(t, 6, ReviewCount(seedA), "seedA reviewed alice five times and dave once")

	uassert.NotPanics(t, cur, func() { AssertScore(alice, 500) })
	testing.SetRealm(testing.NewUserRealm(carol))
	uassert.AbortsWithMessage(t, cur, "guildhall: reputation 20 is below the required 300", func() {
		gate(cross(cur), 300)
	})
}

func TestVoidRecord(cur realm, t *testing.T) {
	id := write(cur, carol, seedA)
	before := Score(carol)

	testing.SetRealm(testing.NewUserRealm(carol))
	uassert.AbortsWithMessage(t, cur, "ownable: caller is not owner", func() { VoidRecord(cross(cur), id, "fraud") })

	testing.SetRealm(testing.NewUserRealm(InitialAdmin))
	uassert.AbortsWithMessage(t, cur, "reputation: a reason of 1..300 bytes is required", func() { VoidRecord(cross(cur), id, "") })
	VoidRecord(cross(cur), id, "work was plagiarised")
	uassert.Equal(t, before-100, Score(carol))
	rec, ok := GetRecord(id)
	urequire.True(t, ok)
	uassert.True(t, rec.Voided)
	uassert.AbortsWithMessage(t, cur, "reputation: record already voided", func() { VoidRecord(cross(cur), id, "again") })
	uassert.True(t, strings.Contains(Render("record/"+itoa(id)), "work was plagiarised"))
}

func TestGovernance(cur realm, t *testing.T) {
	testing.SetRealm(testing.NewUserRealm(InitialAdmin))
	uassert.AbortsWithMessage(t, cur, "trust: threshold must be positive", func() { SetParams(cross(cur), 100, 0, 0, 0) })
	SetParams(cross(cur), 200, 500, 0, 0)
	uassert.Equal(t, int64(200), Params().Base)
	SetParams(cross(cur), 100, 500, 0, 0)

	AddWriter(cross(cur), "gno.land/r/g1lnkytfqcjwllws63gvf0mv9yt04aswy4y9amhm/guildhall/grants")
	uassert.True(t, IsWriter("gno.land/r/g1lnkytfqcjwllws63gvf0mv9yt04aswy4y9amhm/guildhall/grants"))
	RemoveWriter(cross(cur), "gno.land/r/g1lnkytfqcjwllws63gvf0mv9yt04aswy4y9amhm/guildhall/grants")
	uassert.False(t, IsWriter("gno.land/r/g1lnkytfqcjwllws63gvf0mv9yt04aswy4y9amhm/guildhall/grants"))

	RemoveSeed(cross(cur), seedA)
	uassert.False(t, IsSeed(seedA))
	uassert.AbortsWithMessage(t, cur, "reputation: not a seed", func() { RemoveSeed(cross(cur), seedA) })
	AddSeed(cross(cur), seedA)

	TransferAdmin(cross(cur), alice)
	uassert.Equal(t, alice.String(), Admin().String())
	testing.SetRealm(testing.NewUserRealm(alice))
	TransferAdmin(cross(cur), address(testutils.TestAddress("govdao-placeholder")))
}

func TestRender(cur realm, t *testing.T) {
	home := Render("")
	uassert.True(t, strings.Contains(home, "Leaderboard"))
	uassert.True(t, strings.Contains(home, "reputation.AssertScore"))

	profile := Render("u/" + alice.String())
	uassert.True(t, strings.Contains(profile, "Journeyman"))
	uassert.True(t, strings.Contains(profile, "6 GNOT"), "five seed-approved payments plus one self-reviewed")

	uassert.True(t, strings.Contains(Render("u/"+testutils.TestAddress("ghost").String()), "No recorded work"))
	uassert.True(t, strings.Contains(Render("record/1"), "Vouched for by"))
	uassert.True(t, strings.Contains(Render("records"), "All records"))
	uassert.True(t, strings.Contains(Render("seeds"), "Seed reviewers"))
	uassert.True(t, strings.Contains(Render("about"), "gno.land/r/g1lnkytfqcjwllws63gvf0mv9yt04aswy4y9amhm/guildhall/bounties"))
	uassert.True(t, strings.Contains(Render("record/abc"), "Not found"))
	uassert.True(t, strings.Contains(Render("nope"), "Not found"))
}

// gate stands in for a consumer realm entry point that requires reputation.
func gate(cur realm, min int64) {
	AssertScore(cur.Previous().Address(), min)
}

func itoa(id uint64) string {
	return strings.TrimLeft(idKey(id), "0")
}

func TestAPI(cur realm, t *testing.T) {
	uassert.True(t, strings.HasPrefix(Render("api/stats"), `{"records":`))
	top := Render("api/top?limit=1")
	uassert.True(t, strings.Contains(top, `"rank":1,"address":"`+alice.String()+`"`))
	uassert.True(t, strings.Contains(Render("api/profile/"+alice.String()), `"level":"Journeyman","rank":1`))
	uassert.True(t, strings.Contains(Render("api/profile/"+testutils.TestAddress("ghost").String()), `"score":0`))
	uassert.True(t, strings.Contains(Render("api/records?addr="+seedA.String()+"&kind=reviews&limit=1"), `"more":true`))
	uassert.True(t, strings.Contains(Render("api/record/1"), `"id":1,"worker":`))
	uassert.True(t, strings.Contains(Render("api/seeds"), seedA.String()))
	uassert.True(t, strings.Contains(Render("api/record/x"), `"error"`))
}
