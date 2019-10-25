
# Yen Tests

Run easily maintanable and etensible collections of test scripts on the `yen` servers. 

The broad purpose of the tests is to test availability of software packages, software package setups (`module load`), local server and network file systems on the Stanford Yen servers. There are also some basic task executions as tests. 

The system is designed so that you don't need to know how the tests are actually run to write a test. You just need to know what you want to test and package that in a `bash` script. Our hope is that this makes contribution and debugging of tests easy. 

The tests are run regularly in a `cron` job on each server. Test results are logged to `sqlite`, `S3`, and `influxdb`. Alerts can operate on top of either `S3` (using AWS Lambda) or over `influxdb` using `kapacitor`. We use `kapacitor`. 

### Dependencies

* `bash`
* `sqlite3` software and starter database (if you want to use it)
* An AWS account, `S3` bucket and write credentials (if you want to use it)
* A machine/instance/cluster running `influxdb`. 

# Installing yentests

## Getting the Code

Clone the repo from Bitbucket, as usual. 

The repo is already cloned and tracked on the `yens` at `/ifs/yentools/yentests`. 

If you want to play with the repo outside of the normal location, say in your home folder, you can do 

```
~$ git clone --single-branch --branch development git@git.bitbucket.org/circleresearch/yentests
```

This will, of course, create and populate a folder `~/yentests`. 

## Defining the Environment

We use a `.env` file to define key data needed by the actual test script. A template is provided as `.env.template`, because you shouldn't track the `.env` file. It will have secrets you need to leave out of version control. 

Here's a quick list of the variables you can define in `.env`: 

```
YENTESTS_TEST_LOGS=
YENTESTS_TEST_HOST=
YENTESTS_TEST_RIDF=
YENTESTS_TEST_TIMEOUT=
YENTESTS_TEST_RESULTS=
YENTESTS_HASH_LOG=
YENTESTS_RUN_LOG=
YENTESTS_SQLITE_DB=
YENTESTS_SQLITE_FILE=
YENTESTS_S3_ACCESS_KEY_ID=
YENTESTS_S3_SECRET_ACCESS_KEY=
YENTESTS_S3_BUCKET=
YENTESTS_S3_PREFIX=
YENTESTS_INFLUXDB_HOST=
YENTESTS_INFLUXDB_PORT=
YENTESTS_INFLUXDB_DB=
YENTESTS_INFLUXDB_USER=
YENTESTS_INFLUXDB_PWD=
```

See the comments in `.env.template` for more information. 

## Creating the sqlite3 database

Create the `sqlite` database and tables using a script
```
$ cd ${YENTESTS_TEST_HOME}/db_scripts
$ ./create_db.sh
```

Check the sqlite database file exists
```
$ cd ${YENTESTS_TEST_HOME}/db_scripts
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

## Installing yentests as a cron job

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



# About

## Running By Hand

You can run the `yentests` by hand by running the `test.sh` script in the `/ifs/yentools/yentests` folder: 

```
$ cd /ifs/yentools/yentests && ./test.sh
```

You can pass some flags to the script to control its behavior

``` 
-h: print help and exit
-r: reset run ids
-d: dryrun tests; that is, just setup for each test but don't actually run any of them
-v: make verbose prints to the logs
-l: "local only", meaning no S3 or influxdb (even if defined)
-w: "web only", meaning no sqlite (even if defined)
-S: Do not write data to sqlite, even if defined
-A: Do not send data to S3, even if defined
-I: Do not send data to influxdb, even if defined
```

## What test.sh does

The main `test.sh` script will search any _subfolder_ of `tests` and run

* `tests/*/test.sh` file, if it exists
* any file matching `tests/*/tests/*.sh`

This way




# Test Output

Each test will output

1. Folder location of the test
2. Command being tested
    1. execution status : SUCCESS or FAILURE
    2. Exit Code
        1. 0 is command successfully executed
        2. Non-0 will be an error
    3. Execution time in seconds
3. Indicator the test record was stored in the database both Sqlite and InfluxDB

## Logs

A daily results file in `csv` format is created, whose columns are
```
datetime , run id , test name , S/F , exit code , timeout? , duration
```

## sqlite


## AWS S3

If credentials and settings are provided, upload the `csv` data to `S3`. 

## influxdb



# Changing or Contributing Tests

Our intent is that writing tests should be easy. All you should really know how to do is write a script (on top of how to use `git` that is). 

## An Example


## Placement


## Frontmatter


## Incorporating Your Changes



# Test Monitoring

## Dashboard

A Chronograph dashboard called [Yen Test](http://monitor.gsbrss.com:8888/sources/1/dashboards/9?lower=now%28%29%20-%2012h) monitors the tests on each server. Any results displayed in the graph are errors and should be investigated.

## Alerts

We use `kapacitor` for alerting. 



# Contact

You can contact the DARC team [via email](gsb_darcresearch@stanford.edu). 

Authors: 

* Ferdi Evalle 
* [W. Ross Morrow](morrowwr@stanford.edu)