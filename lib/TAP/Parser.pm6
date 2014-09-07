class TAP::Parser {
	role Source {
		method input() {...}
		method done() {...}
		method kill() { }
		method exit-status { Proc::Status }
	}

	class State { ... }
	class Lexer { ... }
	role Session { ... };

	has Str $.name;
	has Source $!source;
	has State $!state;
	has Lexer $!lexer;
	has Promise $.done;
	has Session $!session;

	submethod BUILD(Str :$!name, Source :$!source, :$!session = Session, Promise :$bailout = Promise) {
		my $entries = Supply.new;
		$!state = State.new(:$bailout);
		$entries.tap(-> $entry { $!state.handle-entry($entry) }, :done(-> { $!state.end-input() }));
		$entries.tap(-> $entry { $!session.handle-entry($entry) }) if $!session;
		$!lexer = Lexer.new(:input($!source.input), :output($entries));
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
	class YAML does Entry {
		has Str $.content;
	}
	class Unknown does Entry {
	}

	class Result {
		has Str $.name;
		has Int $.tests-planned;
		has Int $.tests-run;
		has Int $.passed;
		has Int $.failed;
		has Str @.errors;
		has Proc::Status $.exit-status;
	}

	has Result $!result;
	method result {
		return $!done ?? $!result //= $!state.finalize($!name, $!source.exit-status) !! Nil;
	}

	class State {
		has Range $.allowed-versions = 12 .. 13;
		has Int $!tests-planned;
		has Int $!tests-run = 0;
		has Int $!passed = 0;
		has Int $!failed = 0;
		has Str @!errors;

		has Promise $.bailout;
		has Int $!seen-lines = 0;
		enum Seen <Unseen Before After>;
		has Seen $!seen-plan = Unseen;
		has Promise $.done = Promise.new;
		has Int $!version;

		method handle-entry(Entry $entry) {
			given $entry {
				when Version {
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
				when Plan {
					if $!seen-plan {
						self!add-error('Seen a second plan');
					}
					else {
						$!tests-planned = $entry.tests;
						$!seen-plan = $!tests-run ?? After !! Before;
					}
				}
				when Test {
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
				when Bailout {
					if $!bailout.defined {
						$!bailout.keep($entry);
					}
					else {
						$!.done.break($entry);
					}
				}
				when Comment {
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
			return Result.new(:$name, :$!tests-planned, :$!tests-run, :$!passed, :$!failed, :@!errors, :$exit-status);
		}
		method !add-error(Str $error) {
			push @!errors, $error;
		}
	}

	grammar Grammar {
		token TOP { ^ <line>+ $ }
		token ws { <[\s] - [\n]> }
		token line {
			^^ [ <plan> | <test> | <bailout> | <version> | <comment> | <yaml> || <unknown> ] \n
		}
		token plan {
			'1..' $<count>=[\d+] [ '#' <ws>* $<directive>=[:i 'SKIP'] \S+ <ws>+ $<explanation>=[\N*] ]?
		}
		token test {
			$<nok>=['not '?] 'ok' [ <ws> $<num>=[\d] ]? ' -'?
				[ <ws>+ $<description>=[<-[\n\#]>+] ]?
				[ <ws>* '#' <ws>* $<directive>=[:i [ 'SKIP' | 'TODO'] \S* ] <ws>+ $<explanation>=[\N*] ]?
				<ws>*
		}
		token bailout {
			'Bail out!' [ <ws> $<explanation>=[\N*] ]?
		}
		token version {
			:i 'TAP version ' $<version>=[\d+]
		}
		token comment {
			'#' <ws>* $<comment>=[\N+]
		}
		token yaml-line {
			^^ <!yaml-end> \N*
		}
		token yaml-end {
			^^ <ws>+ '...'
		}
		token yaml {
			$<indent>=[<ws>+] '---' \n
			$<content>=[ <yaml-line> \n ]+
			<yaml-end>
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
			make Test.new(:raw($/.Str), :ok(!$<nok>.Str), :number($<num>.defined ?? $<num>.Int !! Int), | %( $/.kv.map( * => ~* )));
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
		method yaml($/) {
			my $indent = $<indent>.Str;
			my $content = $/<content>.Str.subst(/ ^^ <$indent>/, '', :g);
			make YAML.new(:raw($/.Str), :$content);
		}
		method unknown($/) {
			make Unknown.new(:raw($/.Str));
		}
	}

	class Lexer {
		has Supply $!input;
		has Supply $!output;
		has Grammar $!grammar = Grammar.new;
		has Action $!actions = Action.new;
		submethod BUILD(Supply:D :$!input, Supply:D :$!output) {
			my $buffer = '';
			my $done = False;
			$!input.act(-> $data {
				$buffer ~= $data;
				while ($!grammar.subparse($buffer, :actions($!actions))) -> $match {
					$buffer.=substr($match.to);
					for @($match.made) -> $result {
						$!output.more($result);
					}
				}
			},
			:done({
				if !$done {
					$done = True;
					$!output.done();
				}
			}));
		}
	}

	class Aggregator {
		has Result %!results-for;
		has Result @!parse-order;

		has Int $.parsed = 0;
		has Int $.tests-planned = 0;
		has Int $.tests-run = 0;
		has Int $.passed = 0;
		has Int $.failed = 0;
		has Str @.errors;

		method add-result(Result $result) {
			my $description = $result.name;
			die "You already have a parser for ($description). Perhaps you have run the same test twice." if %!results-for{$description};
			%!results-for{$description} = $result;
			@!parse-order.push($result);

			$!parsed++;
			$!tests-planned += $result.tests-planned // 0;
			$!tests-run += $result.tests-run;
			$!passed += $result.passed;
			$!failed += $result.failed;
			@!errors.push(@($result.errors));
		}

		method descriptions {
			return @!parse-order.map(*.name);
		}
	}
}

