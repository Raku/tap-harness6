class TAP::Parser {
	role Source {
		method input() {...}
		method done() {...}
		method kill() { }
	}

	class State { ... }
	class Lexer { ... }

	has Source $!source;
	has State $!state;
	has Lexer $!lexer;
	has Promise $.done;

	submethod BUILD(Source :$!source) {
		$!state = State.new();
		$!lexer = Lexer.new(:input($!source.input), :$!state);
		$!done = Promise.allof($!state.done, $!source.done);
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

	role Entry {
		has Str $.raw = !!! 'Raw input is required';
	}
	class Version does Entry {
		has Int $.version;
	}
	class Plan does Entry {
		has Int $.tests = !!! 'tests is required';
		has Str $.directive;
		has Str $.explanation;
		has Int @.todo_list;
	}
	class Test does Entry {
		has Bool $.ok;
		has Int $.number;
		has Str $.description;
	}
	class Bailout does Entry {
		has Str $.explanation;
	}
	class Comment does Entry {
		has Str $.comment = !!! 'comment is required';
	}
	class Unknown does Entry {
	}

	class State {
		has Int $.tests-planned;
		has Int $!seen-anything = 0;
		has Bool $!seen-plan = False;
		has Int $!tests-run = 0;
		has Int $.passed = 0;
		has Int $.failed = 0;
		has Str @.warnings;
		has Promise $.done = Promise.new;

		method handle_result(Entry $result) {
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
		method finalize() {
			if !$!seen-plan {
				self!add_warning('No plan found in TAP output');
				if $!tests-run != ($!tests-planned || 0) {
					if defined $!tests-planned {
						self!add_warning("Bad plan.  You planned $!tests-planned tests but ran $!tests-run.");
					}
				}
			}
			$!done.keep(True);
		}
		method !add_warning($warning) {
			push @!warnings, $warning;
		}
	}

	grammar Grammar {
		token TOP { ^ <line>+ }
		token ws { <[ \t]> }
		token line {
			^^ [ <plan> | <test> | <bailout> | <version> ] \n
		}
		rule directive {
			 '#' $<directive>=['SKIP' | 'TODO'] $<explanation>=[\N*]
		}
		token plan {
			'1..' $<count>=[\d+] <directive>?
		}
		token test {
			$<nok>=['not '?] 'ok' \s* $<num>=[\d] '-'? [ \s+ $<description>=[\N*] ]? <directive>?
		}
		token bailout {
			'Bail out!' [ ' ' $<explanation>=[\N*] ]?
		}
		token version {
			'TAP VERSION ' $<version>=[\d+]
		}
	}
	class Action {
		my $raw = '';
		method TOP($/) {
			make [ $/<line>.map(*.ast) ];
		}
		method line($/) {
			make $/.values[0].ast;
		}
		method plan($/) {
			make Plan.new(:raw($/.Str), :tests($<count>.Int), | %( $/.kv.map( * => ~* )));
		}
		method test($/) {
			make Test.new(:raw($/.Str), :ok(!$<nok>), :number($<num>.Int), | %( $/.kv.map( * => ~* )));
		}
		method bailout($/) {
			make Bailout.new(:raw($/.Str), | %( $/.kv.map( * => ~* )));
		}
		method version($/) {
			make Version.new(:raw($/.Str), :version($<version>.Int));
		}
	}

	class Lexer {
		has $!input;
		has $!grammar = Grammar.new;
		has $!actions = Action.new;
		submethod BUILD(Supply:D :$!input, State :$state) {
			my $buffer = '';
			my $done = False;
			$!input.act(-> $data {
				$buffer ~= $data;
				while ($!grammar.subparse($buffer, :actions($!actions))) -> $match {
					$buffer.=substr($match.to);
					for @($match.made) -> $result {
						$state.handle_result($result);
					}
				}
			},
			:done({
				if !$done {
					$done = True;
					$state.finalize();
				}
			}));
		}
	}
}

