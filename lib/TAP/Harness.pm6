use TAP::Parser;
use TAP::Entry;
use TAP::Result;
use TAP::Formatter;

package TAP::Runner {
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
			if $!seen-plan {
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
			if !$!seen-plan {
				self!add-error('No plan found in TAP output');
			}
			elsif $!tests-run != $!tests-planned {
				self!add-error("Bad plan.  You planned $!tests-planned tests but ran $!tests-run.");
			}
			$!done.keep;
		}
		method finalize(Str $name, Proc::Status $exit-status, Duration $time) {
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
		method run(Supply) { ... }
		method make-parser(:@handlers, Promise :$promise) {
			return Async.new(:source(self), :@handlers, :$promise);
		}
	}
	my class Run {
		subset Killable of Any where *.can('kill');
		has Killable $!process;
		has Promise:D $.done;
		has Promise $.timer;
		method kill() {
			$!process.kill if $!process;
		}
		method exit-status() {
			return $!done.result ~~ Proc::Status ?? $.done.result !! Proc::Status;
		}
		method time() {
			return $!timer.defined ?? $!timer.result !! Duration;
		}
	}
	class Source::Proc does Source {
		has IO::Path $.path;
		has @.args;
		method run(Supply $output) {
			my $process = Proc::Async.new($!path, @!args);
			my $lexer = TAP::Parser.new(:$output);
			$process.stdout().act({ $lexer.add-data($^data) }, :done({ $lexer.close-data() }));
			my $done = $process.start();
			my $start-time = now;
			my $timer = $done.then({ now - $start-time });
			return Run.new(:$done, :$process, :$timer);
		}
	}
	class Source::File does Source {
		has Str $.filename;

		method run(Supply $output) {
			my $lexer = TAP::Parser.new(:$output);
			return Run.new(:done(start {
				$lexer.add-data($!filename.IO.slurp);
				$lexer.close-data();
			}));
		}
	}
	class Source::String does Source {
		has Str $.content;
		method run(Supply $output) {
			my $lexer = TAP::Parser.new(:$output);
			$lexer.add-data($!content);
			sleep 1;
			$lexer.close-data();
			my $done = Promise.new;
			$done.keep;
			return Run.new(:$done);
		}
	}
	class Source::Through does Source does TAP::Entry::Handler {
		has Promise $.done = Promise.new;
		has TAP::Entry @!entries;
		has Supply $!input = Supply.new;
		has Supply $!supply = Supply.new;
		method run(Supply $output) {
			for @!entries -> $entry {
				$output.emit($entry);
			}
			$!input.act({
				$output.emit($^entry);
				@!entries.push($^entry);
			}, :done({ $output.done() }));
			return Run.new(:done($!input.Promise));
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

		method new(Source :$source, :@handlers, Promise :$bailout) {
			my $entries = Supply.new;
			my $state = State.new(:$bailout);
			for $state, @handlers -> $handler {
				$entries.act({ $handler.handle-entry($^entry) }, :done({ $handler.end-entries() }));
			}
			my $run = $source.run($entries);
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
}

class TAP::Harness {
	role SourceHandler {
		method can-handle {...};
		method make-async-source {...};
		method make-async-parser(Any :$name, :@handlers, Promise :$bailout) {
			my $source = self.make-async-source($name);
			return TAP::Runner::Async.new(:$source, :@handlers :$bailout);
		}
	}
	class SourceHandler::Perl6 does SourceHandler {
		method can-handle($name) {
			return 0.5;
		}
		method make-async-source($name) {
			return TAP::Runner::Source::Proc.new(:$name, :path($*EXECUTABLE), :args[$name]);
		}
	}

	has SourceHandler @.handlers = SourceHandler::Perl6.new();
	has Any @.sources;
	has TAP::Formatter:T $.formatter-class = TAP::Formatter::Console;

	class Run {
		has Promise $.done handles <result>;
		has Promise $!kill;
		method kill(Any $reason = True) {
			$!kill.keep($reason);
		}
	}

	method run(Int :$jobs = 1, Bool :$timer = False, TAP::Formatter :$formatter = $!formatter-class.new(:parallel($jobs > 1), :names(@.sources), :$timer)) {
		my @working;
		my $kill = Promise.new;
		my $aggregator = TAP::Aggregator.new();
		my $done = start {
			for @!sources -> $name {
				last if $kill;
				my $session = $formatter.open-test($name);
				my $parser = @!handlers.max(*.can-handle($name)).make-async-parser(:$name, :handlers[$session], :$kill);
				@working.push({ :$parser, :$session, :done($parser.done) });
				next if @working < $jobs;
				await Promise.anyof(@working»<done>, $kill);
				reap-finished();
			}
			await Promise.anyof(Promise.allof(@working»<done>), $kill) if @working and not $kill;
			reap-finished();
			@working».kill if $kill;
			$formatter.summarize($aggregator, ?$kill);
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
		return Run.new(:$done, :$kill);
	}
}
