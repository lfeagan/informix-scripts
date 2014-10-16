-- tabprof.sql
database sysmaster;
select
	dbsname,
	tabname,
	isreads,
	bufreads,
	pagreads
	-- uncomment the following to show writes
	-- iswrites,
	-- bufwrites,
	-- pagwrites
	-- uncomment the following to show locks
	-- lockreqs,
	-- lockwts,
	-- deadlks
from sysptprof
where (bufreads > 1 OR pagreads > 1)
order by isreads desc; -- change this sort to whatever you need to monitor.
