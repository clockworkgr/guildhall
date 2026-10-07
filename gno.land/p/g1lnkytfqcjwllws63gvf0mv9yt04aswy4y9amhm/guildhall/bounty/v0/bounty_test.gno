package bounty

import (
	"testing"
	"time"

	"gno.land/p/nt/testutils/v0"
	"gno.land/p/nt/uassert/v0"
	"gno.land/p/nt/urequire/v0"
)

var (
	poster   = testutils.TestAddress("poster")
	worker   = testutils.TestAddress("worker")
	worker2  = testutils.TestAddress("worker2")
	rev1     = testutils.TestAddress("rev1")
	rev2     = testutils.TestAddress("rev2")
	rev3     = testutils.TestAddress("rev3")
	arbiter  = testutils.TestAddress("arbiter")
	stranger = testutils.TestAddress("stranger")

	t0 = time.Date(2026, 9, 26, 0, 0, 0, 0, time.UTC)
)

func validParams() Params {
	return Params{
		ID:          1,
		Poster:      poster,
		Title:       "Port the faucet to interrealm v2",
		Description: "Rewrite r/faucet with cur realm.",
		Link:        "https://github.com/gnolang/gno/issues/1",
		Tags:        []string{"Realm", "faucet"},
		Denom:       "ugnot",
		Reviewers:   []address{rev1, rev2, rev3},
		Quorum:      2,
		Arbiter:     arbiter,
		Milestones:  []MilestoneSpec{{"Design", 1000}, {"Implementation", 4000}},
		Now:         t0,
	}
}

func newActive(t *testing.T) *Bounty {
	b, err := New(validParams())
	urequire.NoError(t, err)
	urequire.NoError(t, b.Assign(poster, worker, t0))
	return b
}

func TestNewValidation(t *testing.T) {
	var p Params
	cases := []struct {
		name     string
		malleate func()
		expErr   string
	}{
		{"success", func() {}, ""},
		{"empty title", func() { p.Title = "  " }, "title"},
		{"invalid poster", func() { p.Poster = "nope" }, "poster"},
		{"no denom", func() { p.Denom = "" }, "denomination"},
		{"bad reviewer", func() { p.Reviewers = []address{"nope"} }, "reviewer"},
		{"duplicate reviewer", func() { p.Reviewers = []address{rev1, rev1} }, "duplicate"},
		{"quorum too high", func() { p.Quorum = 4 }, "quorum"},
		{"negative quorum", func() { p.Quorum = -1 }, "quorum"},
		{"bad arbiter", func() { p.Arbiter = "" }, "arbiter"},
		{"no milestones", func() { p.Milestones = nil }, "milestones"},
		{"zero amount", func() { p.Milestones = []MilestoneSpec{{"x", 0}} }, "positive"},
		{"bad tag", func() { p.Tags = []string{"no spaces!"} }, "tags"},
		{"too many tags", func() { p.Tags = []string{"a", "b", "c", "d", "e", "f"} }, "tags"},
		{"negative window", func() { p.WorkWindow = -time.Hour }, "window"},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			p = validParams()
			tc.malleate()
			_, err := New(p)
			if tc.expErr == "" {
				urequire.NoError(t, err)
				return
			}
			uassert.ErrorContains(t, err, tc.expErr)
		})
	}
}

func TestNewDefaults(t *testing.T) {
	p := validParams()
	p.Reviewers = nil
	p.Quorum = 0
	b, err := New(p)
	urequire.NoError(t, err)
	uassert.Equal(t, 1, len(b.Reviewers))
	uassert.Equal(t, poster.String(), b.Reviewers[0].String())
	uassert.Equal(t, 1, b.Quorum)
	uassert.Equal(t, int64(DefaultWorkWindow), int64(b.WorkWindow))
	uassert.Equal(t, int64(5000), b.Total())
	uassert.Equal(t, int64(5000), b.Escrowed())
	uassert.Equal(t, "realm", b.Tags[0], "tags are lowercased")
	uassert.Equal(t, StatusOpen.String(), b.Status.String())
}

func TestParseMilestones(t *testing.T) {
	specs, err := ParseMilestones("Design = 1000; Build=4000;", 0)
	urequire.NoError(t, err)
	uassert.Equal(t, 2, len(specs))
	uassert.Equal(t, "Design", specs[0].Title)
	uassert.Equal(t, int64(1000), specs[0].Amount)
	uassert.Equal(t, int64(4000), specs[1].Amount)

	specs, err = ParseMilestones("", 700)
	urequire.NoError(t, err)
	uassert.Equal(t, 1, len(specs))
	uassert.Equal(t, int64(700), specs[0].Amount)

	specs, err = ParseMilestones("a=b=5", 0)
	urequire.NoError(t, err)
	uassert.Equal(t, "a=b", specs[0].Title, "last '=' separates the amount")

	_, err = ParseMilestones("", 0)
	uassert.Error(t, err)
	_, err = ParseMilestones("Design", 0)
	uassert.ErrorContains(t, err, "Title=amount")
	_, err = ParseMilestones("Design=-5", 0)
	uassert.ErrorContains(t, err, "positive integer")
	_, err = ParseMilestones("Design=99999999999999999999", 0)
	uassert.ErrorContains(t, err, "overflows")
}

func TestParseAddresses(t *testing.T) {
	got := ParseAddresses(" " + rev1.String() + ", " + rev2.String() + " ")
	uassert.Equal(t, 2, len(got))
	uassert.Equal(t, rev2.String(), got[1].String())
	uassert.Equal(t, 0, len(ParseAddresses("")))
}

func TestApplyAndAssign(t *testing.T) {
	b, err := New(validParams())
	urequire.NoError(t, err)

	urequire.NoError(t, b.Apply(worker, "I wrote the original faucet", t0))
	uassert.ErrorContains(t, b.Apply(worker, "again", t0), "already applied")
	uassert.ErrorContains(t, b.Apply(poster, "", t0), "cannot apply")
	uassert.ErrorContains(t, b.Apply(rev1, "", t0), "cannot apply")
	uassert.True(t, b.HasApplied(worker))

	uassert.ErrorIs(t, b.Assign(stranger, worker, t0), ErrUnauthorized)
	uassert.ErrorContains(t, b.Assign(poster, rev2, t0), "cannot be assigned")
	uassert.ErrorContains(t, b.Assign(poster, poster, t0), "cannot be assigned")
	urequire.NoError(t, b.Assign(poster, worker, t0))
	uassert.Equal(t, StatusActive.String(), b.Status.String())
	uassert.ErrorIs(t, b.Assign(poster, worker2, t0), ErrBadState)
	uassert.ErrorIs(t, b.Apply(worker2, "", t0), ErrBadState)
}

func TestHappyPathWithQuorum(t *testing.T) {
	b := newActive(t)

	uassert.ErrorIs(t, b.Submit(stranger, 0, "https://x", t0), ErrUnauthorized)
	uassert.ErrorIs(t, b.Submit(worker, 5, "https://x", t0), ErrBadMilestone)
	uassert.ErrorContains(t, b.Submit(worker, 0, "", t0), "link")
	urequire.NoError(t, b.Submit(worker, 0, "https://github.com/gnolang/gno/pull/10", t0))
	uassert.ErrorIs(t, b.Submit(worker, 0, "https://x", t0), ErrBadState)

	_, err := b.Approve(stranger, 0, t0)
	uassert.ErrorIs(t, err, ErrUnauthorized)

	payouts, err := b.Approve(rev1, 0, t0)
	urequire.NoError(t, err)
	uassert.Equal(t, 0, len(payouts), "quorum not reached")
	_, err = b.Approve(rev1, 0, t0)
	uassert.ErrorContains(t, err, "already approved")

	payouts, err = b.Approve(rev2, 0, t0)
	urequire.NoError(t, err)
	urequire.Equal(t, 1, len(payouts))
	uassert.Equal(t, worker.String(), payouts[0].To.String())
	uassert.Equal(t, int64(1000), payouts[0].Amount)
	uassert.Equal(t, string(PayoutWork), string(payouts[0].Kind))
	uassert.Equal(t, MilestonePaid.String(), b.Milestones[0].Status.String())
	uassert.Equal(t, StatusActive.String(), b.Status.String())
	uassert.Equal(t, int64(4000), b.Escrowed())

	_, err = b.Approve(rev3, 0, t0)
	uassert.ErrorIs(t, err, ErrBadState, "paid milestones take no more approvals")

	urequire.NoError(t, b.Submit(worker, 1, "https://github.com/gnolang/gno/pull/11", t0))
	b.Approve(rev3, 1, t0)
	payouts, err = b.Approve(rev1, 1, t0)
	urequire.NoError(t, err)
	uassert.Equal(t, int64(4000), payouts[0].Amount)
	uassert.Equal(t, StatusCompleted.String(), b.Status.String())
	uassert.Equal(t, int64(0), b.Escrowed())
	uassert.Equal(t, int64(5000), b.PaidOut())
}

func TestRequestChangesResetsApprovals(t *testing.T) {
	b := newActive(t)
	urequire.NoError(t, b.Submit(worker, 0, "https://x/1", t0))
	b.Approve(rev1, 0, t0)

	uassert.ErrorIs(t, b.RequestChanges(worker, 0, "lgtm"), ErrUnauthorized)
	urequire.NoError(t, b.RequestChanges(rev2, 0, "missing tests"))
	m := b.Milestones[0]
	uassert.Equal(t, MilestoneChangesRequested.String(), m.Status.String())
	uassert.Equal(t, 0, len(m.Approvals))
	uassert.Equal(t, "missing tests", m.Feedback)

	urequire.NoError(t, b.Submit(worker, 0, "https://x/2", t0))
	payouts, _ := b.Approve(rev1, 0, t0)
	uassert.Equal(t, 0, len(payouts), "earlier approval was discarded")
	payouts, _ = b.Approve(rev2, 0, t0)
	uassert.Equal(t, 1, len(payouts))
}

func TestDisputeSplit(t *testing.T) {
	b := newActive(t)
	urequire.NoError(t, b.Submit(worker, 1, "https://x/1", t0))
	urequire.NoError(t, b.RequestChanges(rev1, 1, "not what we asked"))

	uassert.ErrorIs(t, b.OpenDispute(stranger, 1, "hm", t0), ErrUnauthorized)
	uassert.ErrorIs(t, b.OpenDispute(poster, 0, "hm", t0), ErrBadState, "pending milestones cannot be disputed")
	uassert.ErrorContains(t, b.OpenDispute(worker, 1, " ", t0), "reason")
	urequire.NoError(t, b.OpenDispute(worker, 1, "spec was ambiguous", t0))
	uassert.Equal(t, MilestoneDisputed.String(), b.Milestones[1].Status.String())

	// Nothing can move a disputed milestone except the arbiter.
	uassert.ErrorIs(t, b.Submit(worker, 1, "https://x/2", t0), ErrBadState)
	_, err := b.Approve(rev1, 1, t0)
	uassert.ErrorIs(t, err, ErrBadState)
	uassert.ErrorContains(t, b.Unassign(worker, t0), "arbitration")

	_, err = b.Resolve(poster, 1, 5000, "", t0)
	uassert.ErrorIs(t, err, ErrUnauthorized)
	_, err = b.Resolve(arbiter, 1, 10001, "", t0)
	uassert.ErrorContains(t, err, "share")

	payouts, err := b.Resolve(arbiter, 1, 2500, "partial delivery", t0)
	urequire.NoError(t, err)
	urequire.Equal(t, 2, len(payouts))
	uassert.Equal(t, worker.String(), payouts[0].To.String())
	uassert.Equal(t, int64(1000), payouts[0].Amount)
	uassert.Equal(t, poster.String(), payouts[1].To.String())
	uassert.Equal(t, int64(3000), payouts[1].Amount)
	uassert.Equal(t, string(PayoutRefund), string(payouts[1].Kind))
	uassert.Equal(t, MilestoneSplit.String(), b.Milestones[1].Status.String())
	uassert.True(t, b.Milestones[1].Dispute.Resolved)

	_, err = b.Resolve(arbiter, 1, 2500, "", t0)
	uassert.ErrorIs(t, err, ErrBadState, "cannot resolve twice")
}

func TestDisputeOutcomes(t *testing.T) {
	b := newActive(t)
	urequire.NoError(t, b.Submit(worker, 0, "https://x/0", t0))
	urequire.NoError(t, b.OpenDispute(poster, 0, "plagiarised", t0))
	payouts, err := b.Resolve(arbiter, 0, 0, "upheld", t0)
	urequire.NoError(t, err)
	uassert.Equal(t, 1, len(payouts))
	uassert.Equal(t, poster.String(), payouts[0].To.String())
	uassert.Equal(t, MilestoneRefunded.String(), b.Milestones[0].Status.String())

	urequire.NoError(t, b.Submit(worker, 1, "https://x/1", t0))
	urequire.NoError(t, b.OpenDispute(worker, 1, "reviewers went silent", t0))
	payouts, err = b.Resolve(arbiter, 1, MaxBps, "work is fine", t0)
	urequire.NoError(t, err)
	uassert.Equal(t, 1, len(payouts))
	uassert.Equal(t, worker.String(), payouts[0].To.String())
	uassert.Equal(t, MilestonePaid.String(), b.Milestones[1].Status.String())
	uassert.Equal(t, StatusCompleted.String(), b.Status.String())
}

func TestUnassign(t *testing.T) {
	b := newActive(t)
	uassert.ErrorContains(t, b.Unassign(poster, t0), "work window")
	uassert.ErrorIs(t, b.Unassign(stranger, t0), ErrUnauthorized)

	urequire.NoError(t, b.Submit(worker, 0, "https://x/0", t0))
	later := t0.Add(DefaultWorkWindow + time.Hour)
	uassert.ErrorContains(t, b.Unassign(poster, later), "awaiting review")

	urequire.NoError(t, b.RequestChanges(rev1, 0, "nope"))
	urequire.NoError(t, b.Unassign(poster, later))
	uassert.Equal(t, StatusOpen.String(), b.Status.String())
	uassert.Equal(t, address("").String(), b.Assignee.String())
	uassert.Equal(t, MilestonePending.String(), b.Milestones[0].Status.String(), "rejected work resets for the next assignee")

	// A contributor can always step back.
	urequire.NoError(t, b.Assign(poster, worker2, later))
	urequire.NoError(t, b.Unassign(worker2, later))
	uassert.Equal(t, StatusOpen.String(), b.Status.String())
}

func TestReassignKeepsPaidWork(t *testing.T) {
	b := newActive(t)
	urequire.NoError(t, b.Submit(worker, 0, "https://x/0", t0))
	b.Approve(rev1, 0, t0)
	b.Approve(rev2, 0, t0)
	urequire.NoError(t, b.Unassign(worker, t0))
	urequire.NoError(t, b.Assign(poster, worker2, t0))
	uassert.Equal(t, worker.String(), b.Milestones[0].Worker.String(), "paid milestone keeps its worker")
	uassert.ErrorIs(t, b.Submit(worker, 1, "https://x/1", t0), ErrUnauthorized)
	urequire.NoError(t, b.Submit(worker2, 1, "https://x/1", t0))
}

func TestCancel(t *testing.T) {
	b := newActive(t)
	_, err := b.Cancel(poster, t0)
	uassert.ErrorIs(t, err, ErrBadState, "active bounties must be unassigned first")

	urequire.NoError(t, b.Submit(worker, 0, "https://x/0", t0))
	b.Approve(rev1, 0, t0)
	b.Approve(rev2, 0, t0)
	urequire.NoError(t, b.Unassign(worker, t0))

	_, err = b.Cancel(worker, t0)
	uassert.ErrorIs(t, err, ErrUnauthorized)
	payouts, err := b.Cancel(poster, t0)
	urequire.NoError(t, err)
	urequire.Equal(t, 1, len(payouts), "only the unsettled milestone is refunded")
	uassert.Equal(t, int64(4000), payouts[0].Amount)
	uassert.Equal(t, poster.String(), payouts[0].To.String())
	uassert.Equal(t, StatusCancelled.String(), b.Status.String())
	uassert.Equal(t, int64(0), b.Escrowed())

	_, err = b.Cancel(poster, t0)
	uassert.ErrorIs(t, err, ErrBadState)
}

func TestStatusStrings(t *testing.T) {
	for _, s := range []Status{StatusOpen, StatusActive, StatusCompleted, StatusCancelled} {
		got, ok := ParseStatus(s.String())
		uassert.True(t, ok)
		uassert.Equal(t, s.String(), got.String())
	}
	_, ok := ParseStatus("bogus")
	uassert.False(t, ok)
	uassert.True(t, MilestoneSplit.Settled())
	uassert.False(t, MilestoneDisputed.Settled())
}
