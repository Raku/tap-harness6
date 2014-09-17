use TAP::Parser;
use Test::More;

my $content1 = q:heredoc/END/;
    ok 1 - subtest 1a
    ok 2 - subtest 1b
    1..2
ok 1 - Subtest 1
    ok 1 - subtest 2a
    ok 2 - subtest 2b
    1..2
ok 2 - Subtest 2
1..2
END
parse-and-get($content1, :tests-planned(2), :tests-run(2), :passed(2), :failed(0), :todo-passed(0), :skipped(0), :unknowns(0), :errors());

my $content2 = q:heredoc/END/;
ok 1 - foo
    not ok 1 - not ok
ok 2 - bar passed
1..2
END
parse-and-get($content2, :tests-planned(2), :tests-run(2), :passed(2), :failed(0), :todo-passed(0), :skipped(0), :unknowns(0), :errors(['Subtest 2 isn\'t coherent']));

my $content3 = q:heredoc/END/;
ok 1 - foo
        ok 1 - bar indented too far
ok 2 - bar passed
1..2
END

parse-and-get($content3, :tests-planned(2), :tests-run(2), :passed(2), :failed(0), :todo-passed(0), :skipped(0), :unknowns(1), :errors());

done-testing();

my $i = 1;
sub parse-and-get($content, :$tests-planned, :$tests-run, :$passed, :$failed, :$todo-passed, :$skipped, :$unknowns, :@errors = Array, :$name = "Test-{ $i++ }") {
	my $source = TAP::Parser::Async::Source::String.new(:$name, :$content);
	my $parser = $source.make-parser();

	my $result = $parser.result;
	is($result.tests-planned, $tests-planned, "Expected $tests-planned planned tests in $name") if $tests-planned.defined;
	is($result.tests-run, $tests-run, "Expected $tests-run run tests in $name") if $tests-run.defined;
	is($result.passed.elems, $passed, "Expected $passed passed tests in $name") if $passed.defined;
	is($result.failed.elems, $failed, "Expected $failed failed tests in $name") if $failed.defined;
	is($result.todo-passed.elems, $todo-passed, "Expected $todo-passed todo-passed tests in $name") if $todo-passed.defined;
	is($result.skipped.elems, $skipped, "Expected $skipped skipped tests in $name") if $skipped.defined;
	is($result.unknowns, $unknowns, "Expected $unknowns unknown tests in $name") if $unknowns.defined;
	is-deeply($result.errors, Array[Str].new(@errors), 'Got expected errors: ' ~ @errors.map({qq{"$_"}}).join(', ')) if @errors.defined;

	diag("Finished $name");
	return $result;
}
