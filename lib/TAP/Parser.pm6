class TAP::Parser {
	role Source {
		method input() {...}
		method done() {...}
		method kill() { }
	}

	class Lexer { ... }

	has Source $!source;
	has Supply $!lexer_stream;
	has Lexer $!lexer;
	has Promise $.done;

	submethod BUILD(Source :$!source) {
		$!lexer = Lexer.new(:input($!source.input));
		my $parsed = Promise.new;
		$!lexer.output.act(-> $result { self!handle_result($result) }, :done(-> { self!finalize(); $parsed.keep(True) }));
		$!done = Promise.allof($parsed, $!source.done);
	}

	class Source::Proc does Source {
		has Proc::Async $!process;
		has Supply $.input;
		has Promise $.done;
		submethod BUILD(:$path, :$args) {
			$!process = Proc::Async.new(:$path, :$args);
			$!input = $!process.stdout_chars();
			$!done = $!process.start();
		}
		method kill {
			$!process.kill;
		}
	}
	class Source::File does Source {
		has Str $.filename;
		has Supply $.input = Supply.new;
		has Thread $.done = start {
			my $fh = open $!filename, :r;
			for $fh.lines -> $line {
				$!input.more($line);
			}
			$!input.done();
		};
	}

	role Result {
		has Str $.raw = !!! 'Raw input is required';
	}
	class Version does Result {
		has Int $.version;
	}
	class Plan does Result {
		has Int $.tests = !!! 'tests is required';
		has Str $.directive;
		has Str $.explanation;
		has Int @.todo_list;
	}
	class Test does Result {
		has Bool $.ok;
		has Int $.number;
		has Str $.description;
	}
	class Bailout does Result {
		has Str $.explanation;
	}
	class Comment does Result {
		has Str $.comment = !!! 'comment is required';
	}
	class Unknown does Result {
	}

	has Int $.tests-planned;
	has Int $!seen-anything = 0;
	has Bool $!seen-plan = False;
	has Int $!tests-run = 0;
	has Int $.passed = 0;
	has Int $.failed = 0;
	has Str @.warnings;

	method !handle_result(Result $result) {
		given $result {
			when Plan {
				if $!seen-plan {
					self!add_warning('Seen a second plan');
				}
				else {
					$!tests-planned = $result.tests;
					$!seen-plan = True;
				}
			}
			when Test {
				my $found-number = $result.number;
				my $expected-number = ++$!tests-run;
				if $found-number.defined && ($found-number != $expected-number) {
					self!add_warning("Tests out of sequence.  Found ($found-number) but expected ($expected-number)");
				}
				($result ?? $!passed !! $!failed)++;
			}
			default {
				...;
			}
		}
		$!seen-anything++;
	}
	method !finalize() {
		if !$!seen-plan {
			self!add_warning('No plan found in TAP output');
			if $!tests-run != ($!tests-planned || 0) {
				if defined $!tests-planned {
					self!add_warning("Bad plan.  You planned $!tests-planned tests but ran $!tests-run.");
				}
			}
		}
	}

	method !add_warning($warning) {
		push @!warnings, $warning;
	}

	class Lexer {
		has Supply $.input;
		has Str $!buffer;
		has Supply $.output;
		has Bool $!done;

		submethod BUILD(Supply:D :$!input, Supply:D :$!output = Supply.new) {
			$!buffer = '';
			$!input.act(-> $data {
				$!buffer ~= $data;
				while ($!buffer ~~ / $<line>=[\N+] \n/) {
					my $line = $<line>.Str;
					$!buffer.=subst(/\N+\n/, '');
					$!output.more(self.parse_line($line));
				}
			},
			:done({
				if !$!done {
					$!done = True;
					$!output.done();
				}
			}));
		}
		method parse_line(Str $raw) {
			return do given $raw {
				when m/ ^ '1..' $<num>=[\d] [ ' '? '#' $<directive>=['SKIP' | 'TODO'] \s+ $<explanation>=[.*] ]? $ / {
					Plan.new(:$raw, :tests($<num>.Int), | %( $/.kv.map( * => ~* )));
				}
				when m/ ^ $<nok>=['not '?] 'ok' [ ' ' $<num>=[\d+] ]? '-'? [ ' ' $<description>=[.*] ]? $ / {
					Test.new(:$raw, :ok(!$<nok>), :number($<num>.Int), | %( $/.kv.map( * => ~* )));
				}
				when m/ ^ 'Bail out!' ' '? $<explanation>=[.*] / {
					Bailout(:$raw, | %( $/.kv.map( * => ~* )));
				}
				when m/ ^ 'TAP VERSION ' $<version>=[\d+] $/ {
					Version.new(:$raw, :version($<version>.Int));
				}
				default {
					Unknown.new(:$raw);
				}
			}
		}
	}
}

