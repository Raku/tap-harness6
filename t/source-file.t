use v6;
use TAP::Parser;

use Test::More;

plan 4;

my $source = TAP::Parser::Async::Source::File.new(:filename('t/source-file-test-data'));
my $parser = $source.make-parser;
await $parser;
my $result = $parser.result;

is $result.tests-planned, 2;
is $result.tests-run, 2;
is-deeply $result.passed, [ 1 ];
is-deeply $result.failed, [ 2 ];
