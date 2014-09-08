use TAP::Parser;
use TAP::Result;

package TAP {
	role Formatter {
		enum Volume <Silent ReallyQuiet Quiet Normal Verbose>;

		has Int $.parallel;
		has Volume $.volume;
		has Int $!longest;

		method BUILD(:$!parallel, :$!volume = Normal, :@names) {
			$!longest = @names ?? @names.map(*.chars).max !! 12;
		}
		method summary(TAP::Aggregator $aggregator) {
			my @tests = $aggregator.descriptions;
			my $total = $aggregator.tests-run;
			my $passed = $aggregator.passed;

			if $aggregator.failed == 0 {
				self.output-success("All tests successful.\n");
			}
		}
		method output-success(Mu \output) {
			self.output(output);
		}
		method output { ... }
		method open-test { ... }
		method format_name($name) {
			my $periods = '.' x ( $!longest + 2 - $name.chars);
			return "$name $periods ";
		}
	}

	class Session::Console does TAP::Parser::Session {
		has TAP::Formatter $.formatter;
		has Str $!pretty = $!formatter.format_name($!name);
		has TAP::Plan $!plan;
		has Int $!last-updated = 0;
		has Str $!planstr = '/?';
		method handle-entry(TAP::Entry $entry) {
			#$.formatter.output($entry.perl ~ "\n");
			given $entry {
				when TAP::Bailout {
				}
				when TAP::Plan {
					$!plan = $entry;
					$!planstr = '/' ~ $entry.tests;
				}
				when TAP::Test {
					my $number = $entry.number;
					my $now = time;
					if $!last-updated != $now {
						$!last-updated = $now;
						$!formatter.output(("\r", $!pretty, $number, $!planstr).join(''));
					}
				}
				when TAP::Comment {
				}
			}
		}
		method output-test-failure(TAP::Result $result) {
			$.formatter.output("\r$!pretty failed {$result.failed} tests\n");
		}
		method clear-for-close(TAP::Result $result) {
			my $length = ($!pretty ~ $!planstr ~ $result.tests-run).chars + 1;
			$!formatter.output("\r" ~ (' ' x $length));
		}

		method close-test(TAP::Result $result) {
			self.clear-for-close($result);
			if ($result.skip-all) {
				$!formatter.output("\r$!pretty skipped");
			}
			elsif ($result.failed == 0) {
				$!formatter.output("\r$!pretty ok\n");
			}
			else {
				self.output-rest-failure($result);
			}
		}
	}
	class Session::Console::Parallel is Session::Console {
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

	class Formatter::Console does Formatter {
		has IO::Handle $.handle = $*OUT;
		method output(Any $value) {
			$.handle.print($value);
		}
		method open-test(Str $name) {
			my $session-class = $!parallel ?? Session::Console::Parallel !! Session::Console;
			return $session-class.new(:$name, :formatter(self));
		}
	}
}
