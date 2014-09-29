use TAP::Entry;
use TAP::Result;

package TAP {
	grammar Grammar {
		method parse {
			my $*tap-indent = 0;
			callsame;
		}
		method subparse($, *%) {
			my $*tap-indent = 0;
			callsame;
		}
		token TOP { ^ <line>+ $ }
		token sp { <[\s] - [\n]> }
		token num { <[0..9]>+ }
		token line {
			^^ [ <plan> | <test> | <bailout> | <version> | <comment> | <yaml> | <sub-test> || <unknown> ] \n
		}
		token plan {
			'1..' <count=.num> [ '#' <.sp>* $<directive>=[:i 'SKIP'] <.alnum>+ <.sp>+ $<explanation>=[\N*] ]?
		}
		regex description {
			[ <-[\n\#\\]> | \\<[\\#]> ]+ <!after <sp>+>
		}
		token test {
			$<nok>=['not '?] 'ok' [ <.sp> <num> ]? ' -'?
				[ <.sp>+ <description> ]?
				[ <.sp>* '#' <.sp>* $<directive>=[:i [ 'SKIP' | 'TODO'] <.alnum>* ] <.sp>+ $<explanation>=[\N*] ]?
				<.sp>*
		}
		token bailout {
			'Bail out!' [ <.sp> $<explanation>=[\N*] ]?
		}
		token version {
			:i 'TAP version ' <version=.num>
		}
		token comment {
			'#' <.sp>* $<comment>=[\N*]
		}
		token yaml {
			$<yaml-indent>=['  '] '---' \n :
			[ ^^ <.indent> $<yaml-indent> $<yaml-line>=[<!before '...'> \N* \n] ]*
			<.indent> $<yaml-indent> '...'
		}
		token sub-entry {
			<plan> | <test> | <comment> | <yaml> | <sub-test> || <!before <sp>+ > <unknown>
		}
		token indent {
			'    ' ** { $*tap-indent }
		}
		token sub-test {
			'    ' :temp $*tap-indent += 1; <sub-entry> \n
			[ <.indent> <sub-entry> \n ]*
			'    ' ** { $*tap-indent - 1 } <test>
		}
		token unknown {
			\N*
		}
	}
	class Action {
		method TOP($/) {
			make @<line>».ast;
		}
		method line($/) {
			make $/.values[0].ast;
		}
		method plan($/) {
			my %args = :raw($/.Str), :tests($<count>.Int);
			if $<directive> {
				%args<skip-all explanation> = True, $<explanation>;
			}
			make TAP::Plan.new(|%args);
		}
		method !make_test($/) {
			my %args = (:ok(!$<nok>.Str));
			%args<number> = $<num>.defined ?? $<num>.Int !! Int;
			%args<directive> = $<directive> ?? TAP::Directive::{$<directive>.Str.substr(0,4).tclc} !! TAP::No-Directive;
			%args<explanation> = ~$<explanation> if $<explanation>;
			if $<description> {
				%args<description> = $<description>.Str.subst(/\\('#'|'\\')/, $0, :g);
			}
			return %args;
		}
		method test($/) {
			make TAP::Test.new(:raw($/.Str), |self!make_test($/));
		}
		method bailout($/) {
			make TAP::Bailout.new(:raw($/.Str), :explanation($<explanation> ?? ~$<explanation> !! Str));
		}
		method version($/) {
			make TAP::Version.new(:raw($/.Str), :version($<version>.Int));
		}
		method comment($/) {
			make TAP::Comment.new(:raw($/.Str), :comment($<comment>.Str));
		}
		method yaml($/) {
			my $content = $<yaml-line>.join('');
			make TAP::YAML.new(:raw($/.Str), :$content);
		}
		method sub-entry($/) {
			make $/.values[0].ast;
		}
		method sub-test($/) {
			make TAP::Sub-Test.new(:raw($/.Str), :entries(@<sub-entry>».ast), |self!make_test($<test>));
		}
		method unknown($/) {
			make TAP::Unknown.new(:raw($/.Str));
		}
	}

	class Lexer {
		has Str $!buffer = '';
		our subset Output of Any:D where *.can('more');
		has Output $!output;
		has Grammar $!grammar = Grammar.new;
		has Action $!actions = Action.new;
		submethod BUILD(Supply:D :$!output) { }
		method add-data(Str $data) {
			$!buffer ~= $data;
			while ($!grammar.subparse($!buffer, :actions($!actions))) -> $match {
				$!buffer.=substr($match.to);
				for @($match.made) -> $result {
					$!output.more($result);
				}
			}
		}
		method close-data() {
			if $!buffer.chars {
				warn "Unparsed data left at end of stream: $!buffer";
			}
			$!output.done();
		}
	}
}
