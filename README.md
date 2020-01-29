
# Yen Tests

## Purpose 

Run easily maintanable and extensible collections of test scripts on the `yen` servers. 

## Why

The broad purpose of these tests is to _proactively_ assess the availability of software packages, software package setups (`module load`), local server and network file systems, on the Stanford GSB's "`yen`" research computing servers. By proactive we mainly intend for these tests to help us _identify problems on the servers before users do_. 

## Contributing Tests

The testing system is designed so that _you don't need to know how the tests are actually run_ to write or edit a test. You just need to know what you want to test, and how package that in a `bash` script, and maybe edit some "front matter" to control test execution if you want. Our hope is that this makes contribution, maintenance, and debugging of the tests themselves easy, by abstracting away running infrastructure into a single script. 

For a bit of motivation on this point, let's look at a simple `ls /tmp` test to evaluate (a trivial) access to the local filesystem. In the original set of `yentests`, this was the script to do this: 

```
#!/bin/bash 
script_home=$( dirname $(realpath 0$) )
source $script_home/../env.sh
software="Local Server Folder"
testCommand "ls -la /tmp"
storeTestRecord "$software" "$input_cmd" "$exit_code" "$cmd_output" "$time_real"
```

In the setup enabled here, in this package, this script accomplishes the same goal: 

```
#!/bin/bash
ls -al /tmp
```

This illustrates our goal: _to contribute a test, all you have to know is how to write the test_. 

While you only _have_ to know how to script your test to contribute a test, you can do alot here to control how your test runs with "frontmatter". This is described in more detail below. But, in brief, frontmatter will let you: 

* customize the name of your test
* provide a version number for your test
* provide a description of the test
* list the test's authors
* set, change, or eliminate the timeout used for the test
* run the test only in certain test cycles, or with a specified probability
* specify prerequisites from the same test suite, making executions follow a [Directed Acyclic Graph](https://en.wikipedia.org/wiki/Directed_acyclic_graph) pattern

For example, say we want the name "Local Server Folder" to be applied to the test the above. To wit: 

```
#!/bin/bash
# @name Local Server Folder
ls -al /tmp
```

## Drafting Your Tests

One important frontmatter tag is `@draft`. If `test.sh` is run with the flag `-p`, it will run only those scripts _without_ such a tag (and the scheduled jobs include `-p`). We recommend including this in your frontmatter until you are _sure_ that you want the test you're writing to be including in the scheduled, production runs. You can run only the scripts with `@draft` in their frontmatter by passing the `-P` flag to `test.sh`. 

## Running Scheduled Tests "in Production"

Whatever tests are defined are run regularly in a `cron` job on each server. (A `systemd` timer would be better, and is included.) Test results are always stored locally, and can additionally be logged to `sqlite`, `S3`, and `influxdb` (whichever are defined). Alerts can operate on top of either `S3` (using AWS Lambda) or over `influxdb` using `kapacitor`; we use `kapacitor`. 

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

* `sqlite3` software (with a starter database)
* An AWS account, `S3` bucket and write credentials
* A machine/instance/cluster running `influxdb` and write credentials

should you choose to use any of these as result storage options. 

## Contributing to the Infrastructure

Ok, this is complicated. The infrastructure for running tests is really in one file, `test.sh`, for compactness if not simplicity. Some bleeds over into `.env` and `systemd` service files, but really it is all in `test.sh`. We explain this file in detail later in this readme. The file itself is, we hope, verbosely commented to assist in understanding the meaning of the code. 

# Installing yentests

## The "Production" Install

Right now, the `yentests` are installed at `/ifs/yentools/yentests`. This is a temporarily functional but ultimately terrible place for them to be installed. Part of the desired test suite tests the _very availability and functionality_ of `IFS`, and thus the test suites _cannot themselves be installed in_ `IFS`. 

The "right" place to install them would be locally on any given machine, such as in `/etc/yentests` on every `yen`. Then the `yentests` can run, store, and report data regardless of the availability or functionality of `IFS`. Moreover, the tests can report on that availability and/or functionality. 

## Getting the Code

Should you want the code, clone the repo from Bitbucket, as usual. **Note:** the repo is already cloned and tracked on `IFS` at `/ifs/yentools/yentests`. 

If you want to play with the repo outside of the normal location, say in your home folder, you can do 

```
~$ git clone --single-branch --branch development git@bitbucket.org:circleresearch/yentests.git
```

This will, of course, create and populate a folder `~/yentests`. Note we clone the `development` branch, not the `master` branch. We should reserve the `master` branch for production. 

**TODO:** It would be cool to have pushes to this repo run a pipeline to post the relevant parts of an installable repo to `S3` (or other) for easier download. Like a CDN. 

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

See the comments in `.env.template` for more information, including definitions and defaults (if any). 

**TODO:** It could be useful to have a script that helps create this `.env` file based on command line inputs from the user. 

## Creating The sqlite3 Database

**NOTE:** this is old documentation from the original versions of the tests. 

**TODO:** Make this a scripted component of running `test.sh`, as are the checks on InfluxDB or `S3` uploads. 

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

## Installing `yentests` as a `cron` Job

We can install a `cron` job to run the tests each hour (or each half hour, or each 15 minutes etc) on each `yen` server. Care should be taken that _the interval chosen does not produce overlapping test runs_ (on a single machine). That is, if tests take a minute, we should not try to run them every 30 seconds. 

If using `sqlite3` with a database on the `IFS` system, these scheduled tests will need to run on a staggered schedule to prevent collisions in accessing the `sqlite` database. However, this problem is alleviated should we use a machine-specific `sqlite3`database. In fact, we should store locally anyway: if `IFS` is unavailable, a database on `IFS` is not useful. This obviates the need to consider database write collisions. 

We can, and do, keep a staggered schedule for other reasons though. A staggered schedule means that perhaps we get a better portrait of usage across the `yen`s over a given period, and also maybe means that we aren't imposing on all research computing activity at the same time when running the tests. As of now, tests on `yen1` starts at 0 minute mark of each hour, and have the `crontab` entry: 

```
$ crontab -e
MAILTO=""
SHELL=/bin/bash
PATH=/home/users/<user>/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/ifs/yentools/bin
0 */1 * * * /ifs/yentools/yentests/test.sh
```

Tests on `yen2` starts at the 15 minute mark of each hour

```
$ crontab -e
MAILTO=""
SHELL=/bin/bash
PATH=/home/users/<user>/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/ifs/yentools/bin
15 */1 * * * /ifs/yentools/yentests/test.sh
```

`yen3` is setup to run at 30 min and `yen4` at 45 min.

We also have to set the enviroment correctly for a `cron` job to run. This is accomplished by having `cron` run the simple wrapper script `/ifs/yentools/yentests/test.sh`: 

```
#!/bin/bash
cd /ifs/yentools/yentests/development
# this export needed to support cron job
export PATH="${PATH}:/usr/local/sbin:/usr/local/bin:/usr/sbin:/sbin:/bin:/ifs/yentools/bin"
bash test.sh -p
```

Note the append of `/ifs/yentools/bin` to the `PATH` which would exist for a user, _but does not exist for a_ `cron` _job_. We should run the tests with an environment as close as possible to that of a real user. Note also the flag `-p`, which specifies that only "production" test scripts lacking a `@draft` frontmatter tag should be run. 

## Installing yentests as a Scheduled systemd Unit

We can use `systemd` timers to run the `yentests` on a schedule. Prototypes are provided in the `service` folder. 

TBD

--- 

# Test Infrastructure

A primary goal of this package is to "frontload" running complexity to make it as easy as possible to create and include new tests. This frontloading is embodied in `test.sh`, a script that indeed has a fair bit of complexity. This is all (hopefully) addressed below. 

## Running By Hand

You can run the `yentests` by hand by running the `test.sh` script in the `/ifs/yentools/yentests` folder: 

```
$ cd /ifs/yentools/yentests && ./test.sh
```

You should be able to run this without a `.env` file, if you can accept all the defaults. Naturally, you can also pass some options to the script to control its behavior. Here's most of what the help will print: 

``` 
  Command line option flags: 

    h - print this message and exit. 
    r - reset locally-stored, monotonic run index. use with caution. 
    d - do a dry-run; that is, don't actually run any tests themselves
    p - run only \"production\" tests, those WITHOUT a \"@draft\" frontmatter tag
    v - print verbose logs for the tester
    l - store local results only (ignore all remote uploads)
    s - store ONLY sqlite3 results (if configured)
    i - store ONLY influxdb results (if configured)
    w - store ONLY S3 results (if configured)
    P - opposite of -p, run \"@draft\" tests only
    D - keep .defaults file, so that it can be reviewed outside of a particular run
    E - write out a .env-tests file for the run, so it can be reviewed
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

More or less, `test.sh` runs scripts placed into subfolders of the `tests` directory. (This location could, of course, be generalized with a `.env` variable or command line argument.) Each such subfolder is considered a "test suite"; for example, the `tests/isilon` test suite has a number of tests. 

More formally, the main `test.sh` script will search any _subfolder_ of `tests` and run

* a `tests/*/test.sh` file, if it exists
* any file matching `tests/*/tests/*.sh`; that is, any script in a `tests` subfolder of the test suite itself

This way "test suites" can be collected within such folders. If there is a "main" test, that should be defined in `tests/*/test.sh` which will _always_ run _first_. More detailed tests can be defined in any file in `tests/*/tests` whose name ends with `.sh`. Adding a test then amounts to adding a file `newtest.sh` (or whatever) to `tests/*/tests`. It really should be that easy. 

Moreover, some tests have dependencies. Take `tests/mathematica` for example. This test suite has a script to run, `tests/mathematica/test.m` (note: _not_ `.sh`). If you look into `tests/mathematica/tests/runscript.sh`, you'll see a reference to this script. This is the pattern we adopt for dependencies: place them in the test suite folder (like `tests/mathematica`), so long as they aren't named `test.sh`. All test scripts, even if in `tests/*/tests`, will run as if from `tests/*` and thus these dependencies should be available. 

Of course, the running infrastructure script `test.sh` has to _literally_ do quite a bit to work correctly. Here are the major components of what the code actually does: 

### Defines Utility Functions

There is a large section at the top of the file where utility functions and other routines are defined. The comments in the code should explain what they do. (And if they don't, you're welcome to fix them!)

### Setup Default Testing Environment

Read `.env` and prepare a "default" environment to be loaded for _any_ test, and store that (1) in the "global" environment, for values constant over all tests, using `export` and (2) in a file `.defaults` for values that might be overridden in particular tests or test suites. 

### Load Correct Test-Specific Environment

Load variables defined in `.defaults` _and_ any test-suite-specific variables in `tests/*/.env`, should that exist at runtime. Also, parse the "frontmatter" of any particular test script to define or override variables that are expected or appropriate for particular tests. 

### Run Monitored Tests

Actually run the included test scripts and monitor relevant system data about those runs. Right now we store test duration (execution time), total/average CPU utilization at test start time, and memory availability/usage _on the whole machine_ at test start time. 

It would also be good, though more resource intensive, to store CPU utilization and memory statistics for the test processes (and children) themselves. Perhaps this can be an overridable option. Moreover, this shouldn't be done for very fast tests. It would probably only make sense to collect such data for tests that take many seconds or minutes, not sub-second tests. 

**TODO:** Write a function in `test.sh` to collect, at a higher frequency than the test run, and only for "long running tests", CPU and memory statistics for the actual execution of a test script and all its children. Incorporate these data into the result outputs and uploads. 

### Collect and Organize Output

Collect output like monitoring data, test exit code, test success/failure, and any error messages from failures. Organize this output into data structures suitable for loading into storage solutions (both local and remote).

### Load Data into Storage

Manage getting data into any local "databases" (files, `sqlite`) or remote storage (`S3`, `influxdb`). We should also allow syncing to `IFS`, noting that this too is a "remote" file storage system. 

**TODO:** Write options and code to replicate result data to `IFS` if the connection is live. 

---

# Test Output

INTRO TBD

## Logs

TBD

## Results

A machine-specific results file in `csv` format is created, whose columns are
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
(as listed above). These are stored at `${YENTESTS_TEST_RESULTS}.csv`. Here is some example data: 

```
2020-01-26T10:57:28.258128718,2071,launch julia,P,false,0,0.41,,23.26,21.55,21.05,126485960,1458784276,27,1772
2020-01-26T10:57:29.204669796,2071,ml julia,P,false,0,0.07,,23.26,21.55,21.05,126357140,1458913096,13,1772
2020-01-26T10:57:29.820703297,2071,Local Server Folder,F,true,143,5,,23.26,21.55,21.05,125962220,1459308016,13,1772
2020-01-26T10:57:35.403218324,2071,ml mathematica,P,false,0,0.07,,22.43,21.40,21.01,126334428,1458935808,13,1772
2020-01-26T10:57:36.110070604,2071,run mathematica,P,false,0,1.50,,22.43,21.40,21.01,126269308,1459000928,13,1772
2020-01-26T10:57:38.324330797,2071,launch matlab,P,false,0,16.82,,21.68,21.26,20.97,127029012,1458241224,13,1772
```

**TODO:** figure out a rotation scheme for these files, so that they don't grow indefinitely. Compress "old" result files. 

## sqlite3

Here are the environment variables that have to be defined to use `sqlite3`: 

```
YENTESTS_SQLITE_DB=
YENTESTS_SQLITE_FILE=
```

The existence of the db, file, and tables will be tested before attempting any writes. Ideally, these will be created if they don't exist. 

**TODO:** This. Adapt `sqlite3` stuff to new tests. 

## AWS S3

If AWS credentials and settings are provided for `S3`, upload the `csv` data to `S3`. 

Here are the environment variables that have to be defined to use `S3`: 
```
YENTESTS_S3_ACCESS_KEY_ID=
YENTESTS_S3_SECRET_ACCESS_KEY=
YENTESTS_S3_BUCKET=
YENTESTS_S3_PREFIX=
``` 
The connection defined will be tested before attempting any writes. 

Writes to `S3` are done in "batch" fashion after all tests run. If a test hangs (absent a timeout), or if a test takes a long time (absent a timeout stopping it), that will delay the upload to `S3`. 

## InfluxDB

Data from the `yens` is shipped to our `influxdb` monitoring instance, `monitor.gsbdarc.com`. But you could change the host with a setting in `.env`. Specifically we write following: 

* Database: `yentests`
* Measurement: `yentests`
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

We distinguish these categories -- Measurement, Tags, Fields, and time -- as they are relevant to InfluxDB. Measurements are a bit like tables, tags are parts of the data that are automatically indexed, fields are non-indexed data, and time is always a distinct entity in a time series database like InfluxDB. Data that are indexed are efficiently searchable, and we can use `group by` like operations on them. Fields are more like data that we want to plot or aggregate. 

Here are the environment variables that have to be defined to use InfluxDB: 
```
YENTESTS_INFLUXDB_HOST=
YENTESTS_INFLUXDB_PORT=
YENTESTS_INFLUXDB_DB=
YENTESTS_INFLUXDB_USER=
YENTESTS_INFLUXDB_PWD=
```
The connection defined will be tested before attempting any writes. 

Like `S3` uploads, writes to InfluxDB are done in "batch" fashion after all tests run. If a test hangs (absent a timeout), or if a test takes a long time (absent a timeout stopping it), that will delay ingestion into InfluxDB. 

---

# Changing or Contributing Tests

Our primary intent is that writing this package (as opposed to its predecessor, or other approaches) is to make contributing or editing tests as easy as possible. That is, to "frontload" all the complexity into `tests.sh` which, ideally, test contributors can ignore. All you should be _required_ to know how to do to contribute/edit a test is how to write a script that runs your test. We address the added feature of test script frontmatter below; frontmatter will allow contributors to control test script execution without having to understand or manipulate `test.sh`. 

## An Example, with Placement

This is an example of how a test could be written and placed in a location suitable for automated execution. 

Suppose we want to time how long it takes `matlab` to solve a random linear system, as a partial gauge of system performance. How would we do that? 

Well, we would want to create a new file, say `tests/matlab/tests/solve.sh`. Note the new file would go in the `tests` folder, under the `tests/matlab` test suite, as one of its executables in `tests/matlab/tests`. We could also include a dependency `tests/matlab/solve_rand_Axeb.m`, with the code
```
function [] = solve_rand_Axeb( N )
    x = rand( N , N ) \ rand( N , 1 )
end 
```
Note the dependency goes in `tests/matlab`, not `tests/matlab/tests`. We would then edit `tests/matlab/tests/solve.sh` to be, say,  

```
#!/bin/bash
# @draft
matlab -r "solve_rand_Axeb(1000); exit"
```

_And that's it._ This inversion test should run on the next invocation of `test.sh`, and the test duration (minus `matlab` load time, which another test estimates) would estimate for us the inversion time (ignoring random matrix generation time, which is likely small compared to inversion time). To check this, we could just execute `./test.sh -v` from the repo's root directory. 

I did this (removing these files afterward), and observed the results to contain a new line for this new test:
```
2020-01-26T10:57:38.324330797,2071,launch matlab,P,false,0,16.82,,21.68,21.26,20.97,127029012,1458241224,13,1772
2020-01-26T10:57:55.698130870,2071,ml matlab,P,false,0,0.06,,19.67,20.84,20.83,127448860,1457821376,13,1774
2020-01-26T10:57:56.329430146,2071,tests/matlab/tests/solve.sh,P,false,0,16.75,,19.67,20.84,20.83,127006220,1458264016,13,1774
```

Note the "full" path script name listed as the test name. That's the default, used because we didn't include a `@name` frontmatter tag like we do in the other `matlab` tests. Note though that we _do_ include `@draft`, as recommended. 

**EXERCISE:** Replicate this example, verifying it has worked using the logs or the results. Then extend the example to include a `@name`, and check again. 

## Frontmatter

You can, if you want, use frontmatter to define customizations to how a test script should run. Frontmatter items are included in comments in the test script, with `@_____` like codes. See `tests/matlab/tests/launch.sh` for example. 

Here is a list of the recognized frontmatter codes: 

### `@name`

The name to use for the test. For InfluxDB, spaces will be replaced with underscores. This overrides the test script file name (sans extension). This is recorded in the logs and result data. 

### `@version`

A version number for the test. This is recorded in the result data. Note: a hash of the test script is also included in the test results, so that all test script change events (but not particular changes at the `diff` level) are "tracked" regardless of the version number. 

### `@description`

A brief description of the test. This is for commenting purposes only; the description does not affect how the tests are actually run. May be parsed for documentation, however, and is good practice to help others understand the test. 

### `@authors`

A list of test authors. This is for commenting purposes only; the authors do not affect how the tests are actually run. May be parsed for documentation, however. 

### `@draft`

A flag to denote that this test script is a "draft". Drafts tests can be left out of any execution with the `-p` flag, or _only_draft_ tests can be included in a test run with the `-P` flag. _Draft tests will have results printed to the logs only_, not written to `CSV` on disk, `IFS`, `sqlite3`, `S3`, or InfluxDB. 

### `@timeout`

Specify a test-specific timeout (in seconds), or `none` for no timeout. _Run tests without a timeout with caution, they could interrupt the entire testing system if they hang._

### `@notimeout`

A shortcut for `@timeout none`. _Run tests without a timeout with caution, they could interrupt the entire testing system if they hang._

### `@skip`

Specification of when to run tests when _not_ running every time `test.sh` executes. By specifying a positive integer you specify how many cycles or runs are _skipped_; for example, `@skip 3` means that a particular test will run only every _fourth_ execution of `test.sh`, as determined by the monotonic run index. Specifying a positive decimal number less than one is interpreted as a probability. For example, `@skip 0.25` means that the test _could_ run in _any_ execution but will be skipped in any given run with 25% probability; that is, in the long run, the test will run in only 75% of executions. 

### `@after`

A list of (comma-separated) pre-requisites _from the same test suite_. This enables tests to be "staged" as in a Directed Acyclic Graph. For example, you might want a test to be skipped if a certain other test fails; that is, run only if a particular other test succeeded. pre-requisites should be specified by the test name. 

## Incorporating Your Changes into Production

PROCESS TBD

---

# Test Monitoring

## Dashboard

A Chronograph dashboard called [Yen Test](http://monitor.gsbrss.com:8888/sources/1/dashboards/9?lower=now%28%29%20-%2012h) monitors the tests on each server. Any results displayed in the graph are errors and should be investigated. Obviously this requires uploading data to InfluxDB. 

## Alerts

Alerts should be triggered when certain adverse conditions are met; particular adverse conditions of note are described below. 

Local alerting could be managed with a companion `cron` job or `systemd` timer running a script on each `yen`, or with an addition to the postprocessing functionality in `test.sh`. Such a companion service/code would need to scan the results and send emails or post Slack messages when adverse conditions arise. 

We prefer using `kapacitor` for alerting. Obviously this requires uploading data to InfluxDB. This manages alerting through [tick scripts]. Similar functionality could be achieved in `S3` using [Lambda functions](https://aws.amazon.com/lambda/). Such a function would watch the result bucket for new uploads, parse those uploads, and then send alerts upon identification of adverse conditions. 

Remote alerting is perhaps preferable to local alerting because (1) it takes workload off of the `yen` servers, which are actively used for research, and (2) can analyze conditions _across_ the `yen`s, not just on _any single_ `yen`. While we are not currently exploiting that, we might in the future. Say, perhaps we want to issue an alert should _all_ the `yen`s be running slowly, but not if any single one is. 

Note that remote alerting could also mean using `IFS`. A companion service (not, I think, an addition to `test.sh`) would need to scan results _replicated to_ `IFS` and send emails or post Slack messages when adverse conditions arise. 

### Adverse Conditions

Here is a list of the adverse conditions we (should) monitor: 

TBD

---

# Contact

You can contact the DARC team [via email](gsb_darcresearch@stanford.edu). 

Authors: 

* Ferdi Evalle (no longer with Stanford)
* [W. Ross Morrow](morrowwr@stanford.edu)