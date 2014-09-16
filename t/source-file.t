use v6;
use TAP::Parser;

use Test::More;

# not really deep, but good enough
sub is_deeply($got, $expected) {
	unless $got.elems == $expected.elems {
		is $got.elems, $expected.elems;
		return False;
	}
	for (0 .. $got.end) -> $i {
	    unless $got[$i] eqv $expected[$i] {
		diag("got:      $got[$i].gist()");
		diag("expected: $expected[$i].gist()");
		return False;
	    }
	}
	pass;
	return True;
}

plan 4;

my $source = TAP::Parser::Async::Source::File.new(:filename('t/source-file-test-data'));
my $parser = $source.make-parser;
await $parser;
my $result = $parser.result;

is $result.tests-planned, 2;
is $result.tests-run, 2;
is_deeply $result.passed, [ 1 ];
is_deeply $result.failed, [ 2 ];
