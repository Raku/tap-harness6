use v6;
use TAP;

use Test;

plan 6;

my $filename = $*PROGRAM.parent.child('source-file-test-data');
my $source = TAP::Source::File.new(:$filename);
my $parser = TAP::Async.new(:$source);
await $parser.waiter;
my $result = $parser.result;

is($result.tests-planned, 2, "planned 2");
is($result.tests-run, 2, "Ran 2");
is-deeply([@( $result.passed.list )], [ 1 ], "First test passed");
is-deeply([@( $result.failed.list )], [ 2 ], "Second test failed");
is($result.has-problems, True, 'Test failure is a problem');
is($result.errors, [], 'No errors');
