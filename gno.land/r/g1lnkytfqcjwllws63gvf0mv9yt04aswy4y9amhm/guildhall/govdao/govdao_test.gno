package govdao

import (
	"testing"

	"gno.land/p/nt/testutils/v0"
	"gno.land/p/nt/uassert/v0"
	"gno.land/r/g1lnkytfqcjwllws63gvf0mv9yt04aswy4y9amhm/guildhall/reputation"
)

func TestSetThresholdIsGuildhallOnly(cur realm, t *testing.T) {
	testing.SetRealm(testing.NewCodeRealm("gno.land/r/gov/dao"))
	uassert.AbortsWithMessage(t, cur, "guildhall: only the Guildhall admin may change thresholds", func() {
		SetThreshold(cross(cur), "T2", 1)
	})
	testing.SetRealm(testing.NewUserRealm(testutils.TestAddress("someone")))
	uassert.AbortsWithMessage(t, cur, "guildhall: only the Guildhall admin may change thresholds", func() {
		SetThreshold(cross(cur), "T2", 1)
	})

	testing.SetRealm(testing.NewUserRealm(reputation.Admin()))
	SetThreshold(cross(cur), "T2", 900)
	uassert.Equal(t, int64(900), Threshold("T2"))
	uassert.AbortsWithMessage(t, cur, `guildhall: unknown tier "T9"`, func() { SetThreshold(cross(cur), "T9", 1) })
}
