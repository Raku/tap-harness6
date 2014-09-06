class TAP::Parser {
	role Source {
		method input() {...}
		method done() {...}
		method kill() { }
		method exit-status { Proc::Status }
	}

	class State { ... }
	class Lexer { ... }

	has Str $.name;
	has Source $!source;
	has State $!state;
	has Lexer $!lexer;
	has Promise $.done;

	submethod BUILD(Str :$!name, Source :$!source, Promise :$bailout = Promise) {
		$!state = State.new(:$bailout);
		$!lexer = Lexer.new(:input($!source.input), :$!state);
		$!done = Promise.allof($!state.done, $!source.done);
	}

	method kill() {
		$!source.kill();
		$!done.break("killed") if not $!done;
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
		method exit-status {
			return $!done ?? $!done.result !! nextsame;
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
	}
	class Test does Entry {
		has Bool $.ok;
		has Int $.number;
		has Str $.description;
		has Str $.directive;
		has Str $.explanation;

		method is-ok() {
			return $!ok || $.is-todo;
		}
		method is-todo() {
			return $!directive.defined && $!directive ~~ m:i/ ^ 'TODO' /;
		}
		method is-skipped() {
			return $!directive.defined && $!directive ~~ m:i/ ^ 'SKIP' /;
		}
	}
	class Bailout does Entry {
		has Str $.explanation;
	}
	class Comment does Entry {
		has Str $.comment = !!! 'comment is required';
	}
	class Unknown does Entry {
	}

	class Result {
		has Int $.tests-planned;
		has Int $.tests-run;
		has Int $.passed;
		has Int $.failed;
		has Str @.errors;
		has Proc::Status $.exit-status;
	}

	has Result $!result;
	method result {
		return $!done ?? $!result //= $!state.finalize($!source.exit-status) !! Nil;
	}

	class State {
		has Int $tests-planned;
		has Int $tests-run = 0;
		has Int $passed = 0;
		has Int $failed = 0;
		has Str @!errors;

		has Promise $.bailout;
		has Int $!seen-anything = 0;
		has Bool $!seen-plan = False;
		has Promise $.done = Promise.new;

		method handle_result(Entry $result) {
			given $result {
				when Plan {
					if $!seen-plan {
						self!add-error('Seen a second plan');
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
						self!add-error("Tests out of sequence.  Found ($found-number) but expected ($expected-number)");
					}
					($result.is-ok ?? $!passed !! $!failed)++;
				}
				when Bailout {
					if $!bailout.defined {
						$!bailout.keep($result);
					}
					else {
						$!.done.break($result);
					}
				}
				default {
					...;
				}
			}
			$!seen-anything++;
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
		method finalize(Proc::Status $exit-status) {
			return Result.new(:$tests-planned, :$tests-run, :$passed, :$failed, :@errors, :$exit-status);
		}
		method !add-error(Str $error) {
			push @!errors, $error;
		}
	}

	grammar Grammar {
		token TOP { ^ <line>+ $ }
		token ws { <[\s] - [\n]> }
		token line {
			^^ [ <plan> | <test> | <bailout> | <version> | <comment> || <unknown> ] \n
		}
		token plan {
			'1..' $<count>=[\d+] [ '#' <ws>* $<directive>=[:i 'SKIP'] \S+ <ws>+ $<explanation>=[\N*] ]?
		}
		token test {
			$<nok>=['not '?] 'ok' [ <ws> $<num>=[\d] ] ' -'?
				[ <ws>+ $<description>=[<-[\n\#]>+] ]?
				[ <ws>* '#' <ws>* $<directive>=[:i [ 'SKIP' | 'TODO'] \S* ] <ws>+ $<explanation>=[\N*] ]?
				<ws>*
		}
		token bailout {
			'Bail out!' [ <ws> $<explanation>=[\N*] ]?
		}
		token version {
			'TAP VERSION ' $<version>=[\d+]
		}
		token comment {
			'#' <ws>* $<comment>=[\N+]
		}
		token unknown {
			\N+
		}
	}
	class Action {
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
			make Test.new(:raw($/.Str), :ok(!$<nok>.Str), :number($<num>.Int), | %( $/.kv.map( * => ~* )));
		}
		method bailout($/) {
			make Bailout.new(:raw($/.Str), | %( $/.kv.map( * => ~* )));
		}
		method version($/) {
			make Version.new(:raw($/.Str), :version($<version>.Int));
		}
		method comment($/) {
			make Comment.new(:raw($/.Str), :comment($<comment>.Str));
		}
		method unknown($/) {
			make Unknown.new(:raw($/.Str));
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
					$state.end-input();
				}
			}));
		}
	}
}

