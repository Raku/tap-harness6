use TAP::Parser;
use TAP::Entry;

use Test::More;

my $source = TAP::Parser::Async::Source::Through.new(:name("Self-Testing"));
my $parser = $source.make-parser();
my $elements = TAP::Collector.new();
my $output = TAP::Entry::Handler::Multi.new(:handlers($source, $elements));

my $tester = start {
	test-to $output, {
		plan(3);
		ok(True, "This tests passes");

		subtest 'Subtest', {
			pass();
			plan(1);
		};

		skip();
	}
}

is($tester.result, 0, 'Test would have returned 0');

my $result = $parser.result;
is($result.tests-planned, 3, 'Expected 3 tests');
is($result.tests-run, 3, 'Ran 3 tests');
is($result.passed.elems, 3, 'Passed 3 tests');
is($result.failed.elems, 0, 'Failed 0 tests');
is($result.todo-passed.elems, 0, 'Todo-passed 0 tests');
is($result.skipped.elems, 1, 'Skipped 1 test');

my @expected =
	TAP::Plan,
	TAP::Test,
	TAP::Sub-Test,
	TAP::Test,
;

for @($elements.entries) Z @expected -> $got, $expected {
	like($got, $expected, "Expected a " ~ $expected.WHAT.perl);
}

done-testing();
