[![Actions Status](https://github.com/tbrowder/tap-harness6/actions/workflows/linux.yml/badge.svg)](https://github.com/tbrowder/tap-harness6/actions) [![Actions Status](https://github.com/tbrowder/tap-harness6/actions/workflows/macos.yml/badge.svg)](https://github.com/tbrowder/tap-harness6/actions) [![Actions Status](https://github.com/tbrowder/tap-harness6/actions/workflows/windows.yml/badge.svg)](https://github.com/tbrowder/tap-harness6/actions)

NAME
====



TAP

DESCRIPTION
===========



An asynchronous TAP framework written in Raku.

SYNOPSIS
========



```Raku
use TAP;
my $harness = TAP::Harness.new(|%args);
$harness.run(@tests);
```

METHODS
=======



Class Methods
-------------

### new

```Raku
my %args = jobs => 1, err  => 'ignore';
my $harness = TAP::Harness.new( |%args );
```

The constructor returns a new `TAP::Harness` object. It accepts an optional hash whose allowed keys are:

  * `volume`

        Default value: C<Normal>

        Possible values: C<Silent> C<ReallyQuiet> C<Quiet> C<Normal> C<Verbose>

  * `jobs`

        The maximum number of parallel tests to run.

        Default value: C<1>

        Possible values: An C<Int>

  * `timer`

        Append run time for each test to output.

        Default value: C<False>

        Possible values: C<True> C<False>

  * `err`

        Error reporting configuration.

        Default value: C<stderr>

        Possible values: C<stderr> C<ignore> C<merge> C<Supply> C<IO::Handle>

    <table class="pod-table">
    <thead><tr>
    <th>Value</th> <th>Definition</th>
    </tr></thead>
    <tbody>
    <tr> <td>stderr</td> <td>Direct the test&#39;s &#39;$*ERR&#39; to the harness&#39; &#39;$*ERR&#39;</td> </tr> <tr> <td>ignore</td> <td>Ignore the test scripts&#39; &#39;$*ERR&#39;</td> </tr> <tr> <td>merge</td> <td>Merge the test scripts&#39; &#39;$*ERR&#39; into their &#39;$*OUT`</td> </tr> <tr> <td>Supply</td> <td>Direct the test&#39;s &#39;$*ERR&#39; to a &#39;Supply&#39;</td> </tr> <tr> <td>IO::Handle</td> <td>Direct the test&#39;s &#39;$*ERR&#39; to an &#39;IO::Handle&#39;</td> </tr>
    </tbody>
    </table>

  * `ignore-exit`

        If set to C<True> will instruct C<TAP::Parser> to ignore exit and wait for status from test scripts.

        Default value: C<False>

        Possible values: C<True> C<False>

  *     C<trap>

       Attempt to print summary information if run is interrupted by SIGINT (Ctrl-C).

       Default value: C<False>

       Possible values: C<True> C<False>

  *     C<handlers>

       Default value: C<TAP::Harness::SourceHandler::Raku>

       Possible values: C<TAP::Harness::SourceHandler::Raku>
       C<TAP::Harness::SourceHandler::Exec>

    <table class="pod-table">
    <thead><tr>
    <th>Language</th> <th>Handler</th>
    </tr></thead>
    <tbody>
    <tr> <td>Raku</td> <td>TAP::Harness::SourceHandler::Raku.new</td> </tr> <tr> <td>Perl 5</td> <td>TAP::Harness::SourceHandler::Exec.new(&#39;perl&#39;)</td> </tr> <tr> <td>Ruby</td> <td>TAP::Harness::SourceHandler::Exec.new(&#39;ruby&#39;)</td> </tr> <tr> <td>Python</td> <td>TAP::Harness::SourceHandler::Exec.new(&#39;python&#39;)</td> </tr>
    </tbody>
    </table>

Instance Methods
----------------

### run

```Raku
$harness.run(@tests);
```

Accepts an array of `@tests` to be run. This should generally be the names of test files.

TODO
====



These features are currently not implemented but are considered desirable:

  * Rule based parallel scheduling

  * Source Handlers other than `::Raku`

  * Better documentation

LICENSE
=======



You can use and distribute this module under the terms of the The Artistic License 2.0. See the LICENSE file included in this distribution for complete details.

