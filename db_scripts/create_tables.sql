DROP TABLE IF EXISTS test_commands;
DROP TABLE IF EXISTS test_results;
DROP TABLE IF EXISTS tests;

CREATE TABLE tests ( 
	server VARCHAR(30) NOT NULL,	
	test_date DATE NOT NULL,
	ps_info VARCHAR(255)
); 
CREATE TABLE test_results ( 
	test_id integer NOT NULL,
	key_id VARCHAR(50) NOT NULL UNIQUE,
	name VARCHAR(50) NOT NULL,
	command VARCHAR(255) NOT NULL,
	exit_code INTEGER NOT NULL,
	execution_time_sec FLOAT NOT NULL,
	ps_info VARCHAR(255),
	command_output VARCHAR(255),
	FOREIGN KEY (test_id) REFERENCES tests (rowid)
		ON DELETE CASCADE
);

