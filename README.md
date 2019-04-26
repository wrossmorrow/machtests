# Yen Tests

Test the software packages, software package setup prerequisite, local server and network file systems on the Stanford Yen servers.
The script is run in cronjob on each seaver and test results are logged to sqlite and InfluxDB which is part of the TICK stack and monitored in a Chronograph dashboard.

### Prerequisites

Unix Bash
[Unix Module Enviroment Software](http://modules.sourceforge.net/)
Module System Setup Profile at ***/etc/profile.d/lmod.sh***

Sqlite3 software and starter database

InfluxDB where results are written using POST verb in CURL command


### Installing

Pull the repo from Bitbucket

Create the sqlite database and tables using a script
```
$ cd <yentests home>/db_scripts
$ ./create_db.sh
```

Check the sqlite database file exists
```
$ cd <yentests home>/db_scripts
$ ls -1 yentests.db
yentests.db
```

Check the database tables
```
$ sqlite3 yentests.db
SQLite version 3.22.0 2018-01-22 18:45:57
Enter ".help" for usage hints.
sqlite> .tables
test_results  tests
sqlite> .schema tests
CREATE TABLE tests (
        server VARCHAR(30) NOT NULL,
        test_date DATE NOT NULL,
        ps_info VARCHAR(255)
);
sqlite> .schema test_results
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
sqlite> .exit
```

Installing CRON jobs
Setup a CRON job to run the tests each hour on each Yen server.  Setup a different run schedule to prevent overlap with the same job on a different server to prevent tests accessing the sqlite database simultaneously which will cause an access error because sqlite is single threaded.
Set the enviroment in the crontab below
```
For example, tests on Yen1 starts at 0 minute mark of each hour
$ crontab -e
MAILTO=""
SHELL=/bin/bash
PATH=/home/users/<user>/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/ifs/yentools/bin
0 */1 * * * /ifs/yentools/yentests/test.sh

For example, tests on Yen2 starts at the 15 minute mark of each hour
$ crontab -e
MAILTO=""
SHELL=/bin/bash
PATH=/home/users/<user>/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/ifs/yentools/bin
15 */1 * * * /ifs/yentools/yentests/test.sh

Yen 3 is setup to run at 30 min and Yen 4 at 45 min.
```

## Running the tests

Run the test.sh script in the yentests folder.  The test script will look for and run the test.sh file in each sub-folder which is a specific test.
At the beginning of the test, a test record id will be generated which links all the tests in that run in the database.
The specifics of each test will be in the **test.sh** file in the different sub-folders.

Each test will output
1. Folder location of the test
2. Command being tested
    1. execution status : SUCCESS or FAILURE
    2. Exit Code
        1. 0 is command successfully executed
        2. Non-0 will be an error
    3. Execution time in seconds
3. Indicator the test record was stored in the database both Sqlite and InfluxDB

```
fevalle@yen1:/ifs/yentools/yentests$ ./test.sh
Test Record ID = 536

R/
Testing: module load R ==> SUCCESS | 0 | 0.13 sec
storeTestRecord
Testing: Rscript /usr/local/ifs/yentools/yentests/R/test.r ==> SUCCESS | 0 | 0.75 sec
storeTestRecord

db_scripts/

gurobi/
Testing: module load gurobi ==> SUCCESS | 0 | 0.07 sec
storeTestRecord
Testing: /software/non-free/Gurobi/gurobi801/linux64/bin/gurobi.sh /usr/local/ifs/yentools/yentests/gurobi/test.py ==> SUCCESS | 0 | 2.50 sec
storeTestRecord

isilon/
Testing: ls -l /ifs/yentools/yentests/isilon ==> SUCCESS | 0 | 0.59 sec
storeTestRecord

julia/
Testing: module load julia ==> SUCCESS | 0 | 0.05 sec
storeTestRecord
Testing: julia -e "exit()" ==> SUCCESS | 0 | 0.27 sec
storeTestRecord

local_server_folder/
Testing: ls -la /tmp ==> SUCCESS | 0 | 0.01 sec
storeTestRecord

mathematica/
Testing: module load mathematica ==> SUCCESS | 0 | 0.05 sec
storeTestRecord
Testing: wolframscript -script /usr/local/ifs/yentools/yentests/mathematica/test.m ==> SUCCESS | 0 | 1.57 sec
storeTestRecord

matlab/
Testing: module load matlab ==> SUCCESS | 0 | 0.05 sec
storeTestRecord
Testing: matlab -nodisplay -nosplash -nodesktop -batch "exit" ==> SUCCESS | 0 | 23.59 sec
storeTestRecord

stata-mp/
Testing: module load statamp ==> SUCCESS | 0 | 0.05 sec
storeTestRecord
Testing: stata-mp -b /usr/local/ifs/yentools/yentests/stata-mp/test.do ==> SUCCESS | 0 | 0.07 sec
storeTestRecord

stata-se/
Testing: module load statase ==> SUCCESS | 0 | 0.06 sec
storeTestRecord
Testing: stata-se -b /usr/local/ifs/yentools/yentests/stata-se/test.do ==> SUCCESS | 0 | 0.20 sec
storeTestRecord
fevalle@yen1:/ifs/yentools/yentests$

```

## Dashboard Test Monitoring
A Chronograph dashboard called [Yen Test](http://monitor.gsbrss.com:8888/sources/1/dashboards/9?lower=now%28%29%20-%2012h) monitors the tests on each server.  Any results displayed in the graph are errors and should be investigated.
