"""Self-test for the copy style scanners. Run by ci-checks.py."""
import importlib.util
import unittest
from pathlib import Path

spec = importlib.util.spec_from_file_location("copy_style", Path(__file__).resolve().parent / "copy_style.py")
copy_style = importlib.util.module_from_spec(spec)
spec.loader.exec_module(copy_style)


def names(src):
    return [name for _, name in copy_style.empty_state_violations(src)]


class EmptyStateTests(unittest.TestCase):
    def test_nested_call_then_detail_fails(self):
        self.assertEqual(names("EmptyState(kind: makeKind(foo(bar)), detail: 'x')"), ["detail"])

    def test_comment_mentioning_detail_passes(self):
        src = "EmptyState(\n  kind: k,\n  // detail: not shown\n  /* body: nope */\n)"
        self.assertEqual(names(src), [])

    def test_clean_multiline_call_passes(self):
        src = "EmptyState(\n  kind: EmptyKind.dining,\n  title: 'Nothing here',\n  action: () => go(1, 2),\n)"
        self.assertEqual(names(src), [])

    def test_inner_call_of_other_widget_passes(self):
        src = "EmptyState(kind: k, action: Button(detail: 'x', message: m, body: b))"
        self.assertEqual(names(src), [])

    def test_banned_name_in_string_passes(self):
        self.assertEqual(names("EmptyState(title: 'detail: x, body: y')"), [])

    def test_interpolation_with_quotes_passes(self):
        self.assertEqual(names("""EmptyState(title: '${a['body: z']}', kind: k)"""), [])

    def test_banned_arg_inside_interpolation_fails(self):
        self.assertEqual(names("final s = '${EmptyState(body: 'x')}';"), ["body"])

    def test_clean_call_inside_interpolation_passes(self):
        self.assertEqual(names("final s = '${EmptyState(title: 't')}';"), [])

    def test_literal_text_naming_the_call_passes(self):
        self.assertEqual(names("final s = 'EmptyState(body: x)';"), [])

    def test_literal_text_beside_interpolation_passes(self):
        self.assertEqual(names("final s = 'EmptyState(body: x) ${a}';"), [])

    def test_nested_string_inside_interpolation_is_blanked(self):
        self.assertEqual(names("""final s = '${f("EmptyState(body: x)")}';"""), [])

    def test_call_inside_nested_interpolation_fails(self):
        self.assertEqual(names("""final s = '${f("${EmptyState(detail: 1)}")}';"""), ["detail"])

    def test_each_banned_name_fails(self):
        for name in ("body", "message", "detail"):
            self.assertEqual(names("EmptyState(%s: 'x')" % name), [name])

    def test_ternary_colon_is_not_a_named_arg(self):
        self.assertEqual(names("EmptyState(kind: c ? body : other)"), [])

    def test_reports_line_of_call(self):
        self.assertEqual(copy_style.empty_state_violations("a\nb\nEmptyState(\n  detail: 'x',\n)"), [(3, "detail")])

    def test_class_declaration_is_skipped(self):
        self.assertEqual(names("class EmptyState(detail: 1)"), [])

    def test_map_braces_in_interpolation_then_literal_passes(self):
        self.assertEqual(names("""final s = '${ {'a': 1}['a'] } EmptyState(body: x)';"""), [])

    def test_map_braces_in_interpolation_call_inside_fails(self):
        self.assertEqual(names("""final s = '${ {'a': EmptyState(body: x)}['a'] }';"""), ["body"])

    def test_set_braces_in_interpolation_then_literal_passes(self):
        self.assertEqual(names("final s = '${ {1,2}.length } EmptyState(body: x)';"), [])

    def test_set_braces_in_interpolation_call_inside_fails(self):
        self.assertEqual(names("final s = '${ {1,2}.length + EmptyState(message: x) }';"), ["message"])

    def test_short_interpolation_then_literal_passes(self):
        self.assertEqual(names("final s = '$name EmptyState(body: x)';"), [])

    def test_short_interpolation_beside_call_fails(self):
        self.assertEqual(names("final s = '$name'; EmptyState(body: x);"), ["body"])

    def test_escaped_dollar_is_literal_text(self):
        self.assertEqual(names("final s = '\\${EmptyState(body: x)}';"), [])

    def test_escaped_dollar_then_real_interpolation_fails(self):
        self.assertEqual(names("final s = '\\$ ${EmptyState(detail: x)}';"), ["detail"])

    def test_raw_string_is_literal_text(self):
        self.assertEqual(names("final s = r'${EmptyState(body: x)}';"), [])

    def test_raw_triple_string_is_literal_text(self):
        self.assertEqual(names("final s = r'''\n${EmptyState(body: x)}\n''';"), [])

    def test_identifier_ending_in_r_is_not_raw(self):
        self.assertEqual(names("final s = bar'${EmptyState(body: x)}';"), ["body"])

    def test_multiline_string_interpolation_fails(self):
        self.assertEqual(names("final s = '''\nline\n${EmptyState(\n  body: x,\n)}\n''';"), ["body"])

    def test_multiline_string_literal_text_passes(self):
        self.assertEqual(names("final s = '''\nEmptyState(body: x)\n${a}\nEmptyState(message: y)\n''';"), [])

    def test_multiline_string_reports_line_of_call(self):
        src = "final s = '''\nline\n${EmptyState(\n  body: x,\n)}\n''';"
        self.assertEqual(copy_style.empty_state_violations(src), [(3, "body")])


class EmDashTests(unittest.TestCase):
    def test_code_and_string_fail(self):
        self.assertEqual(copy_style.em_dash_lines("a\nb = 'x — y';\n"), [2])

    def test_line_doc_and_block_comments_pass(self):
        src = "// a — b\n/// c — d\n/* e —\n f — */\nx = 1;\n"
        self.assertEqual(copy_style.em_dash_lines(src), [])

    def test_trailing_comment_passes(self):
        self.assertEqual(copy_style.em_dash_lines("x = 1; // a — b\n"), [])

    def test_slashes_inside_string_are_not_a_comment(self):
        self.assertEqual(copy_style.em_dash_lines("u = 'http://x'; v = '—';\n"), [1])

    def test_dash_after_interpolation_fails(self):
        self.assertEqual(copy_style.em_dash_lines("s = '${a} —';\n"), [1])

    def test_dash_after_map_braces_in_interpolation_fails(self):
        self.assertEqual(copy_style.em_dash_lines("s = '${ {'a': 1}['a'] } —';\n"), [1])

    def test_dash_after_set_braces_in_interpolation_fails(self):
        self.assertEqual(copy_style.em_dash_lines("s = '${ {1,2}.length } —';\n"), [1])

    def test_dash_in_string_literal_inside_interpolation_fails(self):
        self.assertEqual(copy_style.em_dash_lines("s = '${f('—')}';\n"), [1])

    def test_dash_in_map_literal_inside_interpolation_fails(self):
        self.assertEqual(copy_style.em_dash_lines("s = '${ {'a': '—'}['a'] }';\n"), [1])

    def test_dash_in_comment_inside_interpolation_passes(self):
        self.assertEqual(copy_style.em_dash_lines("s = '''${a // x — y\n}''';\n"), [])

    def test_dash_in_block_comment_inside_interpolation_passes(self):
        self.assertEqual(copy_style.em_dash_lines("s = '${a /* x — y */}';\n"), [])

    def test_dash_after_short_interpolation_fails(self):
        self.assertEqual(copy_style.em_dash_lines("s = '$name —';\n"), [1])

    def test_dash_after_escaped_dollar_fails(self):
        self.assertEqual(copy_style.em_dash_lines("s = '\\${a} —';\n"), [1])

    def test_dash_in_raw_string_fails(self):
        self.assertEqual(copy_style.em_dash_lines("s = r'${a} —';\n"), [1])

    def test_dash_in_multiline_string_reports_its_line(self):
        self.assertEqual(copy_style.em_dash_lines("s = '''\nline\n${a} —\n''';\n"), [3])

    def test_dash_in_comment_after_multiline_string_passes(self):
        self.assertEqual(copy_style.em_dash_lines("s = '''\n${a}\n'''; // —\n"), [])

    def test_comment_marker_in_interpolated_string_is_not_a_comment(self):
        self.assertEqual(copy_style.em_dash_lines("s = '${a}//'; t = '—';\n"), [1])


if __name__ == "__main__":
    unittest.main()
