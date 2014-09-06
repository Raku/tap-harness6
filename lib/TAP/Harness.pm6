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
	has Promise $!kill = Promise.new;

	method run(Int :$parallel = 2) {
		my (@working, @results);
		return start {
			for @!sources -> $name {
				last if $!kill;
				my $source = @!handlers.max(*.can_handle($name)).make_source($name);
				@working.push(TAP::Parser.new(:$name, :$source, :$!kill));
				next if @working < $parallel;
				await Promise.anyof(@working.map(*.done), $!kill);
				reap-finished();
			}
			await Promise.anyof(Promise.allof(@working.map(*.done)), $!kill) if not $!kill;
			reap-finished();
			if ($!kill) {
				.kill for @working;
			}
			@results;
		};
		sub reap-finished() {
			@results.push(@working.grep(*).map(*.result));
			@working .= grep(!*);
		}
	}
	method kill(Any $reason = True) {
		$!kill.keep($reason);
	}
}
