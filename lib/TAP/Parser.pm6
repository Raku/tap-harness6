use TAP::Lexer;
use TAP::Entry;
use TAP::Result;

package TAP::Parser {
	class State does TAP::Entry::Handler {
		has Range $.allowed-versions = 12 .. 13;
		has Int $!tests-planned;
		has Int $!tests-run = 0;
		has Int $!passed = 0;
		has Int $!failed = 0;
		has Str @!errors;
		has Bool $!skip-all = False;;

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
						$!skip-all = ?$entry.directive;
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
					($entry.is-ok ?? $!passed !! $!failed)++;
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
		method end-input() {
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
			return TAP::Result.new(:$name, :$!tests-planned, :$!tests-run, :$!passed, :$!failed, :@!errors, :$!skip-all, :$exit-status);
		}
		method !add-error(Str $error) {
			push @!errors, $error;
		}
	}

	class Async {
		role Source {
			method start(Supply) { ... }
			method done() { ... }
			method kill() { }
			method exit-status() { Proc::Status }
		}

		has Str $.name;
		has Source $!source;
		has State $!state;
		has Promise $.done;
		has TAP::Session $.session;

		submethod BUILD(Str :$!name, Source :$!source, :$!session = TAP::Session, TAP::Entry::Handler :@handlers = Array[TAP::Entry::Handler].new, Promise :$bailout = Promise) {
			my $entries = Supply.new;
			$!state = State.new(:$bailout);
			$entries.tap(-> $entry { $!state.handle-entry($entry) }, :done(-> { $!state.end-input() }));
			for ($!session, @handlers) -> $handler {
				$entries.tap(-> $entry { $handler.handle-entry($entry) }) if $handler.defined;
			}

			$!source.start($entries);
			$!done = Promise.allof($!state.done, $!source.done);
		}

		method kill() {
			$!source.kill();
			$!done.break("killed") if not $!done;
		}

		has TAP::Result $!result;
		method result {
			return $!done ?? $!result //= $!state.finalize($!name, $!source.exit-status) !! Nil;
		}

		class Source::Proc does Source {
			has Proc::Async $!process;
			has Supply $!input;
			has Promise $.done;
			submethod BUILD(:$path, :$args) {
				$!process = Proc::Async.new(:$path, :$args);
				$!input = $!process.stdout_chars();
			}
			method start(Supply $output) {
				my $lexer = TAP::Lexer.new(:$output);
				my $done = False;
				$!input.act(-> $data { $lexer.add-data($data) }, :done({ $output.done() if !$done++; }));
				$!done = $!process.start();
			}
			method kill() {
				$!process.kill();
			}
			method exit-status {
				return $!done ?? $!done.result !! nextsame;
			}
		}
		class Source::File does Source {
			has Str $.filename;
			has Thread $.done;
			submethod BUILD(Str :$!filename) { }
			method start(Supply $output) {
				my $lexer = TAP::Lexer.new(:$output);
				$!done = start {
					$lexer.add-data($!filename.IO.slurp);
					$output.done();
				};
			}
		}
	}
}
