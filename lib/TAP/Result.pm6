use TAP::Entry;
package TAP {
	class Result {
		has Str $.name;
		has Int $.tests-planned;
		has Int $.tests-run;
		has Int $.passed;
		has Int $.failed;
		has Str @.errors;
		has Bool $.skip-all;
		has Proc::Status $.exit-status;
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
