select sum(bids.p * bids.v), sum(bids.v)
	from bids
	where 0.25*(select sum(b2.v) from bids b2) > 
		(select sum(b1.v) from bids b1
			where b1.p > bids.p)