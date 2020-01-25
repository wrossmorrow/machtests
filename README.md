
# Yen Tests

## Purpose 

Run easily maintanable and extensible collections of test scripts on the `yen` servers, ideally to identify problems on the servers before users do. 

## Why

The broad purpose of these tests is to _proactively_ assess the availability of software packages, software package setups (`module load`), local server and network file systems, on the Stanford GSB's "`yen`" research computing servers. By proactive we mainly intend for these tests to help us identify problems on the servers before users do. There are also some basic task executions as tests. 

## Contributing Tests

The testing system is designed so that _you don't need to know how the tests are actually run_ to write or edit a test. You just need to know what you want to test, and how package that in a `bash` script, and maybe edit some "front matter" to control test execution if you want. Our hope is that this makes contribution, maintenance, and debugging of the tests themselves easy, by abstracting away running infrastructure into a single script. 

## How Tests Run

Whatever tests are defined are run regularly in a `cron` job on each server. (A `systemd` timer would be better, and is included.) Test results are logged to `sqlite`, `S3`, and `influxdb` (or whichever are defined). Alerts can operate on top of either `S3` (using AWS Lambda) or over `influxdb` using `kapacitor`; we use `kapacitor`. 

## Test Results

Test results are always stored locally, on physical disk, in `csv` form. Locally storing results is important because the tests themselves test network filesystem availability, which is not something to take for granted. Ideally, these local test results could be periodically synced to network filesystems for replication, when those systems are available. But we should run tests and collect results regardless of their availability. 

Each row of the `csv` results has the following fields, in order: 

```
    datetime of test run,
    test runid (for a given run of test.sh),
    test name,
    status (i.e., pass/fail),
    timedout?,
    test script exit code,
    duration of test script run,
    error from test script run, if any,
    machine's  5m cpu usage at test start,
    machine's 10m cpu usage at test start,
    machine's 15m cpu usage at test start,
    memory used at test start,
    memory available at test start,
    processes running at test start, 
    processes defined at test start
```

## Dependencies

The tests and their running infrastructure should be lightweight. We require only `bash` and, optionally, 

* `sqlite3` software and starter database
* An AWS account, `S3` bucket and write credentials
* A machine/instance/cluster running `influxdb` and write credentials

should you choose to use any of these as result storage options. 

## Contributing to the Infrastructure

Ok, this is complicated. The infrastructure for running tests is really in one file, `test.sh`, for compactness if not simplicity. Some bleeds over into `.env` and `systemd` service files, but really it is all in `test.sh`. We explain this file in detail later in this readme. The file itself is, we hope, verbosely commented to assist in understanding the meaning of the code. 

# Installing yentests

## Getting the Code

First, clone the repo from Bitbucket, as usual. **Note:** the repo is already cloned and tracked on `IFS` at `/ifs/yentools/yentests`. 

If you want to play with the repo outside of the normal location, say in your home folder, you can do 

```
~$ git clone --single-branch --branch development git@bitbucket.org/circleresearch/yentests.git
```

This will, of course, create and populate a folder `~/yentests`. Note we clone the `development` branch, not the `master` branch. Reserve the `master` branch for production. 

**TODO:** It would be cool to have pushes to this repo run a pipeline to post the relevant parts of an installable repo to `S3` (or other) for download. Like a CDN. 

**TODO:** It might also be cool to create a simple webform that allowed (secure) entry of various running parameters, converted them to a `.env` file, and them packaged that into a download with the "CDN" version of the code. 

## Defining the Environment

We use a `.env` file to define key data needed by the actual test script. A template is provided as `.env.template`, because we shouldn't track the `.env` file in the repo. _It will have secrets you need to leave out of version control._ 

Here's a quick list of the variables the running infrastructure will make sense of from `.env`: 

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

See the comments in `.env.template` for more information and definitions. 

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

You should be able to run this without a `.env` file, if you can accept all the defaults. 

You can pass some options to the script to control its behavior: 

``` 
  Command line option flags: 

    h - print this message and exit. 
    r - reset locally-stored, monotonic run index. use with caution. 
    d - do a dry-run; that is, don't actually run any tests themselves
    v - print verbose logs for the tester
    l - store local results only
    s - store ONLY sqlite3 results (if configured)
    i - store ONLY influxdb results (if configured)
    w - store ONLY S3 results (if configured)
    L - do NOT store local results (delete after completion)
    S - do NOT store results in sqlite3 (even if configured)
    I - do NOT store results in influxdb (even if configured)
    W - do NOT store results in S3 (even if configured)

  Command line options with arguments: 

    t (string) - Specific list of test suites (folders) to run (comma separated, bash regex ok)
    e (string) - Specific list of test suites (folders) to exclude (comma separated, bash regex ok)
    R ([0-9]+) - Reset locally-stored, monotonic run index to a SPECIFIC value matching [0-9]+. Use with caution. 

```

These command line options will override settings in any `.env` file included. 

## What test.sh Does

More or less, `test.sh` runs scripts placed into subfolders of the `tests` directory. (This location could be generalized.) Each such subfolder is considered a "test suite"; for example, the included `isilon` test suite has a number of tests. 

More formally, the main `test.sh` script will search any _subfolder_ of `tests` and run

* a `tests/*/test.sh` file, if it exists
* any file matching `tests/*/tests/*.sh`; that is, any script in a `tests` subfolder of the test suite

This way "test suites" can be collected within such folders. If there is a "main" test, that should be defined in `test.sh`. More detailed tests can be defined in any file in `tests/*/tests` whose name ends with `.sh`. Adding a test then amounts to adding a file `newtest.sh` (or whatever) to `tests/*/tests`. It really should be that easy. 

Of course, the running infrastructure script `test.sh` has to _literally_ do quite a bit more than this to work correctly. Here are the major components of what the code actually does: 

### Setup Default Testing Environment

Read `.env` and prepare a "default" environment to be loaded for _any_ test in a file `.defaults`. 

### Load Correct Test Environment

Load variables defined in `.defaults` _and_ any test-suite-specific variables in `tests/*/.env`, should that exist. Also, parse the "frontmatter" of any test script to define or override variables that should be defined for any tests. 

### Run Monitored Tests

Actually run the included test scripts and monitor relevant system data about those runs. Right now we store test duration (execution time), total/average CPU utilization at test start time, and memory availability/usage _on the whole machine_s at test start time. It would also be good, though more resource intensive, to store CPU utilization and memory statistics for the test processes (and children) themselves. 

### Collect and Organize Output

Collect output like monitoring data, test exit code, test success/failure, and any error messages from failures. Organize this output into data structures suitable for loading into storage solutions (both local and remote).

### Load Data into Storage

Manage getting data into any local "databases" (files, `sqlite`) or remote storage (`S3`, `influxdb`). We should also allow syncing to `IFS`, notinng that this too is a "remote" file storage system. 

---

# Test Output



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

Our intent is that writing this package is to make contributing or editing tests easy. That is, to "front load" all the complexity into `tests.sh`. All you should be required to know how to do to contribute/edit a test is how to write a script that runs your test. 

## An Example


## Placement


## Frontmatter

You can, if you want, use frontmatter to define customizations to how a test script should run. Frontmatter items are included in comments in the test script, with `@_____` like codes. See `tests/matlab/tests/launch.sh` for example. 

Here is a list of the recognized frontmatter codes now: 

### `@name`

The name to use for the test. For `influxdb`, spaces will be replaced with underscores. This overrides the test script file name (sans extension). This is recorded in the logs and result data. 

### `@version`

A version number for the test. This is recorded in the result data. 

### `@description`

A brief description of the test. This is for commenting purposes only; the description does not affect how the tests are actually run. May be parsed for documentation, however, and is good practice to help others understand the test. 

### `@authors`

A list of test authors. This is for commenting purposes only; the authors do not affect how the tests are actually run. May be parsed for documentation, however. 

### `@timeout`

Specify a test-specific timeout (in seconds), or `none` for no timeout. _Run tests without a timeout with caution, they could interrupt the entire testing system if they hang._

### `@notimeout`

A shortcut for `@timeout none`. _Run tests without a timeout with caution, they could interrupt the entire testing system if they hang._

### `@skip`

Specification of when to run tests when _not_ running every time `test.sh` executes. By specifying a positive integer you specify how many cycles or runs are _skipped_; for example, `@skip 3` means that a particular test will run only every _fourth_ execution of `test.sh`, as determined by the monotonic run index. Specifying a positive decimal number less than one is interpreted as a probability; for example, `@skip 0.25` means that the test could run in _any_ execution but will, in the long run, run in only 75% of executions. 

### `@after`

A list of (comma-separated) pre-requisites from the same test suite. This enables tests to be "staged" as in a Directed Acyclic Graph. For example, you might want a test to be skipped if a certain other test fails; that is, run only if a particular other test succeeded. 

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

* Ferdi Evalle (no longer with Stanford)
* [W. Ross Morrow](morrowwr@stanford.edu)