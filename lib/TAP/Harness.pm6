use TAP::Parser;

class TAP::Harness {
	role SourceHandler {
		method can_handle {...};
		method make_source {...};
	}
	class SourceHandler::Perl6 does SourceHandler {
		method can_handle($filename) {
			return 1;
		}
		method make_source($filename) {
			return TAP::Parser::Source::Proc.new(:path($*EXECUTABLE), :args([$filename]));
		}
	}

	has SourceHandler @.handlers = SourceHandler::Perl6.new();
	has Any @.sources;
	has TAP::Parser::Formatter:T $.formatter-class = TAP::Parser::Formatter::Console;

	class Run {
		has Promise $.done;
		has Promise $!kill;
		method kill(Any $reason = True) {
			$!kill.keep($reason) = Promise.new;
		}
		method result() {
			return $!done.result;
		}
	}

	method run(Int :$parallel = 2, TAP::Parser::Formatter :$formatter = $!formatter-class.new(:$parallel, :names(@.sources))) {
		my @working;
		my $kill = Promise.new;
		my $aggregator = TAP::Parser::Aggregator.new();
		my $done = start {
			for @!sources -> $name {
				last if $kill;
				my $source = @!handlers.max(*.can_handle($name)).make_source($name);
				my $session = $formatter.open-test($name);
				@working.push(TAP::Parser.new(:$name, :$source, :$session, :$kill));
				next if @working < $parallel;
				await Promise.anyof(@working.map(*.done), $kill);
				reap-finished();
			}
			await Promise.anyof(Promise.allof(@working.map(*.done)), $kill) if not $kill;
			reap-finished();
			if ($kill) {
				.kill for @working;
			}
			$aggregator;
		};
		sub reap-finished() {
			my @new-working;
			for @working -> $current {
				if $current.done {
					$aggregator.add-result($current.result);
					$current.session.close-test($current.result);
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
