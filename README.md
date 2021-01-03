# NAME

TAP::Harness

# DESCRIPTION

An asynchronous TAP framework written in Raku.

# prove6

This module provides support for the `prove6` command which runs a TAP based test suite and prints a report. The actual command is in the App::prove6 module.
The `prove6` command is a minimal wrapper around an instance of this module.

For a detailed documentation on how to use `prove6` [click here](https://github.com/Leont/app-prove6/blob/master/README.md) or run `prove6 --help` (once it's been installed)

# SYNOPSIS

```Raku
use TAP::Harness;
my $harness = TAP::Harness.new(|%args);
$harness.run(@tests);
```

# METHODS

## Class Methods

### new

```Raku
my %args = jobs => 1, err  => 'ignore';
my $harness = TAP::Harness.new( |%args );
```

The constructor returns a new `TAP::Harness` object.
It accepts an optional hash whose allowed keys are:

* `volume`

  Default value: `Normal`

  Possible values: `Silent` `ReallyQuiet` `Quiet` `Normal` `Verbose`
* `jobs`

  The maximum number of parallel tests to run.

  Default value: `1`

  Possible values: An `Int`
* `timer`

  Append run time for each test to output.

  Default value: `False`

  Possible values: `True` `False`
* `err`

  Error reporting configuration.

  Default value: `stderr`

  Possible values: `stderr` `ignore` `merge` `Supply` `IO::Handle`

  |Value       |Definition                                        |
  |------------|--------------------------------------------------|
  |`stderr`    |Direct the test's `$*ERR` to the harness' `$*ERR` |
  |`ignore`    |Ignore the test scripts' `$*ERR`                  |
  |`merge`     |Merge the test scripts' `$*ERR` into their `$*OUT`|
  |`Supply`    |Direct the test's `$*ERR` to a `Supply`           |
  |`IO::Handle`|Direct the test's `$*ERR` to an `IO::Handle`      |
* `ignore-exit`

  If set to `True` will instruct `TAP::Parser` to ignore exit and wait for status from test scripts.

  Default value: `False`

  Possible values: `True` `False`
* `trap`

  Attempt to print summary information if run is interrupted by SIGINT (Ctrl-C).

  Default value: `False`

  Possible values: `True` `False`
* `handlers`

  Default value: `TAP::Harness::SourceHandler::Raku`

  Possible values: `TAP::Harness::SourceHandler::Raku`
  `TAP::Harness::SourceHandler::Exec`

  |Language|Handler                                          |
  |--------|-------------------------------------------------|
  |Raku    |`TAP::Harness::SourceHandler::Raku.new`          |
  |Perl 5  |`TAP::Harness::SourceHandler::Exec.new('perl')`  |
  |Ruby    |`TAP::Harness::SourceHandler::Exec.new('ruby')`  |
  |Python  |`TAP::Harness::SourceHandler::Exec.new('python')`|

## Instance Methods

### run

```Raku
$harness.run(@tests);
```

Accepts an array of `@tests` to be run. This should generally be the names of test files.

# TODO

These features are currently not implemented but are considered desirable:

 * Rule based parallel scheduling
 * Source Handlers other than `::Raku`
 * Various `prove6` arguments
 * Better documentation

 # LICENSE

You can use and distribute this module under the terms of the The Artistic License 2.0. See the LICENSE file included in this distribution for complete details.
