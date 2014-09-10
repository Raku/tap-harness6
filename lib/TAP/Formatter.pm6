use TAP::Entry;
use TAP::Result;

package TAP {
	role Formatter {
		method summarize(TAP::Aggregator) { ... }
		method open-test(Str $) { ... }
	}
	enum Formatter::Volume <Silent ReallyQuiet Quiet Normal Verbose>;

	role Formatter::Text does Formatter {
		has Bool $.parallel;
		has Formatter::Volume $.volume;

		has Int $!longest;
		method BUILD(:$!parallel, :$!volume = Normal, :@names) {
			$!longest = @names ?? @names.map(*.chars).max !! 12;
		}
		method format-name($name) {
			my $periods = '.' x ( $!longest + 2 - $name.chars);
			return "$name $periods ";
		}
		method summarize(TAP::Aggregator $aggregator) {
			my @tests = $aggregator.descriptions;
			my $total = $aggregator.tests-run;
			my $passed = $aggregator.passed;

			if $aggregator.failed == 0 {
				self.success-output("All tests successful.\n");
			}

			if ($total != $passed || $aggregator.has-problems) {
				self.output("\nTest Summary Report");
				self.output("\n-------------------\n");
				for @tests -> $name {
					my $result = $aggregator.results-for{$name};
					if $result.has-problems {
						my $spaces = ' ' x min($!longest - $name.chars, 1);
						my $method = $result.has-errors ?? 'failure-output' !! 'output';
						my $wait = $result.exit-status ?? 0 // '(none)' !! '(none)';
						self."$method"("$name$spaces (Wstat: $wait Tests: {$result.tests-run} Failed: {$result.failed.elems})\n");

						if $result.failed -> @failed {
							self.failure-output('  Failed tests:  ' ~ @failed.join(' ') ~ "\n");
						}
						if $result.todo-passed -> @todo-passed {
							self.failure-output('  TODO passed:  ' ~ @todo-passed.join(' ') ~ "\n");
						}
						if $result.exit-status.?exit { # XXX
							if $result.exit-status.exit {
								self.failure-output("Non-zero exit status: { $result.exit-status.exit }\n");
							}
							else {
								self.failure-output("Non-zero wait status: { $result.exit-status.status }\n");
							}
						}
						if $result.errors -> @errors {
							my ($head, @tail) = @errors;
							self.failure-output("  Parse errors: $head\n");
							for @tail -> $error {
								self.failure-output(' ' x 16 ~ $error ~ "\n");
							}
						}
					}
				}
			}
			self.output("Files={ @tests.elems }, Tests=$total\n");
			my $status = $aggregator.get-status;
			self.output("Result: $status\n");
		}
		method output(Any $value) {
			$.handle.print($value);
		}
		method success-output(Str $output) {
			self.output($output);
		}
		method failure-output(Str $output) {
			self.output($output);
		}
	}
	role Formatter::Text::Session does TAP::Session {
		has TAP::Formatter::Text $.formatter;
		has Str $.name;
		has Str $!pretty = $!formatter.format-name($!name);
		method header {
			return $!name;
		}
		method clear-for-close() {
		}
		method output-return(Str $output) {
			self.output($output);
		}
		method output-test-failure(TAP::Result $result) {
			return if $!formatter.volume < Quiet;
			self.output-return($!pretty);

			my $total = $result.tests-planned // $result.test-run;
			my $failed = $result.failed + abs($total - $result.tests-run);

			if $result.exit -> $status {
				$!formatter.failure-output("Dubious, test returned $status\n");
			}

			if $result.failed == 0 {
				$!formatter.failure-output($total ?? "All $total subtests passed " !! 'No subtests run');
			}
			else {
				$!formatter.failure-output("Failed {$result.failed}/$total subtests ");
				if (!$total) {
					$!formatter.failure-output("\nNo tests run!");
				}
			}

			if $result.skipped.elems -> $skipped {
				my $passed = $result.passed.elems - $skipped;
				my $test = 'subtest' ~ ( $skipped != 1 ?? 's' !! '' );
				$!formatter.output("\n\t(less $skipped skipped $test: $passed okay)");
			}

			if $result.todo-passed.elems -> $todo-passed {
				my $test = $todo-passed > 1 ?? 'tests' !! 'test';
				$!formatter.output("\n\t($todo-passed TODO $test unexpectedly succeeded)");
			}

			$!formatter.output("\n");
		}
		method close-test(TAP::Result $result) {
			self.clear-for-close($result);
			if ($result.skip-all) {
				self.output-return("$!pretty skipped");
			}
			elsif ($result.has-errors) {
				self.output-test-failure($result);
			}
			else {
				self.output-return("$!pretty ok\n");
			}
		}
	}

	class Formatter::Console does Formatter::Text {
		class Session does Formatter::Text::Session {
			has TAP::Plan $!plan;
			has Int $!last-updated = 0;
			has Str $!planstr = '/?';
			has Int $!number = 0;
			method handle-entry(TAP::Entry $entry) {
				#$.formatter.output($entry.perl ~ "\n");
				given $entry {
					when TAP::Bailout {
						self.failure-output("Bailout called.  Further testing stopped:  {$entry.explanation}\n");
					}
					when TAP::Plan {
						$!plan = $entry;
						$!planstr = '/' ~ $entry.tests;
					}
					when TAP::Test {
						my $now = time;
						if $!last-updated != $now {
							$!last-updated = $now;
							self.output-return(($!pretty, ++$!number, $!planstr).join(''));
						}
					}
					when TAP::Comment {
					}
				}
			}
			method output(Str $output) {
				$!formatter.output($output);
			}
			method output-return(Str $output) {
				self.output("\r$output");
			}
			method clear-for-close(TAP::Result $result) {
				my $length = ($!pretty ~ $!planstr ~ $result.tests-run).chars + 1;
				self.output-return(' ' x $length);
			}
		}
		class Session::Parallel is Session {
			method handle-entry(TAP::Entry $entry) {
				nextsame;
			}
			method close-test(TAP::Result $result) {
				nextsame;
			}
			method clear-for-close(TAP::Result $result) {
				nextsame;
			}
		}

		has IO::Handle $.handle = $*OUT;
		method open-test(Str $name) {
			my $session-class = $.parallel ?? Session::Parallel !! Session;
			return $session-class.new(:$name, :formatter(self));
		}
	}
}
