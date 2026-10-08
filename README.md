# Guildhall

Live on the Onyx testnet at [onyx.testnets.gno.land/r/g1lnkytfqcjwllws63gvf0mv9yt04aswy4y9amhm/guildhall](https://onyx.testnets.gno.land/r/g1lnkytfqcjwllws63gvf0mv9yt04aswy4y9amhm/guildhall), with a web app at [guildhall.clockwork.gr](https://guildhall.clockwork.gr) ([source](https://github.com/clockworkgr/guildhall-web)).

An on-chain bounty board and contribution-reputation system for gno.land. It lets people fund work, track it, and turn finished work into a record anyone can check.

- **Escrowed bounties.** Anyone can post a task funded with GNOT (or any native coin) or any token in the GRC20 registry, split into milestones. Funds stay in the realm until the bounty's reviewers approve a milestone.
- **Campaigns.** A fixed reward for each person who does a small task, up to a set number of people: 10 GNOT each to the first 100 people who write about something is one campaign holding 1000 GNOT. A reviewer checks each claim before it pays.
- **Records of completed work.** Every payout writes a record: who did the work, who funded it, who vouched for it, how much it paid, which transaction released the funds, and a link to the PR, realm path or proposal.
- **Reputation other realms can use.** Scores are built from those records and weighted by the reputation of the reviewers. Any realm can gate on them with one import.
- **No separate website needed.** Every page is rendered by the realms themselves and served by gnoweb.

## Layout

```
gno.land/
  p/g1lnkytfqcjwllws63gvf0mv9yt04aswy4y9amhm/guildhall/bounty/v0      bounty state machine: milestones, quorum, disputes, cancellation (pure, no coins)
  p/g1lnkytfqcjwllws63gvf0mv9yt04aswy4y9amhm/guildhall/campaign/v0    campaign state machine: slots, claims, approvals, refunds (pure, no coins)
  p/g1lnkytfqcjwllws63gvf0mv9yt04aswy4y9amhm/guildhall/trust/v0       scoring rules: reviewer trust, record points, levels (pure)
  r/g1lnkytfqcjwllws63gvf0mv9yt04aswy4y9amhm/guildhall                landing page
  r/g1lnkytfqcjwllws63gvf0mv9yt04aswy4y9amhm/guildhall/bounties       escrow + bounty board (native coins and GRC20)
  r/g1lnkytfqcjwllws63gvf0mv9yt04aswy4y9amhm/guildhall/campaigns      escrow for many-hands tasks: fixed reward per claim, fixed slots
  r/g1lnkytfqcjwllws63gvf0mv9yt04aswy4y9amhm/guildhall/reputation     work records, scores, leaderboard, the import-able API
  r/g1lnkytfqcjwllws63gvf0mv9yt04aswy4y9amhm/guildhall/govdao         optional: reputation as an input to GovDAO membership
  r/g1lnkytfqcjwllws63gvf0mv9yt04aswy4y9amhm/guildhall/testing/gld20  throwaway GRC20 used by tests; do not deploy
scripts/
  deploy.sh                  deploys every package and realm in order (Onyx by default)
  propose_member.gno         MsgRun: propose a contributor to GovDAO with a generated portfolio
  bootstrap.gno              MsgRun: seed reviewers, optionally move admin/council to multisigs
```

The rules live in `p/`, free of chain effects, so they can be tested exhaustively and reused. The realms handle authentication, moving funds, storage and rendering.

## Pages

| URL | What |
|---|---|
| `/r/g1lnkytfqcjwllws63gvf0mv9yt04aswy4y9amhm/guildhall` | overview, live stats, top contributors |
| `/r/g1lnkytfqcjwllws63gvf0mv9yt04aswy4y9amhm/guildhall/bounties` | board, filterable: `?status=open\|active\|completed\|cancelled\|all&tag=x&page=N` |
| `/r/g1lnkytfqcjwllws63gvf0mv9yt04aswy4y9amhm/guildhall/bounties:<id>` | bounty, milestones, disputes, applications, one-click action links |
| `/r/g1lnkytfqcjwllws63gvf0mv9yt04aswy4y9amhm/guildhall/bounties:u/<addr>` | every bounty an address is involved in, with its role |
| `/r/g1lnkytfqcjwllws63gvf0mv9yt04aswy4y9amhm/guildhall/bounties:post` | how to post (form links + `gnokey` example) |
| `/r/g1lnkytfqcjwllws63gvf0mv9yt04aswy4y9amhm/guildhall/campaigns` | campaigns, filterable: `?status=open\|closed\|all&tag=x&page=N` |
| `/r/g1lnkytfqcjwllws63gvf0mv9yt04aswy4y9amhm/guildhall/campaigns:<id>` | campaign and its claims (`?claims=pending\|approved\|rejected\|all`), with approve/reject links |
| `/r/g1lnkytfqcjwllws63gvf0mv9yt04aswy4y9amhm/guildhall/campaigns:u/<addr>` | campaigns an address posted, reviews or claimed |
| `/r/g1lnkytfqcjwllws63gvf0mv9yt04aswy4y9amhm/guildhall/campaigns:post` | how to post a campaign |
| `/r/g1lnkytfqcjwllws63gvf0mv9yt04aswy4y9amhm/guildhall/reputation` | leaderboard, latest records |
| `/r/g1lnkytfqcjwllws63gvf0mv9yt04aswy4y9amhm/guildhall/reputation:u/<addr>` | profile: score, level, rank, work, reviews, earnings |
| `/r/g1lnkytfqcjwllws63gvf0mv9yt04aswy4y9amhm/guildhall/reputation:record/<id>` | a record, with each reviewer's trust when they approved |
| `/r/g1lnkytfqcjwllws63gvf0mv9yt04aswy4y9amhm/guildhall/reputation:about` | scoring rules and live parameters |
| `/r/g1lnkytfqcjwllws63gvf0mv9yt04aswy4y9amhm/guildhall/govdao:u/<addr>` | GovDAO eligibility per tier + generated portfolio |

## Bounty lifecycle

```
Open ──Assign──▶ Active ──(all milestones settled)──▶ Completed
  ▲                │
  └─Unassign/Resign┘          Open ──Cancel──▶ Cancelled (unpaid milestones refunded)

Milestone: Pending ──Submit──▶ Submitted ──Approve × quorum──▶ Paid   (+ reputation record)
              ▲                  │    │
              └─RequestChanges───┘    └─OpenDispute─▶ Disputed ──Resolve(bps)──▶ Paid | Split | Refunded
```

| Function | Who | Notes |
|---|---|---|
| `PostBounty(title, description, link, tags, reviewers, quorum, milestones, arbiter, workWindowDays)` + `-send` | anyone (direct call) | `milestones` = `Title=amount;Title=amount`, must sum to what was sent; empty = one milestone |
| `PostBountyGRC20(tokenKey, …)` | anyone | approve the bounties realm on the token first |
| `Apply(id, pitch)` | anyone but poster/reviewers | |
| `Assign(id, assignee)` | poster | assignee can't be the poster, a reviewer or the arbiter |
| `Unassign(id)` | assignee anytime; poster after the work window | not while a milestone is in review or disputed |
| `Submit(id, milestone, link)` | assignee | milestones are 1-based |
| `Approve(id, milestone)` | reviewer | the quorum-reaching approval pays out and writes the record |
| `RequestChanges(id, milestone, feedback)` | reviewer | discards approvals so far |
| `OpenDispute(id, milestone, reason)` | poster or the submitting worker | |
| `Resolve(id, milestone, workerBps, ruling)` | arbiter | pays `workerBps/10000` to the worker, refunds the rest |
| `Cancel(id)` | poster | open bounties only; active ones must be unassigned first |

A bounty with no reviewers is reviewed by its poster. A bounty with no arbiter is arbitrated by the **council**, which follows the seat if it changes hands. The council can pause new postings, but never payouts or refunds.

## Campaigns

```
Open ──Close (poster; anyone after the deadline)──▶ Closed (free slots refunded)
Open ──(every slot paid)──▶ Closed

Claim: Pending ──ApproveClaim──▶ Approved (reward paid + reputation record at 5%)
          └─────RejectClaim───▶ Rejected (slot freed; refunded to the poster if closed)
```

| Function | Who | Notes |
|---|---|---|
| `PostCampaign(title, description, link, tags, reviewers, reward, slots, deadlineDays)` + `-send` | anyone (direct call) | send exactly `reward × slots`; up to 1000 slots; `deadlineDays` 0 = none |
| `PostCampaignGRC20(tokenKey, …)` | anyone | approve the campaigns realm on the token first |
| `Claim(id, proof)` | anyone but the poster and reviewers | one pending or approved claim per address; a pending claim reserves a slot |
| `ApproveClaim(id, claim)` | any one reviewer | pays the reward and writes the record |
| `RejectClaim(id, claim, reason)` | any one reviewer | the claimant may claim again while the campaign is open |
| `Close(id)` | poster; anyone after the deadline | pending claims can still be reviewed afterwards |

Each paid claim writes a reputation record at `ClaimShareBps` (5%) of a bounty milestone's weight, vouched for by the reviewer who approved it, so repeatable small tasks count without outweighing reviewed bounty work. With no reviewers the poster reviews alone, so the records carry the poster's own trust as a reviewer.

## Reputation

Scoring is in `p/g1lnkytfqcjwllws63gvf0mv9yt04aswy4y9amhm/guildhall/trust`:

- A record is worth `Base` (100) points, scaled by the **average trust of the approving reviewers**.
- **Seed reviewers**, curated by the Guildhall admin, carry full trust. Everyone else carries trust in proportion to their own score, reaching full trust at `TrustThreshold` (500).
- Reviewers with no score carry **0** trust, so a ring of fresh accounts approving each other earns nothing. Trust spreads outward from the seeds one paid record at a time.
- Nobody can vouch for their own work. Self-funded work earns 0 by default.
- Split disputes scale points by the worker's share.
- Points are fixed when a record is written. The admin can void a fraudulent record, which removes its points.

Using it from another realm:

```go
import "gno.land/r/g1lnkytfqcjwllws63gvf0mv9yt04aswy4y9amhm/guildhall/reputation"

func Vote(cur realm, pid int) {
	reputation.AssertScore(cur.Previous().Address(), 300) // panics below 300
	// ...
}
```

Also available: `Score`, `Level`, `HasScore`, `Rank`, `Top(n)`, `CompletedCount`, `ReviewCount`, `Earned(addr, denom)`, `GetRecord`, `RecordsOf`, `ReviewsOf`, `IsSeed`.

Only allowlisted **writer** realms can call `AddRecord`. Those are `r/g1lnkytfqcjwllws63gvf0mv9yt04aswy4y9amhm/guildhall/bounties` and `r/g1lnkytfqcjwllws63gvf0mv9yt04aswy4y9amhm/guildhall/campaigns`, and the admin can add more, for example a grants realm.

## Governance

Guildhall governs itself. No outside realm, GovDAO included, has any authority over it. Two roles exist, and both start with the namespace address `g1lnkytfqcjwllws63gvf0mv9yt04aswy4y9amhm`:

| Role | Controls | Hand on with |
|---|---|---|
| reputation admin | seeds, writer realms, scoring params, voiding records, GovDAO-bridge thresholds | `reputation.TransferAdmin(addr)` |
| bounty council | default arbiter, posting pause | `bounties.TransferCouncil(addr)` |

Use a multisig for either role to share it. `reputation.RenounceAdmin()` exists for anyone who wants reputation frozen for good. After it, nothing can add seeds or void records, so don't call it casually.

`scripts/bootstrap.gno` adds the first seed reviewers and optionally moves both roles to multisigs, all in one transaction.

### Optional GovDAO bridge (`r/g1lnkytfqcjwllws63gvf0mv9yt04aswy4y9amhm/guildhall/govdao`)

A one-way adapter: it reads reputation and builds GovDAO proposals, and nothing else in Guildhall depends on it, so you can skip deploying it. A GovDAO member can use `NewMemberRequest(addr, tier)` to propose a contributor. It refuses candidates below Guildhall's threshold for that tier (default T1 2000, T2 800, T3 300) and attaches a portfolio generated from their records (see `scripts/propose_member.gno`). GovDAO's own vote decides. The thresholds are set by the Guildhall admin with `SetThreshold`.

## Web app and JSON API

[guildhall-web](https://github.com/clockworkgr/guildhall-web) is a static front end for all of the above, published at [guildhall.clockwork.gr](https://guildhall.clockwork.gr). It reads over RPC and signs with Adena. Its data comes from JSON endpoints that the realms serve under `Render("api/...")`, for example `bounties:api/bounty/3` or `reputation:api/profile/g1…`, built with the small `p/…/guildhall/jsonw` package. Any other client can use the same endpoints through `vm/qrender`.

## Develop

Tooling is pinned via `go.mod` (same gno master commit as the IBC realms), so always use `go tool gno`:

```sh
make test      # go tool gno test ./gno.land/...
make lint
make dev       # gnodev with all Guildhall realms; gnoweb on http://127.0.0.1:8888
```

A walkthrough on a local node, using gnodev's `test1` key:

```sh
K="go tool gnokey"; C="-gas-fee 1000000ugnot -gas-wanted 50000000 -broadcast -chainid dev -remote tcp://127.0.0.1:26657"
$K maketx call $C -pkgpath gno.land/r/g1lnkytfqcjwllws63gvf0mv9yt04aswy4y9amhm/guildhall/reputation -func AddSeed -args $REVIEWER test1
$K maketx call $C -pkgpath gno.land/r/g1lnkytfqcjwllws63gvf0mv9yt04aswy4y9amhm/guildhall/bounties -func PostBounty -send 10000000ugnot \
  -args "Port r/faucet" -args "…" -args "https://github.com/gnolang/gno/issues/1" -args "realm" \
  -args $REVIEWER -args 1 -args "Design=2000000;Build=8000000" -args "" -args 30 test1
$K maketx call $C -pkgpath gno.land/r/g1lnkytfqcjwllws63gvf0mv9yt04aswy4y9amhm/guildhall/bounties -func Apply  -args 1 -args "pitch" worker
$K maketx call $C -pkgpath gno.land/r/g1lnkytfqcjwllws63gvf0mv9yt04aswy4y9amhm/guildhall/bounties -func Assign -args 1 -args $WORKER test1
$K maketx call $C -pkgpath gno.land/r/g1lnkytfqcjwllws63gvf0mv9yt04aswy4y9amhm/guildhall/bounties -func Submit -args 1 -args 1 -args "https://github.com/…/pull/2" worker
$K maketx call $C -pkgpath gno.land/r/g1lnkytfqcjwllws63gvf0mv9yt04aswy4y9amhm/guildhall/bounties -func Approve -args 1 -args 1 reviewer
```

## Deploying

`scripts/deploy.sh` does steps 1 to 3: it deploys from the `mainclock` key to the Onyx testnet (`onyx-1`), leaving out test files and `testing/*`, skips packages already on chain, and registers the bounties and campaigns realms as reputation writers (step 3). Set `KEY`, `CHAIN_ID` and `REMOTE` to target another network, such as mainnet. Onyx charges a storage deposit of 100 ugnot per byte, so have a few dozen GNOT on the key.

1. Deploy from the key whose address is `g1lnkytfqcjwllws63gvf0mv9yt04aswy4y9amhm`: only that address may publish under `r/g1lnky…/` and `p/g1lnky…/`. No namespace registration is needed. To move to a registered name later (e.g. `r/guildhall`), rewrite the paths and redeploy; realm state does not migrate.
2. `gnokey maketx addpkg` in dependency order: `p/g1lnkytfqcjwllws63gvf0mv9yt04aswy4y9amhm/guildhall/jsonw/v0`, `p/g1lnkytfqcjwllws63gvf0mv9yt04aswy4y9amhm/guildhall/trust/v0`, `p/g1lnkytfqcjwllws63gvf0mv9yt04aswy4y9amhm/guildhall/bounty/v0`, `p/g1lnkytfqcjwllws63gvf0mv9yt04aswy4y9amhm/guildhall/campaign/v0`, `r/g1lnkytfqcjwllws63gvf0mv9yt04aswy4y9amhm/guildhall/reputation`, `r/g1lnkytfqcjwllws63gvf0mv9yt04aswy4y9amhm/guildhall/bounties`, `r/g1lnkytfqcjwllws63gvf0mv9yt04aswy4y9amhm/guildhall/campaigns`, `r/g1lnkytfqcjwllws63gvf0mv9yt04aswy4y9amhm/guildhall/govdao` (optional), `r/g1lnkytfqcjwllws63gvf0mv9yt04aswy4y9amhm/guildhall`. Do **not** deploy `r/g1lnkytfqcjwllws63gvf0mv9yt04aswy4y9amhm/guildhall/testing/*`.
3. As the reputation admin, `AddWriter("gno.land/r/…/guildhall/campaigns")`. The bounties realm is registered when reputation is deployed; campaigns came later, and its payouts fail until it is added.
4. Fill in and run `scripts/bootstrap.gno`.

## Known limits (v1)

- The board page scans bounties newest-first to apply filters. That's fine for thousands of bounties; add per-status and per-tag indexes before it outgrows query gas.
- Reputation is computed once, when a record is written. Removing a seed or voiding a record doesn't unwind trust the affected account already passed on to others.
- A trusted reviewer who funds bounties to their own sybil can mint reputation for it. The defence is social: records are public and attributable, voids are available, and seeds are chosen by the admin.
- Campaign claims are checked by a person, not the chain: a proof link is only as good as the reviewer who opens it. Sybil accounts can each claim once, so keep rewards small or reviewers strict.
- The landing realm (`r/…/guildhall`) predates campaigns and doesn't link to them; realms can't be changed once deployed.
- After the work window passes, a poster can unassign a worker whose milestone has "changes requested", ending the worker's chance to dispute it. Workers should dispute promptly.
