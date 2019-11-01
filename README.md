
# Yen Tests

**Purpose:** Run easily maintanable and etensible collections of test scripts on the `yen` servers. 

**The Why:** The broad purpose of these tests is to _proactively_ assess the availability of software packages, software package setups (`module load`), local server and network file systems, on the Stanford GSB's "`yen`" research computing servers. There are also some basic task executions as tests. A _proactive_ assessment allows us to not only better understand our computing systems, but also to take action ahead of recieving user complaints. 

**Contributing:** Our testing system is designed so that _you don't need to know how the tests are actually run_ to write or edit a test. You just need to know what you want to test, and how package that in a `bash` script. Our hope is that this makes contribution, maintenance, and debugging of tests easy. 

**How Tests Run:** Whatever tests are defined are run regularly in a `cron` job on each server. Test results are logged to `sqlite`, `S3`, and `influxdb` (or whichever are defined). Alerts can operate on top of either `S3` (using AWS Lambda) or over `influxdb` using `kapacitor`; we use `kapacitor`. 

**Dependencies:** Our tests should be lightweight. We require only

* `bash`
* `sqlite3` software and starter database (if you want to use it)
* An AWS account, `S3` bucket and write credentials (if you want to use it)
* A machine/instance/cluster running `influxdb` (if you want to use it). 

# Installing yentests

## Getting the Code

Clone the repo from Bitbucket, as usual. **Note:** the repo is already cloned and tracked on the `yens` at `/ifs/yentools/yentests`. 

If you want to play with the repo outside of the normal location, say in your home folder, you can do 

```
~$ git clone --single-branch --branch development git@bitbucket.org/circleresearch/yentests
```

This will, of course, create and populate a folder `~/yentests`. Note we clone the `development` branch. 

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

## Installing yentests as a cron Job

Setup a `cron` job to run the tests each hour on each `yen` server.  Setup a different run schedule to prevent overlap with the same job on a different server to prevent tests accessing the `sqlite` database simultaneously which will cause an access error because `sqlite` is single threaded.

Set the enviroment in the `crontab` below. 

For example, tests on `yen1` starts at 0 minute mark of each hour

```
$ crontab -e
MAILTO=""
SHELL=/bin/bash
PATH=/home/users/<user>/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/ifs/yentools/bin
0 */1 * * * /ifs/yentools/yentests/test.sh
```

For example, tests on `yen2` starts at the 15 minute mark of each hour

```
$ crontab -e
MAILTO=""
SHELL=/bin/bash
PATH=/home/users/<user>/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/ifs/yentools/bin
15 */1 * * * /ifs/yentools/yentests/test.sh
```

`yen3` is setup to run at 30 min and `yen4` at 45 min.

## Installing yentests as a Scheduled systemd Unit

We can use `systemd` timers to run the `yentests` on a schedule. Prototypes are provided in the `service` folder. 



--- 

# Test Infrastructure



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

## What test.sh Does

The main `test.sh` script will search any _subfolder_ of `tests` and run

* `tests/*/test.sh` file, if it exists
* any file matching `tests/*/tests/*.sh`

This way test "suites" can be collected within such folders. If there is a "main" test, that can be defined in `test.sh`. More detailed tests can be defined in any file in `tests` whose name ends with `.sh`. Adding a test then amounts to adding a file `newtest.sh` (or whatever) to `tests`. 

Of course, `test.sh` has to _literally_ do quite a bit more than this to work correctly. Here are the major components of what the code actually does: 

### Setup Default Testing Environment

Read `.env` and prepare a "default" environment to be loaded for any test in a file `.defaults`. 

### Load Correct Test Environment

Load variables defined in `.defaults` _and_ any test-suite-specific variables in `tests/*/.env`. Also, parse the frontmatter of any test script to define or override variables that should be defined for any tests. 

### Run Monitored Tests

Actually run the scripts and monitor relevant system data about those runs. Right now we just store test duration (execution time), but we should also store total/average CPU utilization and maximum memory usage for each test process (and any of its children).  

### Collect and Organize Output

Collect output like monitoring data, test exit code, test success/failure, and any error messages from failures. Organize this output into data structures suitable for loading into storage solutions (both local and remote).

### Load Data in Storage

Manage getting data into any local "databases" (files, `sqlite`) or remote storage (`S3`, `influxdb`). 

---

# Test Output

Each test will output

1. Folder location of the test
2. Command being tested
    1. execution status : SUCCESS or FAILURE
    2. Exit Code
        1. 0 is command successfully executed
        2. Non-0 will be an error
    3. Whether test timed out (0/1)
    4. Execution time in seconds
    5. any error messages
3. Indicator the test record was stored in the database both Sqlite and InfluxDB

## Logs


## Results

A daily results file in `csv` format is created, whose columns are
```
datetime , run id , test name , S/F , exit code , timeout? , duration , cpu (TBD) , mem (TBD)
```

## sqlite



## AWS S3

If credentials and settings are provided, upload the `csv` data to `S3`. 

## influxdb

Data from the `yens` is shipped to our `influxdb` monitoring instance, `monitor.gsbdarc.com`. Specifically: 

* Database: `yentests`
* Mesurement: `yentests`
* Tags: 
    * `test`: name of the test script
    * `hash`: `SHA256` hash of the test script
    * `tver`: declared version number of the test
    * `host`: machine test was run on
    * `fail`: boolean taking the value "true" if the test failed
    * `tout`: boolean taking the value "true" if the test timed out
    * `code`: integer exit code for the test
* Fields: 
    * `runid`: the test run index (for that machine)
    * `xtime`: the test's execution time
    * `cpu05`, `cpu10`, `cpu15`: the 5-, 10-, and 15-minute averaged CPU utilization on the system when the test started
    * `memu`, `mema`: the used and available memory (RAM and swap) when the test started
    * `rprocs`, `nprocs`: the number of running and total processes when the test started
*  `time`: the _start_ time of the test, at second precision

---

# Changing or Contributing Tests

Our intent is that writing tests should be easy. All you should really know how to do is write a script (on top of how to use `git` that is). 

## An Example


## Placement


## Frontmatter

### `@name`

The name to use for the test. For `influxdb`, spaces will be replaced with underscores. 

### `@version`

A version number for the test. 

### `@description`

A brief description of the test. This is for commenting purposes only; the description does not affect how the tests are actually run. May be parsed for documentation, however. 

### `@authors`

A list of test authors. This is for commenting purposes only; the authors do not affect how the tests are actually run. May be parsed for documentation, however. 

### `@timeout`

Specify a test-specific timeout (in seconds), or `none` for no timeout. Run tests without a timeout with caution. 

### `@notimeout`

A shortcut for `@timeout none`. Run tests without a timeout with caution. 

### `@skip`

Specification of when to run tests when _not_ running every time the tests code executes. By specifying a positive integer you specify how many cycles or runs are _skipped_; for example, `@skip 3` means that a particular test will run only every _fourth_ execution of the testing code. Specifying a positive decimal number less than one is interpreted as a probability; for example, `@skip 0.25` means that the test could run in any execution but will, in the long run, run in only 75% of executions. 

### `@after`

A list of (comma-separated) pre-requisites from the same test suite. 


## Incorporating Your Changes


---

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