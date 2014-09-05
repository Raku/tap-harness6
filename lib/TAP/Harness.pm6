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

	has SourceHandler @!handlers = SourceHandler::Perl6.new();
	has Any @.sources;

	method run(:$parallel = 2) {
		my (@working, @parsed);
		return start {
			for @!sources -> $source-name {
				my $source = @!handlers.max(*.can_handle($source-name)).make_source($source-name);
				@working.push(TAP::Parser.new(:$source));
				next if @working < $parallel;
				await Promise.anyof(@working.map(*.done));
				reap-finished();
			}
			await Promise.allof(@working.map(*.done));
			reap-finished();
			@parsed;
		};
		sub reap-finished() {
			@parsed.push(@working.grep(*));
			@working .= grep(!*);
		}
	}
}
