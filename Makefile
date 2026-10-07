PATHS = gno.land/r/g1lnkytfqcjwllws63gvf0mv9yt04aswy4y9amhm/guildhall,gno.land/r/g1lnkytfqcjwllws63gvf0mv9yt04aswy4y9amhm/guildhall/bounties,gno.land/r/g1lnkytfqcjwllws63gvf0mv9yt04aswy4y9amhm/guildhall/reputation,gno.land/r/g1lnkytfqcjwllws63gvf0mv9yt04aswy4y9amhm/guildhall/govdao

.PHONY: test lint fmt dev

test:
	go tool gno test ./gno.land/...

lint:
	go tool gno lint ./gno.land/...

fmt:
	go tool gno fmt -w ./gno.land/...

dev:
	go tool gnodev -empty-blocks -paths "$(PATHS)"
