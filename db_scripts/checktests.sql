SELECT
	t.rowid AS JobId,
	tr.rowid AS TestSeq,
	t.server AS Server,
	t.test_date AS TestDate,
	tr.exit_code AS ExitCode,
	printf("%.2f", tr.execution_time_sec) AS TimeSec,
	tr.name AS TestName
FROM tests AS t
INNER JOIN test_results AS tr ON t.rowid = tr.test_id
ORDER BY tr.rowid;