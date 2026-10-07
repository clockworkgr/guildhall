package trust

import (
	"testing"

	"gno.land/p/nt/testutils/v0"
	"gno.land/p/nt/uassert/v0"
	"gno.land/p/nt/urequire/v0"
)

var (
	worker = testutils.TestAddress("worker")
	poster = testutils.TestAddress("poster")
	seed   = testutils.TestAddress("seed")
	peer   = testutils.TestAddress("peer")
	nobody = testutils.TestAddress("nobody")
)

func TestTrustOf(t *testing.T) {
	p := DefaultParams()
	cases := []struct {
		name string
		r    Reviewer
		want int64
	}{
		{"seed", Reviewer{Addr: seed, Seed: true}, MaxBps},
		{"stranger", Reviewer{Addr: nobody}, 0},
		{"half threshold", Reviewer{Addr: peer, Score: 250}, 5000},
		{"at threshold", Reviewer{Addr: peer, Score: 500}, MaxBps},
		{"above threshold", Reviewer{Addr: peer, Score: 9000}, MaxBps},
		{"worker reviewing self", Reviewer{Addr: worker, Score: 9000, Seed: true}, 0},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			uassert.Equal(t, tc.want, TrustOf(tc.r, worker, p))
		})
	}

	p.TrustFloorBps = 1000
	uassert.Equal(t, int64(1000), TrustOf(Reviewer{Addr: nobody}, worker, p))
	uassert.Equal(t, int64(0), TrustOf(Reviewer{Addr: worker}, worker, p), "floor never applies to self-review")
}

func TestEvaluate(t *testing.T) {
	p := DefaultParams()
	full := int64(MaxBps)
	cases := []struct {
		name string
		in   Input
		want int64
	}{
		{
			"single seed reviewer",
			Input{Worker: worker, Poster: poster, Reviewers: []Reviewer{{Addr: seed, Seed: true}}, ShareBps: full},
			100,
		},
		{
			"seed and stranger average out",
			Input{Worker: worker, Poster: poster, Reviewers: []Reviewer{{Addr: seed, Seed: true}, {Addr: nobody}}, ShareBps: full},
			50,
		},
		{
			"partially trusted peer",
			Input{Worker: worker, Poster: poster, Reviewers: []Reviewer{{Addr: peer, Score: 125}}, ShareBps: full},
			25,
		},
		{
			"strangers only earn nothing",
			Input{Worker: worker, Poster: poster, Reviewers: []Reviewer{{Addr: nobody}}, ShareBps: full},
			0,
		},
		{
			"split dispute scales points",
			Input{Worker: worker, Poster: poster, Reviewers: []Reviewer{{Addr: seed, Seed: true}}, ShareBps: 6000},
			60,
		},
		{
			"self-funded work earns nothing",
			Input{Worker: worker, Poster: worker, Reviewers: []Reviewer{{Addr: seed, Seed: true}}, ShareBps: full},
			0,
		},
		{
			"duplicate reviewer counts once",
			Input{Worker: worker, Poster: poster, Reviewers: []Reviewer{{Addr: seed, Seed: true}, {Addr: seed, Seed: true}, {Addr: nobody}}, ShareBps: full},
			50,
		},
		{
			"no reviewers",
			Input{Worker: worker, Poster: poster, ShareBps: full},
			0,
		},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			res, err := Evaluate(tc.in, p)
			urequire.NoError(t, err)
			uassert.Equal(t, tc.want, res.Points)
			uassert.Equal(t, len(tc.in.Reviewers), len(res.TrustBps))
		})
	}
}

func TestEvaluateRejectsBadInput(t *testing.T) {
	_, err := Evaluate(Input{Worker: worker, ShareBps: MaxBps + 1}, DefaultParams())
	uassert.ErrorContains(t, err, "share")

	bad := DefaultParams()
	bad.Base = 0
	_, err = Evaluate(Input{Worker: worker, ShareBps: MaxBps}, bad)
	uassert.ErrorContains(t, err, "base")
}

func TestParamsValidate(t *testing.T) {
	p := DefaultParams()
	urequire.NoError(t, p.Validate())

	p.TrustThreshold = 0
	uassert.ErrorContains(t, p.Validate(), "threshold")

	p = DefaultParams()
	p.TrustFloorBps = MaxBps + 1
	uassert.ErrorContains(t, p.Validate(), "floor")

	p = DefaultParams()
	p.SelfFundedFactorBps = -1
	uassert.ErrorContains(t, p.Validate(), "self-funded")
}

func TestLevel(t *testing.T) {
	uassert.Equal(t, "Newcomer", Level(0))
	uassert.Equal(t, "Apprentice", Level(1))
	uassert.Equal(t, "Journeyman", Level(300))
	uassert.Equal(t, "Artisan", Level(800))
	uassert.Equal(t, "Master", Level(2000))
	uassert.Equal(t, "Grandmaster", Level(5000))
}
