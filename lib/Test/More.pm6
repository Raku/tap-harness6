use TAP::Entry;
use TAP::Generator;

module Test::More {
	my $generator;
	my sub generator() {
		return $*tap-generator // $generator //= TAP::Generator.new(:output(TAP::Output.new));
	}

	multi plan(Int $tests) is export {
		generator.plan($tests);
	}
	multi plan(Bool :$skip-all) is export {
		generator.plan(:skip-all);
	}
	multi done-testing() is export {
		generator.done-testing();
	}
	multi done-testing(Int $count) is export {
		generator.done-testing($count);
	}

	our $TODO is export = Str;

	my sub arguments(Str :$todo, Str :$description) {
		my %ret;
		%ret<description>
	}
	my sub test-args() {
		return $TODO.defined ?? %(:directive(TAP::Todo), :explanation($TODO)) !! ();
	}

	sub ok(Any $value, TAP::Generator::Description $description = TAP::Generator::Description) is export {
		generator.test(:ok(?$value), :$description);
		return ?$value;
	}

	sub is(Mu $got, Mu $expected, TAP::Generator::Description $description = TAP::Generator::Description) is export {
		$got.defined; # Hack to deal with Failures
		my $ok = $got eq $expected;
		generator.test(:$ok, :$description, |test-args());
		if !$ok {
			generator.comment("expected: '$expected'\n     got: '$got'");
		}
		return $ok;
	}
	sub isnt(Mu $got, Mu $expected, TAP::Generator::Description $description = TAP::Generator::Description) is export {
		$got.defined; # Hack to deal with Failures
		my $ok = $got ne $expected;
		generator.test(:$ok, :$description, |test-args());
		if !$ok {
			generator.comment("twice: '$got'");
		}
		return $ok;
	}
	sub like(Mu $got, Mu $expected, TAP::Generator::Description $description = TAP::Generator::Description) is export {
		$got.defined; # Hack to deal with Failures
		my $ok = $got ~~ $expected;
		generator.test(:$ok, :$description, |test-args());
		if !$ok {
			generator.comment("expected: {$expected.perl}\n     got: '$got'");
		}
		return $ok;
	}

	sub cmp-ok(Mu $got, Any $op, Mu $expected, TAP::Generator::Description $description = TAP::Generator::Description) is export {
		$got.defined; # Hack to deal with Failures
		my $ok;
		if $op ~~ Callable ?? $op !! try EVAL "&infix:<$op>" -> $matcher {
			$ok = $matcher($got,$expected);
			generator.test(:$ok, :$description, |test-args());
			if !$ok {
				generator.comment("expected: '{$expected // $expected.^name}'");
				generator.comment(" matcher: '$matcher'");
				generator.comment("     got: '$got'");
			}
			return $ok;
		}
		else {
			generator.test(:$ok, $description.defined ?? :$description !! ());
			generator.comment("Could not use '$op' as a comparator");
			return False;
		}
	}

	sub pass(TAP::Generator::Description $description = TAP::Generator::Description) is export {
		generator.test(:ok, :$description, |test-args());
		return True;
	}
	sub flunk(TAP::Generator::Description $description = TAP::Generator::Description) is export {
		generator.test(:!ok, :$description, |test-args());
		return False;
	}

	sub skip(TAP::Generator::Explanation $explanation= TAP::Generator::Explanation, Int $count = 1) is export {
		for 1 .. $count {
			generator.test(:ok, :directive(TAP::Skip), :$explanation);
		}
	}

	multi subtest(&subtests) is export {
		generator.start-subtest();
		subtests();
		LEAVE {
			generator.stop-subtest();
		}
	}
	multi subtest(TAP::Generator::Description $description, &subtests) is export {
		generator.start-subtest($description);
		subtests();
		LEAVE {
			generator.stop-subtest();
		}
	}

	sub diag(Str $comment) is export {
		generator.comment($comment);
		return True;
	}

	sub test-to(TAP::Entry::Handler $output, &tests, Bool :$keep-alive, Int :$version = 12) is export {
		my $*tap-generator = TAP::Generator.new(:$output, :$version);
		tests();
		my $ret = 0;
		LEAVE {
			$ret = generator.stop-tests() if not $keep-alive;
		}
		return $ret;
	}

	END {
		generator.stop-tests();
	}
}
