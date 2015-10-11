package TAP {
	role Entry {
		has Str $.raw;
		method to-string { ... }
		method Str {
			return $.raw // $.to-string;
		}
	}
	class Version does Entry {
		has Int:D $.version is required;
		method to-string() {
			return "TAP Version $!version";
		}
	}
	class Plan does Entry {
		has Int:D $.tests is required;
		has Bool $.skip-all;
		has Str $.explanation;
		method to-string() {
			return ('1..' ~ $!tests, ($!skip-all ?? ('#SKIP', $!explanation).grep(*.defined) !! () )).join(' ');
		}
	}

	enum Directive <No-Directive Skip Todo>;
	subset Directive::Explanation of Str where { not .defined or m/ ^ \N* $ / };

	class Test does Entry {
		has Bool:D $.ok is required;
		has Int $.number;
		has Str $.description;
		has Directive:D $.directive = No-Directive;
		has Str $.explanation;

		method is-ok() {
			return $!ok || $!directive ~~ Todo;
		}
		method to-string() {
			my @ret = ($!ok ?? 'ok' !! 'not ok'), $!number, '-', $!description;
			@ret.push('#'~$!directive.uc, $!explanation) if $!directive;
			return @ret.grep(*.defined).join(' ');
		}
	}
	subset Test::Description of Str where { not .defined or m/ ^ \N* $ / };

	class Sub-Test is Test {
		has @.entries;

		method inconsistencies(Str $usable-number = ~$.number // '?') {
			my @errors;
			my @tests = @!entries.grep(Test);
			if $.ok != ?all(@tests).is-ok {
				@errors.push: "Subtest $usable-number isn't coherent";
			}
			my @plans = @!entries.grep(Plan);
			if !@plans {
				@errors.push: "Subtest $usable-number doesn't have a plan";
			}
			elsif @plans > 1 {
				@errors.push: "Subtest $usable-number has multiple plans";
			}
			elsif @plans[0].tests != @tests.elems {
				@errors.push: "Subtest $usable-number expected { @plans[0].tests } but contains { @tests.elems } tests";
			}
			return @errors;
		}
		method to-string() {
			return (@!entries».to-string()».indent(4), callsame).join("\n");
		}
	}

	class Bailout does Entry {
		has Str $.explanation;
		method to-string {
			return ('Bail out!', $.explanation).grep(*.defined).join(' ');
		}
	}
	class Comment does Entry {
		has Str:D $.comment is required;
		method to-string {
			return "# $!comment";
		}
	}
	class YAML does Entry {
		has Str:D $.serialized is required;
		has Any $.deserialized;
		method to-string {
			return "  ---\n" ~ $!serialized.indent(2) ~~ '  ...'
		}
	}
	class Unknown does Entry {
		method to-string {
			$!raw // fail 'Can\'t stringify empty Unknown';
		}
	}

	role Entry::Handler {
		method handle-entry(Entry) { ... }
		method end-entries() { }
	}

	role Session does Entry::Handler {
		method close-test() { ... }
	}

	class Output does Entry::Handler {
		has IO::Handle $.handle = $*OUT;
		method handle-entry(Entry $entry) {
			$!handle.say(~$entry);
		}
		method end-entries() {
			$!handle.flush;
		}
		method open(Str $filename) {
			my $handle = open $filename, :w;
			$handle.autoflush(True);
			return Output.new(:$handle);
		}
	}

	class Entry::Handler::Multi does Entry::Handler {
		has @!handlers;
		submethod BUILD(:@handlers) {
			@!handlers = @handlers;
		}
		method handle-entry(Entry $entry) {
			for @!handlers -> $handler {
				$handler.handle-entry($entry);
			}
		}
		method end-entries() {
			for @!handlers -> $handler {
				$handler.end-entries();
			}
		}
		method add-handler(Entry::Handler $handler) {
			@!handlers.push($handler);
		}
	}

	class Collector does Entry::Handler {
		has @.entries;
		submethod BUILD() {
		}
		method handle-entry(Entry $entry) {
			@!entries.push($entry);
		}
	}

	class Result {
		has Str $.name;
		has Int $.tests-planned;
		has Int $.tests-run;
		has Int @.passed;
		has Int @.failed;
		has Str @.errors;
		has Int @.actual-passed;
		has Int @.actual-failed;
		has Int @.todo;
		has Int @.todo-passed;
		has Int @.skipped;
		has Int $.unknowns;
		has Bool $.skip-all;
		has Proc $.exit-status;
		has Duration $.time;
		method exit() {
			$!exit-status.defined ?? $!exit-status.exitcode !! Int;
		}
		method wait() {
			$!exit-status.defined ?? $!exit-status.status !! Int;
		}

		method has-problems() {
			@!todo || self.has-errors;
		}
		method has-errors() {
			return @!failed || @!errors || self.exit-failed;
		}
		method exit-failed() {
			return $!exit-status && $!exit-status.exitcode > 0;
		}
	}

	class Aggregator {
		has Result %.results-for;
		has Result @!parse-order;

		has Int $.parsed = 0;
		has Int $.tests-planned = 0;
		has Int $.tests-run = 0;
		has Int $.passed = 0;
		has Int $.failed = 0;
		has Str @.errors;
		has Int $.actual-passed = 0;
		has Int $.actual-failed = 0;
		has Int $.todo;
		has Int $.todo-passed;
		has Int $.skipped;
		has Bool $.exit-failed = False;

		method add-result(Result $result) {
			my $description = $result.name;
			die "You already have a parser for ($description). Perhaps you have run the same test twice." if %!results-for{$description};
			%!results-for{$description} = $result;
			@!parse-order.push($result);

			$!parsed++;
			$!tests-planned += $result.tests-planned // 1;
			$!tests-run += $result.tests-run;
			$!passed += $result.passed.elems;
			$!failed += $result.failed.elems;
			$!actual-passed += $result.actual-passed.elems;
			$!actual-failed += $result.actual-failed.elems;
			$!todo += $result.todo.elems;
			$!todo-passed += $result.todo-passed.elems;
			$!skipped += $result.skipped.elems;
			@!errors.push(|$result.errors);
			$!exit-failed = True if $result.exit-status && $result.exit-status.exitcode > 0;
		}

		method descriptions() {
			return @!parse-order».name;
		}

		method has-problems() {
			return $!todo-passed || self.has-errors;
		}
		method has-errors() {
			return $!failed || @!errors || $!exit-failed;
		}
		method get-status() {
			return self.has-errors || $!tests-run != $!passed ?? 'FAILED' !! $!tests-run ?? 'PASS' !! 'NOTESTS';
		}
	}

	grammar Grammar {
		method parse {
			my $*tap-indent = 0;
			callsame;
		}
		method subparse($, *%) {
			my $*tap-indent = 0;
			callsame;
		}
		token TOP { ^ <line>+ $ }
		token sp { <[\s] - [\n]> }
		token num { <[0..9]>+ }
		token line {
			^^ [ <plan> | <test> | <bailout> | <version> | <comment> | <yaml> | <sub-test> || <unknown> ] \n
		}
		token plan {
			'1..' <count=.num> <.sp>* [ '#' <.sp>* $<directive>=[:i 'SKIP'] <.alnum>* [ <.sp>+ $<explanation>=[\N*] ]? ]?
		}
		regex description {
			[ <-[\n\#\\]> | \\<[\\#]> ]+ <!after <sp>+>
		}
		token test {
			$<nok>=['not '?] 'ok' [ <.sp> <num> ]? ' -'?
				[ <.sp>* <description> ]?
				[ <.sp>* '#' <.sp>* $<directive>=[:i [ 'SKIP' | 'TODO'] ] <.alnum>* [ <.sp>+ $<explanation>=[\N*] ]? ]?
				<.sp>*
		}
		token bailout {
			'Bail out!' [ <.sp> $<explanation>=[\N*] ]?
		}
		token version {
			:i 'TAP version ' <version=.num>
		}
		token comment {
			'#' <.sp>* $<comment>=[\N*]
		}
		token yaml {
			$<yaml-indent>=['  '] '---' \n :
			[ ^^ <.indent> $<yaml-indent> $<yaml-line>=[<!before '...'> \N* \n] ]*
			<.indent> $<yaml-indent> '...'
		}
		token sub-entry {
			<plan> | <test> | <comment> | <yaml> | <sub-test> || <!before <sp>+ > <unknown>
		}
		token indent {
			'    ' ** { $*tap-indent }
		}
		token sub-test {
			'    ' :temp $*tap-indent += 1; <sub-entry> \n
			[ <.indent> <sub-entry> \n ]*
			'    ' ** { $*tap-indent - 1 } <test>
		}
		token unknown {
			\N*
		}
	}
	class Action {
		method TOP($/) {
			make @<line>».made;
		}
		method line($/) {
			make $/.values[0].made;
		}
		method plan($/) {
			my %args = :raw(~$/), :tests(+$<count>);
			if $<directive> {
				%args<skip-all explanation> = True, $<explanation>;
			}
			make TAP::Plan.new(|%args);
		}
		method description($/) {
			make ~$/.subst(/\\('#'|'\\')/, { $_[0] }, :g)
		}
		method !make_test($/) {
			my %args = (:ok($<nok> eq ''));
			%args<number> = $<num>.defined ?? +$<num> !! Int;
			%args<description> = $<description>.made if $<description>;
			%args<directive> = $<directive> ?? TAP::Directive::{~$<directive>.substr(0,4).tclc} !! TAP::No-Directive;
			%args<explanation> = ~$<explanation> if $<explanation>;
			return %args;
		}
		method test($/) {
			make TAP::Test.new(:raw(~$/), |self!make_test($/));
		}
		method bailout($/) {
			make TAP::Bailout.new(:raw(~$/), :explanation($<explanation> ?? ~$<explanation> !! Str));
		}
		method version($/) {
			make TAP::Version.new(:raw(~$/), :version(+$<version>));
		}
		method comment($/) {
			make TAP::Comment.new(:raw(~$/), :comment(~$<comment>));
		}
		method yaml($/) {
			my $serialized = $<yaml-line>.join('');
			require YAMLish;
			my $deserialized = YAMLish::load-yaml("---\n$serialized...");
			make TAP::YAML.new(:raw(~$/), :$serialized, :$deserialized);
		}
		method sub-entry($/) {
			make $/.values[0].made;
		}
		method sub-test($/) {
			make TAP::Sub-Test.new(:raw(~$/), :entries(@<sub-entry>».made), |self!make_test($<test>));
		}
		method unknown($/) {
			make TAP::Unknown.new(:raw(~$/));
		}
	}

	class Parser {
		has Str $!buffer = '';
		has TAP::Entry::Handler @!handlers;
		has Grammar $!grammar = Grammar.new;
		has Action $!actions = Action.new;
		submethod BUILD(:@!handlers) { }
		method add-data(Str $data) {
			$!buffer ~= $data;
			while ($!grammar.subparse($!buffer, :$!actions)) -> $match {
				$!buffer.=substr($match.to);
				for @($match.made) -> $result {
					@!handlers».handle-entry($result);
				}
			}
		}
		method close-data() {
			if $!buffer.chars {
				warn "Unparsed data left at end of stream: $!buffer";
			}
			@!handlers».end-entries();
		}
	}

	enum Formatter::Volume <Silent ReallyQuiet Quiet Normal Verbose>;
	role Formatter {
		has Bool $.timer = False;
		has Formatter::Volume $.volume = Normal;
	}
	role Reporter {
		method summarize(TAP::Aggregator, Bool $interrupted) { ... }
		method open-test(Str $) { ... }
	}

	class TAP::Reporter::Text { ... }
	role Reporter::Text::Session does TAP::Session {
		has TAP::Reporter $.reporter;
		has Str $.name;
		has Str $.header;
		method clear-for-close() {
		}
		method close-test(TAP::Result $result) {
			$!reporter.print-result(self, $result);
		}
		method handle-entry(TAP::Entry $) {
		}
	}
	class Formatter::Text does Formatter {
		has Int $!longest;

		submethod BUILD(:@names) {
			$!longest = @names ?? @names».chars.max !! 12;
		}
		method format-name($name) {
			my $periods = '.' x ( $!longest + 2 - $name.chars);
			my @now = $.timer ?? ~DateTime.new(now, :formatter{ '[' ~ .hour ~ ':' ~ .minute ~ ':' ~ .second.Int ~ ']' }) !! ();
			return (|@now, $name, $periods).join(' ');
		}
		method format-summary(TAP::Aggregator $aggregator, Bool $interrupted) {
			my @tests = $aggregator.descriptions;
			my $total = $aggregator.tests-run;
			my $passed = $aggregator.passed;
			my $output = '';

			if $interrupted {
				$output ~= self.format-failure("Test run interrupted!\n")
			}

			if $aggregator.failed == 0 {
				$output ~= self.format-success("All tests successful.\n");
			}

			if $total != $passed || $aggregator.has-problems {
				$output ~= "\nTest Summary Report";
				$output ~= "\n-------------------\n";
				for @tests -> $name {
					my $result = $aggregator.results-for{$name};
					if $result.has-problems {
						my $spaces = ' ' x min($!longest - $name.chars, 1);
						my $wait = $result.exit-status ?? 0 // '(none)' !! '(none)';
						my $line = "$name$spaces (Wstat: $wait Tests: {$result.tests-run} Failed: {$result.failed.elems})\n";
						$output ~= $result.has-errors ?? self.format-failure($line) !! $line;

						if $result.failed -> @failed {
							$output ~= self.format-failure('  Failed tests:  ' ~ @failed.join(' ') ~ "\n");
						}
						if $result.todo-passed -> @todo-passed {
							$output ~= "  TODO passed:  { @todo-passed.join(' ') }\n";
						}
						if $result.exit-status.defined { # XXX
							if $result.exit {
								$output ~= self.format-failure("Non-zero exit status: { $result.exit }\n");
							}
							elsif $result.wait {
								$output ~= self.format-failure("Non-zero wait status: { $result.wait }\n");
							}
						}
						if $result.errors -> @errors {
							my ($head, @tail) = @errors;
							$output ~= self.format-failure("  Parse errors: $head\n");
							for @tail -> $error {
								$output ~= self.format-failure(' ' x 16 ~ $error ~ "\n");
							}
						}
					}
				}
			}
			$output ~= "Files={ @tests.elems }, Tests=$total\n";
			my $status = $aggregator.get-status;
			$output ~= "Result: $status\n";
			return $output;
		}
		method format-success(Str $output) {
			return $output;
		}
		method format-failure(Str $output) {
			return $output;
		}
		method format-return(Str $output) {
			return $output;
		}
		method format-result(Reporter::Text::Session $session, TAP::Result $result) {
			my $output;
			my $name = $session.header;
			if ($result.skip-all) {
				$output = self.format-return("$name skipped");
			}
			elsif ($result.has-errors) {
				$output = self.format-test-failure($name, $result);
			}
			else {
				my $time = self.timer && $result.time ?? sprintf ' %8d ms', Int($result.time * 1000) !! '';
				$output = self.format-return("$name ok$time\n");
			}
			return $output;
		}
		method format-test-failure(Str $name, TAP::Result $result) {
			return if self.volume < Quiet;
			my $output = self.format-return("$name ");

			my $total = $result.tests-planned // $result.tests-run;
			my $failed = $result.failed + abs($total - $result.tests-run);

			if $result.exit -> $status {
				$output ~= self.format-failure("Dubious, test returned $status\n");
			}

			if $result.failed == 0 {
				$output ~= self.format-failure($total ?? "All $total subtests passed " !! 'No subtests run');
			}
			else {
				$output ~= self.format-failure("Failed {$result.failed}/$total subtests ");
				if (!$total) {
					$output ~= self.format-failure("\nNo tests run!");
				}
			}

			if $result.skipped.elems -> $skipped {
				my $passed = $result.passed.elems - $skipped;
				my $test = 'subtest' ~ ( $skipped != 1 ?? 's' !! '' );
				$output ~= "\n\t(less $skipped skipped $test: $passed okay)";
			}

			if $result.todo-passed.elems -> $todo-passed {
				my $test = $todo-passed > 1 ?? 'tests' !! 'test';
				$output ~= "\n\t($todo-passed TODO $test unexpectedly succeeded)";
			}

			$output ~= "\n";
			return $output;
		}
	}
	class Reporter::Text does Reporter {
		has IO::Handle $!handle;
		has Formatter::Text $!formatter;

		submethod BUILD(:@names, :$!handle = $*OUT, :$volume = Normal, :$timer = False) {
			$!formatter = Formatter::Text.new(:@names, :$volume, :$timer);
		}

		method open-test(Str $name) {
			my $header = $!formatter.format-name($name);
			return Formatter::Text::Session.new(:$name, :$header, :formatter(self));
		}
		method summarize(TAP::Aggregator $aggregator, Bool $interrupted) {
			self!output($!formatter.format-summary($aggregator, $interrupted));
		}
		method !output(Any $value) {
			$!handle.print($value);
		}
		method print-result(Reporter::Text::Session $session, TAP::Result $report) {
			self!output($!formatter.format-result($session, $report));
		}
	}

	class Formatter::Console is Formatter::Text {
		my &colored = do {
			try { require Term::ANSIColor }
			GLOBAL::Term::ANSIColor::EXPORT::DEFAULT::<&colored> // sub (Str $text, Str $) { $text };
		}
		method format-success(Str $output) {
			return colored($output, 'green');
		}
		method format-failure(Str $output) {
			return colored($output, 'red');
		}
		method format-return(Str $output) {
			return "\r$output";
		}
	}

	class Reporter::Console::Session does Reporter::Text::Session {
		has Int $!last-updated = 0;
		has Int $.plan = Int;
		has Int $.number = 0;
		proto method handle-entry(TAP::Entry $entry) {
			{*};
		}
		multi method handle-entry(TAP::Bailout $bailout) {
			my $explanation = $bailout.explanation // '';
			$!reporter.bailout($explanation);
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
	}
	class Reporter::Console does Reporter {
		has Bool $.parallel;
		has Formatter::Console $!formatter;
		has Int $!lastlength;
		has Supply $events;
		has Reporter::Console::Session @!active;
		has Int $!tests;
		has Int $!fails;

		submethod BUILD(:@names, IO::Handle :$handle = $*OUT, :$volume = Normal, :$timer = False) {
			$!formatter = Formatter::Console.new(:@names, :$volume, :$timer);
			$!lastlength = 0;
			$!events = Supply.new;
			@!active .= new;

			my $now = 0;
			my $start = now;

			sub output-ruler(Bool $refresh) {
				my $new-now = now;
				return if $now == $new-now and !$refresh;
				$now = $new-now;
				return if $!formatter.volume < Quiet;
				my $header = sprintf '===( %7d;%d', $!tests, $now - $start;
				my @items = @!active.map(-> $active { sprintf '%' ~ $active.plan.chars ~ "d/%d", $active.number, $active.plan });
				my $ruler = ($header, |@items).join('  ') ~ ')===';
				$handle.print($!formatter.format-return($ruler));
			}
			multi receive('update', Str $name, Str $header, Int $number, Int $plan) {
				if @!active.elems == 1 {
					my $status = ($header, $number, '/', $plan // '?').join('');
					$handle.print($!formatter.format-return($status));
					$!lastlength = $status.chars + 1;
				}
				else {
					output-ruler($number == 1);
				}
			}
			multi receive('bailout', Str $explanation) {
				$handle.print($!formatter.format-failure("Bailout called.  Further testing stopped: $explanation\n"));
			}
			multi receive('result', Reporter::Console::Session $session, TAP::Result $result) {
				$handle.print($!formatter.format-return(' ' x $!lastlength) ~ $!formatter.format-result($session, $result));
				@!active = @!active.grep(* !=== $session);
				output-ruler(True) if @!active.elems > 1;
			}
			multi receive('summary', TAP::Aggregator $aggregator, Bool $interrupted) {
				$handle.print($!formatter.format-summary($aggregator, $interrupted));
			}

			$!events.act(-> @args { receive(|@args) });
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
		method summarize(TAP::Aggregator $aggregator, Bool $interrupted) {
			$!events.emit(['summary', $aggregator, $interrupted]);
		}

		method open-test(Str $name) {
			my $header = $!formatter.format-name($name);
			my $ret = Reporter::Console::Session.new(:$name, :$header, :reporter(self));
			@!active.push($ret);
			return $ret;
		}
	}
	class Formatter::Console::Parallel is Formatter::Console {
		method update(Str $name, Str $header, Int $number, Str $planstr) {
		}
		method clear(TAP::Result $result) {
			...;
		}
	}

	package Runner { 
	class State does TAP::Entry::Handler {
		has Range $.allowed-versions = 12 .. 13;
		has Int $!tests-planned;
		has Int $!tests-run = 0;
		has Int @!passed;
		has Int @!failed;
		has Str @!errors;
		has Int @!actual-passed;
		has Int @!actual-failed;
		has Int @!todo;
		has Int @!todo-passed;
		has Int @!skipped;
		has Int $!unknowns = 0;
		has Bool $!skip-all = False;

		has Promise $.bailout;
		has Int $!seen-lines = 0;
		enum Seen <Unseen Before After>;
		has Seen $!seen-plan = Unseen;
		has Promise $.done = Promise.new;
		has Int $!version;

		proto method handle-entry(TAP::Entry $entry) {
			if $!seen-plan == After && $entry !~~ TAP::Comment {
				self!add-error("Got line $entry after late plan");
			}
			{*};
			$!seen-lines++;
		}
		multi method handle-entry(TAP::Version $entry) {
			if $!seen-lines {
				self!add-error('Seen version declaration mid-stream');
			}
			elsif $entry.version !~~ $!allowed-versions {
				self!add-error("Version must be in range $!allowed-versions");
			}
			else {
				$!version = $entry.version;
			}
		}
		multi method handle-entry(TAP::Plan $plan) {
			if $!seen-plan != Unseen {
				self!add-error('Seen a second plan');
			}
			else {
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
			if $!seen-plan == After {
				self!add-error("Plan must be at the beginning or end of the TAP output");
			}

			my $usable-number = $found-number // $expected-number;
			($test.is-ok ?? @!passed !! @!failed).push($usable-number);
			($test.ok ?? @!actual-passed !! @!actual-failed).push($usable-number);
			@!todo.push($usable-number) if $test.directive == TAP::Todo;
			@!todo-passed.push($usable-number) if $test.ok && $test.directive == TAP::Todo;
			@!skipped.push($usable-number) if $test.directive == TAP::Skip;

			if $test ~~ TAP::Sub-Test {
				for $test.inconsistencies(~$usable-number) -> $error {
					self!add-error($error);
				}
			}
		}
		multi method handle-entry(TAP::Bailout $entry) {
			if $!bailout.defined {
				$!bailout.keep($entry);
			}
			else {
				$!done.break($entry);
			}
		}
		multi method handle-entry(TAP::Unknown $) {
			$!unknowns++;
		}
		multi method handle-entry(TAP::Entry $entry) {
		}

		method end-entries() {
			if $!seen-plan == Unseen {
				self!add-error('No plan found in TAP output');
			}
			elsif $!tests-run != $!tests-planned {
				self!add-error("Bad plan.  You planned $!tests-planned tests but ran $!tests-run.");
			}
			$!done.keep;
		}
		method finalize(Str $name, Proc $exit-status, Duration $time) {
			return TAP::Result.new(:$name, :$!tests-planned, :$!tests-run, :@!passed, :@!failed, :@!errors, :$!skip-all,
				:@!actual-passed, :@!actual-failed, :@!todo, :@!todo-passed, :@!skipped, :$!unknowns, :$exit-status, :$time);
		}
		method !add-error(Str $error) {
			push @!errors, $error;
		}
	}

	class Async { ... }

	role Source {
		has Str $.name;
		method make-parser(:@handlers, Promise :$promise) {
			return Async.new(:source(self), :@handlers, :$promise);
		}
	}
	my class Run {
		subset Killable of Any where *.can('kill');
		has Killable $!process;
		has Promise:D $.done is required;
		has Promise $.timer;
		method kill() {
			$!process.kill if $!process;
		}
		method exit-status() {
			return $!done.result ~~ Proc ?? $.done.result !! Proc;
		}
		method time() {
			return $!timer.defined ?? $!timer.result !! Duration;
		}
	}
	class Source::Proc does Source {
		has IO::Path $.path;
		has @.args;
	}
	class Source::File does Source {
		has Str $.filename;
	}
	class Source::String does Source {
		has Str $.content;
	}
	class Source::Through does Source does TAP::Entry::Handler {
		has Promise $.done = Promise.new;
		has TAP::Entry @!entries;
		has Supply $!input = Supply.new;
		has Supply $!supply = Supply.new;
		has Promise $.promise = $!input.Promise;
		method staple(TAP::Entry::Handler @handlers) {
			for @!entries -> $entry {
				@handlers».handle-entry($entry);
			}
			$!input.act({
				@handlers».handle-entry($^entry);
				@!entries.push($^entry);
			}, :done({ @handlers».end-entries() }));
		}
		method handle-entry(TAP::Entry $entry) {
			$!input.emit($entry);
		}
		method end-entries() {
			$!input.done();
		}
	}

	class Async {
		has Str $.name;
		has Run $!run;
		has State $!state;
		has Promise $.done;

		submethod BUILD(Str :$!name, State :$!state, Run :$!run) {
			$!done = Promise.allof($!state.done, $!run.done);
		}

		multi get_runner(Source::Proc $proc; TAP::Entry::Handler @handlers) {
			my $process = Proc::Async.new($proc.path, $proc.args);
			my $lexer = TAP::Parser.new(:@handlers);
			$process.stdout().act({ $lexer.add-data($^data) }, :done({ $lexer.close-data() }));
			my $done = $process.start();
			my $start-time = now;
			my $timer = $done.then({ now - $start-time });
			return Run.new(:$done, :$process, :$timer);
		}
		multi get_runner(Source::Through $through; TAP::Entry::Handler @handlers) {
			$through.staple(@handlers);
			return Run.new(:done($through.promise));
		}
		multi get_runner(Source::File $file; TAP::Entry::Handler @handlers) {
			my $lexer = TAP::Parser.new(:@handlers);
			return Run.new(:done(start {
				$lexer.add-data($file.filename.IO.slurp);
				$lexer.close-data();
			}));
		}
		multi get_runner(Source::String $string; TAP::Entry::Handler @handlers) {
			my $lexer = TAP::Parser.new(:@handlers);
			$lexer.add-data($string.content);
			$lexer.close-data();
			my $done = Promise.new;
			$done.keep;
			return Run.new(:$done);
		}

		method new(Source :$source, :@handlers, Promise :$bailout) {
			my $state = State.new(:$bailout);
			my TAP::Entry::Handler @all_handlers = $state, |@handlers;
			my $run = get_runner($source, @all_handlers);
			return Async.bless(:name($source.name), :$state, :$run);
		}

		method kill() {
			$!run.kill();
			$!done.break("killed") if not $!done;
		}

		has TAP::Result $!result;
		method result {
			await $!done;
			return $!result //= $!state.finalize($!name, $!run.exit-status, $!run.time);
		}

	}

	class Sync {
		has Source $.source;
		has @.handlers;
		has Str $.name = $!source.name;

		method run(Promise :$bailout) {
			my $state = State.new(:$bailout);
			my TAP::Entry::Handler @handlers = $state, |@!handlers;
			my $start-time = now;
			given $!source {
				when Source::Proc {
					my $parser = TAP::Parser.new(:@handlers);
					my $proc = run($!source.path, $!source.args, :out, :!chomp);
					for $proc.out.lines -> $line {
						$parser.add-data($line);
					}
					$parser.close-data();
					return $state.finalize($!name, $proc, now - $start-time);
				}
				when Source::Through {
					$!source.staple(@handlers);
					$!source.promise.result;
					return $state.finalize($!name, Proc, now - $start-time);
				}
				when Source::File {
					my $parser = TAP::Parser.new(:@handlers);
					$parser.add-data($!source.filename.IO.slurp);
					$parser.close-data();
					return $state.finalize($!name, Proc, now - $start-time);
				}
				when Source::String {
					my $parser = TAP::Parser.new(:@handlers);
					$parser.add-data($!source.content);
					$parser.close-data();
					return $state.finalize($!name, Proc, now - $start-time);
				}
			}
		}
	}
	}
}

class TAP::Harness {
	role SourceHandler {
		method can-handle {...};
		method make-source {...};
	}
	class SourceHandler::Perl6 does SourceHandler {
		method can-handle($name) {
			return 0.5;
		}
		method make-source($name) {
			return TAP::Runner::Source::Proc.new(:$name, :path($*EXECUTABLE), :args[$name]);
		}
	}

	has SourceHandler @.handlers = SourceHandler::Perl6.new();
	has Any @.sources;
	has TAP::Reporter:U $.reporter-class = TAP::Reporter::Console;

	class Run {
		has Promise $.waiter handles <result>;
		has Promise $!killed;
		submethod BUILD (Promise :$!waiter, Promise :$!killed) {
		}
		method kill(Any $reason = True) {
			$!killed.keep($reason);
		}
	}

	method run(Int :$jobs = 1, Bool :$timer = False) {
		my $killed = Promise.new;
		my $aggregator = TAP::Aggregator.new();
		my $reporter = $!reporter-class.new(:parallel($jobs > 1), :names(@.sources), :$timer, :$aggregator);
		if $jobs > 1 {
			my @working;
			my $waiter = start {
				for @!sources -> $name {
					last if $killed;
					my $session = $reporter.open-test($name);
					my $source = @!handlers.max(*.can-handle($name)).make-source($name);
					my $parser = TAP::Runner::Async.new(:$source, :handlers[$session], :$killed);
					@working.push({ :$parser, :$session, :done($parser.done) });
					next if @working < $jobs;
					await Promise.anyof(@working»<done>, $killed);
					reap-finished();
				}
				await Promise.anyof(Promise.allof(@working»<done>), $killed) if @working and not $killed;
				reap-finished();
				@working».kill if $killed;
				$reporter.summarize($aggregator, ?$killed);
				$aggregator;
			}
			sub reap-finished() {
				my @new-working;
				for @working -> $current {
					if $current<done> {
						$aggregator.add-result($current<parser>.result);
						$current<session>.close-test($current<parser>.result);
					}
					else {
						@new-working.push($current);
					}
				}
				@working = @new-working;
			}
			return Run.new(:$waiter, :$killed);
		}
		else {
			my $waiter = start {
				for @!sources -> $name {
					last if $killed;
					my $session = $reporter.open-test($name);
					my $source = @!handlers.max(*.can-handle($name)).make-source($name);
					my $parser = TAP::Runner::Sync.new(:$source, :handlers[$session]);
					my $result = $parser.run(:$killed);
					$aggregator.add-result($result);
					$session.close-test($result);
				}
				$reporter.summarize($aggregator, ?$killed);
				$aggregator;
			}
			return Run.new(:$waiter, :$killed);
		}
	}
}

