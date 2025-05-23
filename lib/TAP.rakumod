use v6;

unit module TAP:ver<0.3.15>;

package X {
    class Bailout is Exception {
        has Str $.explanation;

        method message() {
            my $explanation = $!explanation // 'no reason given';
            return "Bailed out: $explanation";
        }
    }

    class Interrupted is Exception {
        method message() {
            return "Interrupted";
        }
    }
}

role Entry {
}
class Version does Entry {
    has Int:D $.version is required;
}
class Plan does Entry {
    has Int:D $.tests is required;
    has Str $.explanation handles :skip-all<defined>;
}

enum Directive <No-Directive Skip Todo>;

class Test does Entry {
    has Bool:D $.ok is required;
    has Int $.number;
    has Str $.description;
    has Directive:D $.directive = No-Directive;
    has Str $.explanation;

    method is-ok() {
        $!ok || $!directive ~~ Todo;
    }
}

class Sub-Test is Test {
    has @.entries;

    method inconsistencies(Str $usable-number = ~($.number // '?')) {
        my @errors;
        my @tests = @!entries.grep(Test);
        if $.is-ok != ?all(@tests).is-ok {
            @errors.push: "Subtest $usable-number isn't coherent";
        }
        my @plans = @!entries.grep(Plan);
        if !@plans {
            @errors.push: "Subtest $usable-number doesn't have a plan";
        } elsif @plans > 1 {
            @errors.push: "Subtest $usable-number has multiple plans";
        } elsif @plans[0].tests != @tests.elems {
            @errors.push: "Subtest $usable-number expected { @plans[0].tests } but contains { @tests.elems } tests";
        }
        @errors;
    }
}

class Bailout does Entry {
    has Str $.explanation;
}
class Comment does Entry {
    has Str:D $.comment is required;
}
class Pragma does Entry {
    has Bool:D %.identifiers is required;
}
class YAML does Entry {
    has Str:D $.serialized is required;
    has Any $.deserialized;
}
class Unknown does Entry {
}

my role Entry::Handler {
    method handle-entry(Entry) { ... }
    method fail-entries($ex) {
        self.end-entries;
    }
    method end-entries() { }
}

class Status {
    has Int $.exit;
    has Int $.signal;
    multi method new(Int $exit, Int $signal) {
        self.bless(:$exit, :$signal);
    }
    multi method new(Proc $proc) {
        self.new($proc.exitcode, $proc.signal);
    }
    multi method wait(::?CLASS:D:) {
        ($!exit +< 8) +| $!signal;
    }
    multi method wait(::?CLASS:U:) {
        Int;
    }
}

class Result {
    has Str:D $.name is required;
    has Int:_ $.tests-planned is required;
    has Int:D $.tests-run is required;
    has Int:D $.passed is required;
    has Int:D @.failed is required;
    has Str:D @.errors is required;
    has Int:D $.actual-passed is required;
    has Int:D $.actual-failed is required;
    has Int:D $.todo is required;
    has Int:D @.todo-passed is required;
    has Int:D $.skipped is required;
    has Int:D $.unknowns is required;
    has Bool:D $.skip-all is required;
    has Status $.exit-status handles <exit signal wait> is required;
    has Duration:D $.time is required;

    method has-problems($ignore-exit = False) {
        so @!failed || @!errors || (!$ignore-exit && $!exit-status.wait);
    }
}

class Aggregator {
    has Promise $!bailout is built(True);
    has Result:D %!results-for is built(False);
    has Str:D @!parse-order is built(False);

    has Int:D $.tests-planned is built(False) = 0;
    has Int:D $.tests-run is built(False) = 0;
    has Int:D $.passed is built(False) = 0;
    has Int:D $.failed is built(False) = 0;
    has Int:D $.errors is built(False) = 0;
    has Int:D $.actual-passed is built(False) = 0;
    has Int:D $.actual-failed is built(False) = 0;
    has Int:D $.todo is built(False) = 0;
    has Int:D $.todo-passed is built(False) = 0;
    has Int:D $.skipped is built(False) = 0;
    has Int:D $.exit-failed is built(False) = 0;

    has Bool:D $.ignore-exit = False;

    method add-result(Result $result) {
        my $description = $result.name;
        die "You already have a parser for ($description). Perhaps you have run the same test twice." if %!results-for{$description};
        %!results-for{$description} = $result;
        @!parse-order.push($result.name);

        $!tests-planned += $result.tests-planned // 0;
        $!tests-run += $result.tests-run;
        $!passed += $result.passed;
        $!failed += $result.failed.elems;
        $!actual-passed += $result.actual-passed;
        $!actual-failed += $result.actual-failed;
        $!todo += $result.todo;
        $!todo-passed += $result.todo-passed.elems;
        $!skipped += $result.skipped.elems;
        $!errors += $result.errors.elems;
        $!exit-failed++ if not $!ignore-exit and $result.wait;
    }

    method result-count {
        +@!parse-order;
    }
    method results() {
        %!results-for{@!parse-order};
    }


    method has-problems() {
        so $!todo-passed || self.has-errors;
    }
    method has-errors() {
        so $!failed + $!errors + $!exit-failed;
    }
    method get-status() {
        self.has-errors || $!tests-run != $!passed ?? 'FAILED' !! $!tests-run ?? 'PASS' !! 'NOTESTS';
    }

    method bailout {
        return $!bailout ?? $!bailout.cause !! Exception;
    }
}

grammar Grammar {
    token TOP { <entry>+ }
    token sp { <[\s] - [\n]> }
    token num { <[0..9]>+ }
    token entry {
        ^^ [ <plan> | <test> | <bailout> | <version> | <comment> | <pragma> | <yaml> | <sub-test> || <unknown> ] \n
    }
    token plan {
        '1..' <count=.num> <.sp>* [
            '#' <.sp>* $<directive>=[:i 'SKIP'] \S*
            [ <.sp>+ $<explanation>=[\N*] ]?
        ]?
    }
    regex description {
        [ '\\\\' || '\#' || <-[\n#]> ]+ <!after <sp>+>
    }
    token test {
        $<nok>=['not '?] 'ok' [ <.sp> <num> ]? ' -'?
            [ <.sp>* <description> ]?
            [
                <.sp>* '#' <.sp>* $<directive>=[:i [ 'SKIP' \S* | 'TODO'] ]
                [ <.sp>+ $<explanation>=[\N*] ]?
            ]?
            <.sp>*
    }
    token bailout {
        'Bail out!' [ <.sp> $<explanation>=[\N*] ]?
    }
    token version {
        :i 'TAP version ' <version=.num>
    }
    token pragma-identifier {
        $<sign>=<[+-]> $<name>=[<alnum>+]
    }
    token pragma {
        'pragma ' <pragma-identifier>+ % ' '
    }
    token comment {
        '#' <.sp>* $<comment>=[\N*]
    }
    token yaml(Int $indent = 0) {
        '  ---' \n
        [ ^^ <.indent($indent)> '  ' $<yaml-line>=[<!before '...'> \N* \n] ]*
        <.indent($indent)> '  ...'
    }
    token sub-entry(Int $indent) {
        <plan> | <test> | <comment> | <pragma> | <yaml($indent)> | <sub-test($indent)> || <!before <.sp> > <unknown>
    }
    token indent(Int $indent) {
        '    ' ** { $indent }
    }
    token sub-test(Int $indent = 0) {
        '    '
        [ <sub-entry($indent + 1)> \n ]+ % [ <.indent($indent+1)> ]
        <.indent($indent)> <test>
    }
    token unknown {
        \N*
    }
}

class Actions {
    method TOP($/) {
        make @<entry>».made;
    }
    method entry($/) {
        make $/.values[0].made;
    }
    method plan($/) {
        my %args = :tests(+$<count>);
        if $<directive> {
            %args<explanation> = ~$<explanation>;
        }
        make TAP::Plan.new(|%args);
    }
    method description($m) {
        $m.make: ~$m.subst(/\\('#'|'\\')/, { $_[0] }, :g)
    }
    method !make_test($/) {
        my %args = (:ok($<nok> eq ''));
        %args<number> = $<num> ?? +$<num> !! Int;
        %args<description> = $<description>.made if $<description>;
        %args<directive> = $<directive> ?? TAP::Directive::{~$<directive>.substr(0,4).tclc} !! TAP::No-Directive;
        %args<explanation> = ~$<explanation> if $<explanation>;
        %args;
    }
    method test($/) {
        make TAP::Test.new(|self!make_test($/));
    }
    method bailout($/) {
        make TAP::Bailout.new(:explanation($<explanation> ?? ~$<explanation> !! Str));
    }
    method version($/) {
        make TAP::Version.new(:version(+$<version>));
    }
    method pragma-identifier($/) {
        make $<name> => ?( $<sign> eq '+' );
    }
    method pragma($/) {
        my Bool:D %identifiers = @<pragma-identifier>.map(*.ast);
        make TAP::Pragma.new(:%identifiers);
    }
    method comment($/) {
        make TAP::Comment.new(:comment(~$<comment>));
    }
    method yaml($/) {
        my $serialized = $<yaml-line>.join('');
        my $deserialized = try (require YAMLish) ?? YAMLish::load-yaml("---\n$serialized...") !! Any;
        make TAP::YAML.new(:$serialized, :$deserialized);
    }
    method sub-entry($/) {
        make $/.values[0].made;
    }
    method sub-test($/) {
        my @entries = @<sub-entry>».made;
        make TAP::Sub-Test.new(:@entries, |self!make_test($<test>));
    }
    method unknown($/) {
        make TAP::Unknown.new;
    }
}

role Output {
    method print(Str $value) {
        ...
    }
    method say(Str $value) {
        self.print($value ~ "\n");
    }
    method flush() {
    }
    method terminal() {
        False;
    }
}

class Output::Handle does Output {
    has IO::Handle:D $.handle handles(:print<print>, :flush<flush>, :terminal<t>) = $*OUT;
}

class Output::Supplier does Output {
    has Supplier:D $.supplier is required;
    method print(Str $value) {
        $!supplier.emit($value);
    }
}

my sub parse-stream(Supply $input, Output $output --> Supply) {
    supply {
        enum Mode <Normal SubTest Yaml >;
        my Mode $mode = Normal;
        my Str @buffer;
        my $grammar = Grammar.new;

        sub emit-reset($line) {
            for $grammar.parse($line, :actions(Actions)).made -> $entry {
                emit $entry;
            }
            @buffer = ();
            $mode = Normal;
        }

        whenever $input.lines(:!chomp) -> $line {
            $output.print($line) with $output;

            if $mode === Normal {
                if $line.starts-with('  ---') {
                    ($mode, @buffer) = (Yaml, $line);
                } elsif $line.starts-with('    ') {
                    ($mode, @buffer) = (SubTest, $line);
                } else {
                    emit-reset $line;
                }
            }
            elsif $mode === SubTest {
                @buffer.push: $line;
                if not $line.starts-with('    ') {
                    emit-reset @buffer.join('');
                }
            }
            elsif $mode === Yaml {
                @buffer.push: $line;
                if not $line.starts-with('  ') or $line eq "  ...\n" {
                    emit-reset @buffer.join('');
                }
            }
        }
        LEAVE { emit-reset @buffer.join('') if @buffer; $output.flush with $output }
    }
}

enum Formatter::Volume (:Silent(-2) :Quiet(-1) :Normal(0) :Verbose(1));
role Formatter {
    has Bool:D $.timer = False;
    has Formatter::Volume $.volume = Normal;
    has Bool:D $.ignore-exit = False;
}
role Reporter {
    has Output:D $.output is required;
    has Formatter:D $.formatter handles<volume> is required;
    method summarize(TAP::Aggregator, Duration $duration) { ... }
    method open-test(Str $) { ... }
}

role Session does Entry::Handler {
    has TAP::Reporter $.reporter;
    has Str $.name;
    has Str $.header;
    method clear-for-close() {
    }
    method close-test(TAP::Result $result) {
        $!reporter.print-result(self, $result);
    }
}

class Reporter::Text::Session does Session {
    method handle-entry(TAP::Entry $) {
    }
}
class Formatter::Text does Formatter {
    has Int $!longest;

    submethod TWEAK(:@names) {
        $!longest = @names ?? @names».chars.max !! 12;
    }
    method format-name($name) {
        my $periods = '.' x ( $!longest + 2 - $name.chars);
        my @now = $.timer ?? ~DateTime.new(now, :formatter{ '[' ~ .hour ~ ':' ~ .minute ~ ':' ~ .second.Int ~ ']' }) !! ();
        (|@now, $name, $periods).join(' ');
    }
    method format-summary(TAP::Aggregator $aggregator, Duration $duration) {
        my $output = '';

        if $aggregator.bailout ~~ X::Interrupted {
            $output ~= self.format-failure("Test run interrupted!\n");
        } elsif $aggregator.bailout ~~ X::Bailout {
            my $explanation = $aggregator.bailout.explanation // 'no reason given';
            $output ~= self.format-failure("Bailed out: $explanation\n");
        } elsif $aggregator.failed == 0 && $aggregator.tests-run > 0 {
            $output ~= self.format-success("All tests successful.\n");
        }

        if $aggregator.has-problems {
            $output ~= "\nTest Summary Report";
            $output ~= "\n-------------------\n";
            for $aggregator.results -> $result {
                my $name = $result.name;
                if $result.has-problems($!ignore-exit) {
                    my $spaces = ' ' x min($!longest - $name.chars, 1);
                    my $wait = $result.wait // '(none)';
                    my $line = "$name$spaces (Wstat: $wait Tests: {$result.tests-run} Failed: {$result.failed.elems})\n";
                    $output ~= self.format-failure($line);

                    if $result.failed -> @failed {
                        $output ~= self.format-failure('  Failed tests:  ' ~ @failed.join(' ') ~ "\n");
                    }
                    if $result.todo-passed -> @todo-passed {
                        $output ~= "  TODO passed:  { @todo-passed.join(' ') }\n";
                    }
                    if $result.wait -> $wait {
                        if $result.exit {
                            $output ~= self.format-failure("Non-zero exit status: { $result.exit }\n");
                        } else {
                            $output ~= self.format-failure("Non-zero wait status: $wait\n");
                        }
                    }
                    if $result.errors -> @ ($head, *@tail) {
                        $output ~= self.format-failure("  Parse errors: $head\n");
                        $output ~= @tail.map({ self.format-failure(' ' x 16 ~ $_ ~ "\n") }).join('');
                    }
                }
            }
        }
        my $timing = $duration.defined ?? ",  { $duration.Int } wallclock secs" !! '';
        $output ~= "Files={ $aggregator.result-count }, Tests={ $aggregator.tests-run }$timing\n";
        my $status = $aggregator.get-status;
        $output ~= "Result: $status\n";
        self.format-return($output);
    }
    method format-success(Str $output) {
        $output;
    }
    method format-failure(Str $output) {
        $output;
    }
    method format-return(Str $output) {
        $output;
    }
    method format-result(Session $session, TAP::Result $result) {
        my $name = $session.header;
        if ($result.skip-all) {
            return self.format-return("$name skipped\n");
        } elsif ($result.has-problems($!ignore-exit)) {
            return self.format-test-failure($name, $result);
        } else {
            my $time = self.timer && $result.time ?? sprintf ' %8d ms', Int($result.time * 1000) !! '';
            my $ok = self.format-success("ok");
            return self.format-return("$name $ok$time\n");
        }
    }
    method format-test-failure(Str $name, TAP::Result $result) {
        return if self.volume <= Quiet;
        my $output = self.format-return("$name ");

        my $total = $result.tests-planned // $result.tests-run;
        my $failed = $result.failed + abs($total - $result.tests-run);

        if !$!ignore-exit && $result.exit -> $status {
            $output ~= self.format-failure("Dubious, test returned $status\n");
        }

        if $result.failed == 0 {
            $output ~= self.format-failure($total ?? "All $total subtests passed " !! 'No subtests run');
        } else {
            $output ~= self.format-failure("Failed {$result.failed.elems}/$total subtests ");
            if (!$total) {
                $output ~= self.format-failure("\nNo tests run!");
            }
        }

        if $result.skipped -> $skipped {
            my $passed = $result.passed - $skipped;
            my $test = 'subtest' ~ ( $skipped != 1 ?? 's' !! '' );
            $output ~= "\n\t(less $skipped skipped $test: $passed okay)";
        }

        if $result.todo-passed.elems -> $todo-passed {
            my $test = $todo-passed > 1 ?? 'tests' !! 'test';
            $output ~= "\n\t($todo-passed TODO $test unexpectedly succeeded)";
        }

        $output ~= "\n";
        $output;
    }
}
class Reporter::Text does Reporter {
    method open-test(Str $name) {
        my $header = $!formatter.format-name($name);
        Reporter::Text::Session.new(:$name, :$header, :reporter(self));
    }
    method summarize(TAP::Aggregator $aggregator, Duration $duration) {
        self!output($!formatter.format-summary($aggregator, $duration)) unless self.volume === Silent;
    }
    method !output(Any $value) {
        $!output.print($value);
    }
    method print-result(Reporter::Text::Session $session, TAP::Result $report) {
        self!output($!formatter.format-result($session, $report)) unless self.volume <= Quiet;
    }
}

class Formatter::Color is Formatter::Text {
    has &colored = (try require Terminal::ANSIColor) !=== Nil
        ?? ::('Terminal::ANSIColor::EXPORT::DEFAULT::&colored')
        !! sub ($text, $) { $text };
    method format-success(Str $output) {
        &colored($output, 'green');
    }
    method format-failure(Str $output) {
        &colored($output, 'red');
    }
    method format-return(Str $output) {
        "\r$output";
    }
}

class Reporter::Console::Session does Session {
    has Int $!last-updated = 0;
    has Int $.plan = Int;
    has Int:D $.number = 0;
    proto method handle-entry(TAP::Entry $entry) {
        {*};
    }
    multi method handle-entry(TAP::Plan $plan) {
        $!plan = $plan.tests;
    }
    multi method handle-entry(TAP::Test $test) {
        my $now = time;
        ++$!number;
        if $!last-updated != $now {
            $!last-updated = $now;
            $!reporter.update($.name, $!header, $test.number // $!number, $!plan);
        }
    }
    multi method handle-entry(TAP::Entry $) {
    }
    method summary() {
        ($!number, $!plan // '?').join("/");
    }
}
class Reporter::Console does Reporter {
    has Int $!last-length = 0;
    has Supplier $events = Supplier.new;
    has Reporter::Console::Session @!active;
    has Int $!tests = 0;
    has Int $!fails = 0;

    submethod TWEAK(:$!output, :$!formatter) {
        my $now = 0;
        my $start = now;

        sub output-ruler(Bool $refresh) {
            my $new-now = now;
            return if $now === $new-now and !$refresh;
            $now = $new-now;
            my $header = sprintf '===( %7d;%d', $!tests, $now - $start;
            my @items = @!active.map(*.summary);
            my $ruler = ($header, |@items).join('  ') ~ ')===';
            $ruler = $ruler.substr(0,70) if $ruler.chars > 70;
            my $output = $!formatter.format-return($ruler);
            $!last-length = $output.chars;
            $!output.print($output);
        }
        multi receive('update', Str $name, Str $header, Int $number, Int $plan) {
            return if self.volume <= Quiet;
            if @!active.elems == 1 {
                my $status = ($header, $number, '/', $plan // '?').join('');
                $!output.print($!formatter.format-return($status));
                $!last-length = $status.chars;
            } else {
                output-ruler($number == 1);
            }
        }
        multi receive('bailout', Str $explanation) {
            return if self.volume <= Quiet;
            $!output.print($!formatter.format-failure("Bailout called.  Further testing stopped: $explanation\n"));
        }
        multi receive('result', Reporter::Console::Session $session, TAP::Result $result) {
            return if self.volume <= Quiet;
            my $output = $!formatter.format-result($session, $result);
            $!output.print($!formatter.format-return(' ' x $!last-length) ~ $output);
            $!last-length = $output.chars;
            @!active = @!active.grep(* !=== $session);
            output-ruler(True) if @!active.elems > 1;
        }
        multi receive('summary', TAP::Aggregator $aggregator, Duration $duration) {
            $!output.print($!formatter.format-summary($aggregator, $duration)) unless self.volume === Silent;
        }

        $!events.Supply.act(-> @args { receive(|@args) });
    }

    method update(Str $name, Str $header, Int $number, Int $plan) {
        $!events.emit(['update', $name, $header, $number, $plan]);
    }
    method bailout(Str $explanation) {
        $!events.emit(['bailout', $explanation]);
    }
    method print-result(Reporter::Console::Session $session, TAP::Result $result) {
        $!events.emit(['result', $session, $result]);
    }
    method summarize(TAP::Aggregator $aggregator, Duration $duration) {
        $!events.emit(['summary', $aggregator, $duration]) unless self.volume === Silent;
    }

    method open-test(Str $name) {
        my $header = $!formatter.format-name($name);
        my $ret = Reporter::Console::Session.new(:$name, :$header, :reporter(self));
        @!active.push($ret);
        $ret;
    }
}

my class State does TAP::Entry::Handler {
    has Range $.allowed-versions = 12 .. 14;
    has Int $!tests-planned;
    has Int $!tests-run = 0;
    has Int $!passed = 0;
    has Int @!failed;
    has Str @!errors;
    has Int $!actual-passed = 0;
    has Int $!actual-failed = 0;
    has Int $!todo = 0;
    has Int @!todo-passed;
    has Int $!skipped = 0;
    has Int $!unknowns = 0;
    has Bool $!skip-all = False;
    has Bool $!strict;

    has Promise $.bailout;
    has Int $!seen-lines = 0;
    enum Seen <Unseen Before After>;
    has Seen $!seen-plan = Unseen;
    has Promise $.done = Promise.new;
    has Int $!version;
    has Bool $.loose;
    has Entry::Handler @!handlers is built;
    has $!start-time = now;

    submethod TWEAK(Supply :$events) {
        my $act  = { self.handle-entry($^entry) };
        my $done = { self.end-entries };
        my $quit = { self.fail-entries($^ex) };
        $events.act($act, :$done, :$quit);
    }

    proto method handle-entry(TAP::Entry $entry) {
        if $!seen-plan === After && $entry !~~ TAP::Comment {
            self!add-error("Got line $entry after late plan");
        }
        {*};
        .handle-entry($entry) for @!handlers;
        $!seen-lines++;
    }
    multi method handle-entry(TAP::Version $entry) {
        if $!seen-lines {
            self!add-error('Seen version declaration mid-stream');
        } elsif $entry.version !~~ $!allowed-versions {
            self!add-error("Version must be in range $!allowed-versions");
        } else {
            $!version = $entry.version;
        }
    }
    multi method handle-entry(TAP::Plan $plan) {
        if $!seen-plan != Unseen {
            self!add-error('Seen a second plan');
        } else {
            $!tests-planned = $plan.tests;
            $!seen-plan = $!tests-run ?? After !! Before;
            $!skip-all = $plan.skip-all;
        }
    }
    multi method handle-entry(TAP::Test $test) {
        my $found-number = $test.number;
        my $expected-number = ++$!tests-run;
        if $found-number.defined && ($found-number != $expected-number) {
            self!add-error("Tests out of sequence.  Found ($found-number) but expected ($expected-number)");
        }
        if $!seen-plan === After {
            self!add-error("Plan must be at the beginning or end of the TAP output");
        }

        my $usable-number = $found-number // $expected-number;
        if $test.is-ok {
            $!passed++;
        } else {
            @!failed.push($usable-number);
        }
        ($test.ok ?? $!actual-passed !! $!actual-failed)++;
        $!todo++ if $test.directive === TAP::Todo;
        @!todo-passed.push($usable-number) if $test.ok && $test.directive === TAP::Todo;
        $!skipped++ if $test.directive === TAP::Skip;

        if !$!loose && $test ~~ TAP::Sub-Test {
            for $test.inconsistencies(~$usable-number) -> $error {
                self!add-error($error);
            }
        }
    }
    multi method handle-entry(TAP::Bailout $entry) {
        my $ex = X::Bailout.new(explanation => $entry.explanation);
        if $!bailout.defined {
            $!bailout.break($ex);
        } else {
            $!done.break($ex);
        }
        self!add-error($entry.explanation ?? "Bail out! $entry.explanation()" !! 'Bail out!');
    }
    multi method handle-entry(TAP::Unknown $) {
        $!unknowns++;
        if $!strict {
            self!add-error('Seen invalid TAP in strict mode');
        }
    }
    multi method handle-entry(TAP::Pragma $entry) {
        if $entry.identifiers<strict>:exists {
            $!strict = $entry.identifiers<strict>;
        }
    }
    multi method handle-entry(TAP::Entry $entry) {
    }

    method fail-entries($ex) {
        $!done.break($ex);
        .fail-entries($ex) for @!handlers;
    }
    method end-entries() {
        if $!seen-plan == Unseen {
            self!add-error('No plan found in TAP output');
        }
        elsif $!tests-run != $!tests-planned {
            self!add-error("Bad plan.  You planned $!tests-planned tests but ran $!tests-run.");
        }
        $!done.keep;
        .end-entries for @!handlers;
    }
    method finalize(Str $name, Status $exit-status) {
        my $time = now - $!start-time;
        $!done.cause.rethrow if $!done.status ~~ Broken;
        TAP::Result.new(:$name, :$!tests-planned, :$!tests-run, :$!passed, :@!failed, :@!errors, :$!skip-all,
            :$!actual-passed, :$!actual-failed, :$!todo, :@!todo-passed, :$!skipped, :$!unknowns, :$exit-status, :$time);
    }
    method !add-error(Str $error) {
        push @!errors, $error;
    }
}

class Parser does Awaitable {
    subset Killable of Any where { .can('kill') };

    has Str $.name;
    has Promise:D $!process is built = Promise.kept(Status);
    has Killable $!killer is built;
    has State $!state is built;
    has Promise $.promise is built(False) handles <result get-await-handle> = self!build-promise;

    method !build-promise() {
        my $done = Promise.allof($!state.done, $!process);
        $done.then({
            my $exit-status = try { $!process.result } // Status;
            $!state.finalize($!name, $exit-status);
        });
    }
    method kill() {
        $!killer.kill if $!killer;
    }
}

role Source {
    has Str:D $.name = '';
    method parse(Promise :$bailout, Bool :$loose, :@handlers, Output :$output) { ... }
}
class Source::Proc does Source {
    has Str @.command is required;
    has $.cwd = $*CWD;
    has %.env = %*ENV;

    method parse(Promise :$bailout, Bool :$loose, :@handlers, Output :$output, Any :$err = 'stderr') {
        my $async = Proc::Async.new(@!command);
        my $events = parse-stream($async.stdout, $output);
        state $devnull;
        END { $devnull.close with $devnull }
        given $err {
            when 'stderr' { #default is correct
            }
            when 'merge' {
                warn "Merging isn't supported yet on Asynchronous streams";
                $devnull //= open($*SPEC.devnull, :w);
                $async.bind-stderr($devnull);
            }
            when 'ignore' {
                $devnull //= open($*SPEC.devnull, :w);
                $async.bind-stderr($devnull);
            }
            when IO::Handle:D {
                $async.bind-stderr($err);
            }
            when Supplier:D {
                $async.stderr.act({ $err.emit($_) }, :done({ $err.done }), :quit({ $err.quit($^reason) }));
            }
            default {
                die "Unknown error handler";
            }
        }
        my $state = State.new(:$bailout, :$loose, :$events, :@handlers);
        my $start = $async.start(:$!cwd, :ENV(%!env));
        my $process = $start.then({ Status.new($start.result) });
        Parser.new(:$!name, :$state, :$process, :killer($async));
    }
}
class Source::File does Source {
    has IO::Path:D(Str) $.filename is required;

    method parse(Promise :$bailout, Bool :$loose, :@handlers, Output :$output) {
        my $events = parse-stream(supply { emit $!filename.slurp(:close) }, $output);
        my $state = State.new(:$bailout, :$loose, :$events, :@handlers);
        Parser.new(:$!name, :$state);
    }
}
class Source::String does Source {
    has Str:D $.content is required;

    method parse(Promise :$bailout, Bool :$loose, :@handlers, Output :$output) {
        my $events = parse-stream(supply { emit $!content }, $output);
        my $state = State.new(:$bailout, :$loose, :$events, :@handlers);
        Parser.new(:$!name, :$state);
    }
}
class Source::Supply does Source {
    has Supply:D $.supply is required;

    method parse(Promise :$bailout, Bool :$loose, Output :$output, :@handlers) {
        my $events = parse-stream($!supply, $output);
        my $state = State.new(:$bailout, :$loose, :$events, :@handlers);
        Parser.new(:$!name, :$state);
    }
}

subset SourceHandler::Priority of Numeric where 0..1;

role SourceHandler {
    method can-handle {...};

    proto method make-source(|) { * };
    multi method make-source(IO:D $path, IO:D() :$cwd = $path.CWD, *%args) {
        self.make-source($path.relative($cwd), :$cwd, |%args);
    }
    multi method make-source(::?CLASS:U: Str:D $name, *%args) {
        self.new.make-source($name, |%args);
    }

    method make-parser(Any:D $name, Promise :$bailout, Bool :$loose, :@handlers, Output :$output, Any:D :$err = 'stderr', *%args) {
        my $source = self.make-source($name, |%args);
        $source.parse(:$bailout, :$loose, :$output, :$err, :@handlers);
    }
}

my sub normalize-path($path, IO::Path $cwd) {
    $path ~~ IO ?? $path.relative($cwd) !! ~$path
}

class SourceHandler::Raku does SourceHandler {
    has Str:D $.path = $*EXECUTABLE.absolute;
    has @.incdirs;
    multi method make-source(::?CLASS:D: Str:D $name, IO:D() :$cwd = $*CWD, :%env is copy = %*ENV, :@include-dirs = (), *%) {
        my @raku-lib = (%env<RAKULIB> // "").split(",", :skip-empty);
        my @normalized = map { normalize-path($^dir, $cwd) }, flat @include-dirs, @!incdirs;
        @raku-lib.prepend(@normalized);
        %env<RAKULIB> = @raku-lib.join(',');
        TAP::Source::Proc.new(:$name, :command[ $!path, $name ], :$cwd, :%env);
    }
    method can-handle(IO::Path $name) {
        $name.extension eq 't6'|'rakutest' || $name.lines.head ~~ / ^ '#!' .* [ 'raku' | 'perl6' ] / ?? 0.8 !! 0.3;
    }
}

class SourceHandler::Exec does SourceHandler {
    has @.args;
    has SourceHandler::Priority $.priority = 1;
    method new (*@args) {
        self.bless(:@args);
    }
    method can-handle(IO::Path $name) {
        $!priority;
    }
    multi method make-source(::?CLASS:D: Str:D $name, IO:D() :$cwd = $*CWD, *%) {
        my $executable = ~$cwd.add($name);
        my @command = (|@!args, $executable);
        TAP::Source::Proc.new(:$name, :@command, :$cwd);
    }
}

class SourceHandler::File does SourceHandler {
    method can-handle(IO::Path $name) {
        $name.extension eq 'tap' ?? 1 !! 0;
    }
    multi method make-source(::?CLASS:D: Str:D $name, IO:D() :$cwd = $*CWD, *%) {
        my $filename = $cwd.add($name);
        TAP::Source::File.new(:$name, :$filename);
    }
}

class SourceHandlers {
    has TAP::SourceHandler @.handlers = ( SourceHandler::Raku.new, TAP::SourceHandler::File.new );
    multi method make-source(Str $path, IO:D(Str) :$cwd, *%args) {
        self.make-source(IO::Path.new($path, :CWD(~$cwd)), :$cwd, |%args);
    }
    multi method make-source(IO:D $path, IO:D(Str) :$cwd = $path.CWD, *%args) {
        @!handlers.max(*.can-handle($path)).make-source($path.relative($cwd), :$cwd, |%args)
    }
    multi method make-parser(Any:D $path, Promise :$bailout, Bool :$loose, :@handlers, Output :$output, Any:D :$err = 'stderr', *%args) {
        my $source = self.make-source($path, |%args);
        $source.parse(:$bailout, :$loose, :$output, :$err, :@handlers);
    }
    method COERCE($handlers) {
        self.new(:handlers($handlers.list));
    }
}

class Harness {
    # Backwards compatibility
    class SourceHandler {
        constant Raku = TAP::SourceHandler::Raku;
        constant Perl6 = TAP::SourceHandler::Raku; # will be removed later
        constant Exec = TAP::SourceHandler::Exec;
    }

    subset OutVal where any(IO::Handle:D, Supplier:D);

    has SourceHandlers() $.handlers = SourceHandlers.new;
    has IO::Handle $.handle = $*OUT;
    has OutVal $.output = $!handle;
    has Formatter::Volume $.volume = ?%*ENV<HARNESS_VERBOSE> ?? Verbose !! Normal;
    has Str %!env-options = (%*ENV<HARNESS_OPTIONS> // '').split(':').grep(*.chars).map: { / ^ (.) (.*) $ /; ~$0 => val(~$1) };
    has TAP::Reporter:U $.reporter-class;
    has Int:D $.jobs = %!env-options<j> // 1;
    has Bool:D $.timer = ?%*ENV<HARNESS_TIMER>;
    subset ErrValue where any(IO::Handle:D, Supplier, 'stderr', 'ignore', 'merge');
    has ErrValue $.err = 'stderr';
    has Bool:D $.ignore-exit = ?%*ENV<HARNESS_INGORE_EXIT>;
    has Bool:D $.trap = False;
    has Bool:D $.loose = $*PERL.compiler.version before 2017.09;
    has Bool $.color;

    class Run does Awaitable {
        has Promise $!promise handles <result get-await-handle> is built;
        has Promise $!bailout is built handles :kill<break>;
    }

    my &sigint = sub { signal(SIGINT) }

    my multi make-output(IO::Handle:D $handle) {
        return Output::Handle.new(:$handle);
    }
    my multi make-output(Supplier:D $supplier) {
        return Output::Supplier.new(:$supplier);
    }

    method !get-reporter(Output $output) {
        if $!reporter-class !=== Reporter {
            $!reporter-class;
        } elsif %!env-options<r> {
            my $classname = %!env-options<r>.subst('-', '::', :g);
            my $loaded = try ::($classname);
            return $loaded if $loaded !eqv Any;
            require ::($classname);
            ::($classname);
        } elsif $output.terminal && $!volume < Verbose {
            TAP::Reporter::Console;
        } else {
            TAP::Reporter::Text;
        }
    }

    method !get-color(Output $output) {
        with $!color {
            $!color;
        } orwith %!env-options<c> {
            True;
        } orwith %*ENV<HARNESS_COLOR> {
            ?%*ENV<HARNESS_COLOR>;
        } orwith %*ENV<NO_COLOR> {
            False;
        } else {
            state @safe-terminals = <xterm eterm vte konsole color>;
            $output.terminal && (%*ENV<TERM> // '') ~~ / @safe-terminals /;
        }
    }

    method run(*@names, IO(Str) :$cwd = $*CWD, OutVal :$out = $!output, ErrValue :$err = $!err, *%handler-args) {
        my $bailout = Promise.new;
        my $aggregator = TAP::Aggregator.new(:$!ignore-exit, :$bailout);
        my $output = make-output($out);
        my $formatter-class = self!get-color($output) ?? Formatter::Color !! Formatter::Text;
        my $formatter = $formatter-class.new(:@names, :$!volume, :$!timer, :$!ignore-exit);
        my $reporter-class = self!get-reporter($output);
        my $reporter = $reporter-class.new(:$output, :$formatter);

        my @working;
        my $promise = start {
            my $int = $!trap ?? sigint().tap({ $bailout.break(X::Interrupted.new); $int.close(); }) !! Tap;
            my $begin = now;
            try {
                for @names -> $name {
                    my $source = $!handlers.make-source($name, :$cwd, |%handler-args);
                    my $session = $reporter.open-test($source.name);
                    my @handlers = $session;
                    my $parser = $source.parse(:$bailout, :$!loose, :$err, :@handlers, :output($!volume === Verbose ?? $output !! Output));
                    @working.push({ :$parser, :$session, :done($parser.promise) });
                    next if @working < $!jobs;
                    await Promise.anyof(@working»<done>, $bailout);
                    reap-finished();
                    await $bailout if $bailout;
                }
                while @working {
                    await Promise.anyof(@working»<done>, $bailout);
                    reap-finished();
                    await $bailout if $bailout;
                }
                CATCH {
                    reap-finished();
                    @working».<parser>».kill;
                    when (X::Bailout | X::Interrupted) {
                    }
                }
            }
            $reporter.summarize($aggregator, now - $begin);
            $int.close if $int;
            $aggregator;
        }
        sub reap-finished() {
            my @new-working;
            for @working -> $current (:$done, :$parser, :$session) {
                if $done {
                    $aggregator.add-result($parser.result);
                    $session.close-test($parser.result);
                } else {
                    @new-working.push($current);
                }
            }
            @working = @new-working;
        }
        Run.new(:$promise, :$bailout);
    }
}

# ts=4 sw=4 et
