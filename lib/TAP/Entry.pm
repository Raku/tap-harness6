package TAP {
	role Entry {
		has Str $.raw = !!! 'Raw input is required';
	}
	class Version does Entry {
		has Int $.version;
	}
	class Plan does Entry {
		has Int:D $.tests = !!! 'tests is required';
		has Str $.directive;
		has Str $.explanation;
	}
	class Test does Entry {
		has Bool:D $.ok;
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
}
