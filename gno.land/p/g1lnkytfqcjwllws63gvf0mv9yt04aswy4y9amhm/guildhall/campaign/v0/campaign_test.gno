package campaign

import (
	"strings"
	"testing"
	"time"

	"gno.land/p/nt/testutils/v0"
	"gno.land/p/nt/uassert/v0"
	"gno.land/p/nt/urequire/v0"
)

var (
	poster   = testutils.TestAddress("poster")
	reviewer = testutils.TestAddress("reviewer")
	alice    = testutils.TestAddress("alice")
	bob      = testutils.TestAddress("bob")
	carol    = testutils.TestAddress("carol")
	t0       = time.Date(2026, 10, 1, 12, 0, 0, 0, time.UTC)
)

func newCampaign(t *testing.T, slots int, deadline time.Time) *Campaign {
	c, err := New(Params{
		ID:        1,
		Poster:    poster,
		Title:     "Post about Guildhall",
		Link:      "https://guildhall.clockwork.gr",
		Tags:      []string{"Social", "social", " outreach "},
		Denom:     "ugnot",
		Reward:    10_000_000,
		Slots:     slots,
		Reviewers: []address{reviewer},
		Deadline:  deadline,
		Now:       t0,
	})
	urequire.NoError(t, err)
	return c
}

func TestNewValidation(t *testing.T) {
	c := newCampaign(t, 3, time.Time{})
	uassert.Equal(t, "social,outreach", strings.Join(c.Tags, ","))
	uassert.Equal(t, int64(30_000_000), c.Total())
	uassert.Equal(t, int64(30_000_000), c.Escrowed())
	uassert.Equal(t, 3, c.FreeSlots())

	base := Params{Poster: poster, Title: "x", Denom: "ugnot", Reward: 1, Slots: 1, Now: t0}
	cases := []struct {
		name string
		edit func(p *Params)
		want string
	}{
		{"no title", func(p *Params) { p.Title = " " }, "title must be"},
		{"no reward", func(p *Params) { p.Reward = 0 }, "reward must be positive"},
		{"no slots", func(p *Params) { p.Slots = 0 }, "slots must be within"},
		{"too many slots", func(p *Params) { p.Slots = MaxSlots + 1 }, "slots must be within"},
		{"overflow", func(p *Params) { p.Reward = 1 << 62; p.Slots = 4 }, "overflows"},
		{"bad reviewer", func(p *Params) { p.Reviewers = []address{"nope"} }, "invalid reviewer"},
		{"dup reviewer", func(p *Params) { p.Reviewers = []address{reviewer, reviewer} }, "duplicate reviewer"},
		{"past deadline", func(p *Params) { p.Deadline = t0 }, "deadline must be in the future"},
		{"bad tag", func(p *Params) { p.Tags = []string{"no spaces"} }, "tags may only contain"},
	}
	for _, tc := range cases {
		p := base
		tc.edit(&p)
		_, err := New(p)
		if err == nil || !strings.Contains(err.Error(), tc.want) {
			t.Errorf("%s: got %v, want error containing %q", tc.name, err, tc.want)
		}
	}

	solo, err := New(base)
	urequire.NoError(t, err)
	uassert.True(t, solo.IsReviewer(poster), "poster reviews alone by default")
}

func TestClaimApproveReject(t *testing.T) {
	c := newCampaign(t, 2, time.Time{})

	_, err := c.Claim(poster, "https://x.com/p/1", t0)
	uassert.ErrorContains(t, err, "poster and reviewers cannot claim")
	_, err = c.Claim(reviewer, "https://x.com/p/1", t0)
	uassert.ErrorContains(t, err, "poster and reviewers cannot claim")
	_, err = c.Claim(alice, "  ", t0)
	uassert.ErrorContains(t, err, "proof link")

	n, err := c.Claim(alice, "https://x.com/alice/1", t0)
	urequire.NoError(t, err)
	uassert.Equal(t, 1, n)
	_, err = c.Claim(alice, "https://x.com/alice/2", t0)
	uassert.ErrorContains(t, err, "already have a pending claim (#1)")

	n, err = c.Claim(bob, "https://x.com/bob/1", t0)
	urequire.NoError(t, err)
	uassert.Equal(t, 2, n)
	_, err = c.Claim(carol, "https://x.com/carol/1", t0)
	uassert.ErrorContains(t, err, "every slot is taken")

	_, err = c.Approve(alice, 1, t0)
	uassert.ErrorIs(t, err, ErrUnauthorized)
	_, err = c.Approve(reviewer, 9, t0)
	uassert.ErrorIs(t, err, ErrBadClaim)

	pays, err := c.Approve(reviewer, 1, t0)
	urequire.NoError(t, err)
	urequire.Equal(t, 1, len(pays))
	uassert.Equal(t, alice.String(), pays[0].To.String())
	uassert.Equal(t, int64(10_000_000), pays[0].Amount)
	uassert.Equal(t, string(PayoutWork), string(pays[0].Kind))
	uassert.Equal(t, 1, pays[0].Claim)
	_, err = c.Approve(reviewer, 1, t0)
	uassert.ErrorContains(t, err, "already approved")
	_, err = c.Claim(alice, "https://x.com/alice/2", t0)
	uassert.ErrorContains(t, err, "already have an approved claim")

	// Rejecting frees the slot; the rejected claimant may try again.
	pays, err = c.Reject(reviewer, 2, "link is not public", t0)
	urequire.NoError(t, err)
	uassert.Equal(t, 0, len(pays))
	uassert.Equal(t, "link is not public", c.GetClaim(2).Reason)
	uassert.Equal(t, 1, c.FreeSlots())
	n, err = c.Claim(bob, "https://x.com/bob/2", t0)
	urequire.NoError(t, err)
	uassert.Equal(t, 3, n)
	uassert.Equal(t, 3, c.ClaimOf(bob).Number)

	// Paying the last slot closes the campaign.
	_, err = c.Approve(reviewer, 3, t0)
	urequire.NoError(t, err)
	uassert.Equal(t, "closed", c.Status.String())
	uassert.Equal(t, int64(0), c.Escrowed())
	uassert.Equal(t, int64(20_000_000), c.PaidOut())
	_, err = c.Claim(carol, "https://x.com/carol/1", t0)
	uassert.ErrorIs(t, err, ErrClosed)

	approved := ClaimApproved
	list, more := c.Claims(&approved, 0, 10)
	uassert.Equal(t, 2, len(list))
	uassert.False(t, more)
	uassert.Equal(t, 3, list[0].Number, "newest first")
	all, more := c.Claims(nil, 1, 1)
	uassert.Equal(t, 1, len(all))
	uassert.True(t, more)
	uassert.Equal(t, 2, all[0].Number)
}

func TestCloseRefunds(t *testing.T) {
	deadline := t0.Add(48 * time.Hour)
	c := newCampaign(t, 5, deadline)
	_, err := c.Claim(alice, "https://x.com/a", t0)
	urequire.NoError(t, err)
	_, err = c.Claim(bob, "https://x.com/b", t0)
	urequire.NoError(t, err)
	_, err = c.Approve(reviewer, 1, t0)
	urequire.NoError(t, err)

	// Only the poster can close before the deadline.
	_, err = c.Close(carol, t0)
	uassert.ErrorIs(t, err, ErrUnauthorized)

	// After it, claims stop and anyone can close.
	_, err = c.Claim(carol, "https://x.com/c", deadline)
	uassert.ErrorContains(t, err, "deadline has passed")
	pays, err := c.Close(carol, deadline)
	urequire.NoError(t, err)
	urequire.Equal(t, 1, len(pays))
	uassert.Equal(t, poster.String(), pays[0].To.String())
	uassert.Equal(t, int64(30_000_000), pays[0].Amount, "3 free slots back")
	uassert.Equal(t, int64(10_000_000), c.Escrowed(), "bob's pending claim stays escrowed")
	_, err = c.Close(poster, deadline)
	uassert.ErrorContains(t, err, "already closed")

	// The pending claim can still be reviewed; rejecting it refunds the poster.
	pays, err = c.Reject(reviewer, 2, "", deadline)
	urequire.NoError(t, err)
	urequire.Equal(t, 1, len(pays))
	uassert.Equal(t, string(PayoutRefund), string(pays[0].Kind))
	uassert.Equal(t, poster.String(), pays[0].To.String())
	uassert.Equal(t, int64(0), c.Escrowed())
	uassert.Equal(t, 4, c.Refunded)
}

func TestCloseByPosterEarly(t *testing.T) {
	c := newCampaign(t, 2, time.Time{})
	pays, err := c.Close(poster, t0)
	urequire.NoError(t, err)
	uassert.Equal(t, int64(20_000_000), pays[0].Amount)
	uassert.Equal(t, 0, c.FreeSlots())
}
