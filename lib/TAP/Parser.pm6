use TAP::Lexer;
use TAP::Entry;
use TAP::Result;

package TAP::Parser {
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
		has Bool $!skip-all = False;

		has Promise $.bailout;
		has Int $!seen-lines = 0;
		enum Seen <Unseen Before After>;
		has Seen $!seen-plan = Unseen;
		has Promise $.done = Promise.new;
		has Int $!version;

		method handle-entry(TAP::Entry $entry) {
			given $entry {
				when TAP::Version {
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
				when TAP::Plan {
					if $!seen-plan {
						self!add-error('Seen a second plan');
					}
					else {
						$!tests-planned = $entry.tests;
						$!seen-plan = $!tests-run ?? After !! Before;
						$!skip-all = $entry.skip-all;
					}
				}
				when TAP::Test {
					my $found-number = $entry.number;
					my $expected-number = ++$!tests-run;
					if $found-number.defined && ($found-number != $expected-number) {
						self!add-error("Tests out of sequence.  Found ($found-number) but expected ($expected-number)");
					}
					if $!seen-plan == After {
						self!add-error("Plan must be at the beginning or end of the TAP output");
					}
					my $usable-number = $found-number // $expected-number;
					($entry.is-ok ?? @!passed !! @!failed).push($usable-number);
					($entry.ok ?? @!actual-passed !! @!actual-failed).push($usable-number);
					@!todo.push($usable-number) if $entry.directive ~~ TAP::Todo;
					@!todo-passed.push($usable-number) if $entry.ok && $entry.directive == TAP::Todo;
					@!skipped.push($usable-number) if $entry.directive == TAP::Skip;
					when TAP::Sub-Test {
						if !$entry.is-consistent {
							self!add-error("Subtest $usable-number isn't coherent");
						}
					}
				}
				when TAP::Bailout {
					if $!bailout.defined {
						$!bailout.keep($entry);
					}
					else {
						$!.done.break($entry);
					}
				}
				when TAP::Comment {
				}
				default {
					if $!seen-plan == After {
						self!add-error("Got line {$/.Str} after late plan");
					}
				}
			}
			$!seen-lines++;
		}
		method end-entries() {
			if !$!seen-plan {
				self!add-error('No plan found in TAP output');
				if $!tests-run != ($!tests-planned || 0) {
					if defined $!tests-planned {
						self!add-error("Bad plan.  You planned $!tests-planned tests but ran $!tests-run.");
					}
				}
			}
			$!done.keep(True);
		}
		method finalize(Str $name, Proc::Status $exit-status) {
			return TAP::Result.new(:$name, :$!tests-planned, :$!tests-run, :@!passed, :@!failed, :@!errors, :$!skip-all,
				:@!actual-passed, :@!actual-failed, :@!todo, :@!todo-passed, :@!skipped, :$exit-status);
		}
		method !add-error(Str $error) {
			push @!errors, $error;
		}
	}

	class Async {
		role Source {
			has Str $.name;
			method run(Supply) { ... }
			method make-parser(:@handlers, Promise :$bailout) {
				my $entries = Supply.new;
				my $state = State.new(:$bailout);
				for $state, @handlers -> $handler {
					$entries.act(-> $entry { $handler.handle-entry($entry) }, :done(-> { $handler.end-entries() }));
				}
				my $run = self.run($entries);
				return Async.new(:$!name, :$state, :$run);
			}
		}
		class Run {
			has Any $!process where *.can('kill');
			has Promise:D $.done;
			method kill() {
				$!process.kill if $!process;
			}
			method exit-status() {
				$.done && $.done.result ~~ Proc::Status ?? $.done.result !! Proc::Status;
			}
		}

		has Str $.name;
		has Run $!run;
		has State $!state;
		has Promise $.done;

		submethod BUILD(Str :$!name, State :$!state, Run :$!run) {
			$!done = Promise.allof($!state.done, $!run.done);
		}

		method kill() {
			$!run.kill();
			$!done.break("killed") if not $!done;
		}

		has TAP::Result $!result;
		method result {
			return $!done ?? $!result //= $!state.finalize($!name, $!run.exit-status) !! TAP::Result;
		}

		class Source::Proc does Source {
			has IO::Path $.path;
			has @.args;
			method run(Supply $output) {
				my $process = Proc::Async.new(:$!path, :@!args);
				my $input = $process.stdout_chars();
				my $lexer = TAP::Lexer.new(:$output);
				$input.act(-> $data { $lexer.add-data($data) }, :done({ $lexer.close-data() }));
				return Run.new(:done($process.start()), :$process);
			}
		}
		class Source::File does Source {
			has Str $.filename;

			method run(Supply $output) {
				my $lexer = TAP::Lexer.new(:$output);
				return Run.new(:done(start {
					$lexer.add-data($!filename.IO.slurp);
					$lexer.close-data();
				}));
			}
		}
		class Source::Through does Source does TAP::Entry::Handler {
			has Promise $.done = Promise.new;
			has TAP::Entry @!entries;
			has Supply $!input = Supply.new;
			has Supply $!supply = Supply.new;
			method run(Supply $output) {
				for @!entries -> $entry {
					$output.more($entry);
				}
				$!input.act(-> $entry {
					$output.more($entry);
					@!entries.push($entry);
				}, :done({ $output.done() }));
				return Run.new(:done($!input.Promise));
			}
			method handle-entry(TAP::Entry $entry) {
				$!input.more($entry);
			}
			method end-entries() {
				$!input.done();
			}
		}
	}
}
