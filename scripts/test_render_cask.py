"""Tests for render_cask.py. They need no network."""

import unittest

import render_cask as rc

PROGRAM = rc.Program(
    repo="zigdoc",
    binary="zigdoc",
    description="A tool to view docs",
    homepage="https://example.com/zigdoc",
    targets=[
        rc.Target("linux", "intel", "linux-x64"),
        rc.Target("linux", "arm", "linux-arm64"),
        rc.Target("macos", "arm", "macos-arm64"),
    ],
    requires=[],
)
SUMS = {
    "zigdoc-v1.2.3-linux-x64.tar.gz": "a" * 64,
    "zigdoc-v1.2.3-linux-arm64.tar.gz": "b" * 64,
    "zigdoc-v1.2.3-macos-arm64.tar.gz": "c" * 64,
}


class RenderTest(unittest.TestCase):
    def test_a_cask_has_every_platform_with_its_hash(self) -> None:
        cask = rc.render(PROGRAM, "v1.2.3", SUMS)
        self.assertIn('cask "zigdoc" do', cask)
        self.assertIn('version "1.2.3"', cask)
        for char in "abc":
            self.assertIn(f'sha256 "{char * 64}"', cask)
        self.assertIn("on_macos do\n    on_arm do", cask)
        self.assertIn("on_linux do\n    on_arm do", cask)
        self.assertIn('binary "zigdoc-v#{version}-macos-arm64/zigdoc"', cask)

    def test_the_hash_comes_before_the_url_as_homebrew_orders_them(self) -> None:
        cask = rc.render(PROGRAM, "v1.2.3", SUMS)
        self.assertLess(cask.index("sha256"), cask.index("      url"))

    def test_stanzas_follow_homebrews_order(self) -> None:
        cask = rc.render(PROGRAM, "v1.2.3", SUMS)
        order = [
            cask.index(x)
            for x in (
                'version "',
                "on_macos",
                "on_linux",
                "  name ",
                "  desc ",
                "livecheck",
            )
        ]
        self.assertEqual(order, sorted(order))
        self.assertLess(cask.index("on_arm"), cask.index("on_intel"))
        self.assertNotIn("  end\n\n  on_linux", cask)

    def test_the_url_follows_the_version(self) -> None:
        cask = rc.render(PROGRAM, "v1.2.3", SUMS)
        self.assertIn(
            "/releases/download/v#{version}/zigdoc-v#{version}-linux-x64.tar.gz", cask
        )

    def test_no_intel_mac_block_when_no_target_builds_for_it(self) -> None:
        cask = rc.render(PROGRAM, "v1.2.3", SUMS)
        macos = cask.split("on_macos do")[1].split("on_linux do")[0]
        self.assertNotIn("on_intel", macos)

    def test_macos_quarantine_is_cleared_with_install_steps_not_a_ruby_block(
        self,
    ) -> None:
        cask = rc.render(PROGRAM, "v1.2.3", SUMS)
        self.assertIn("postflight_steps do", cask)
        self.assertNotIn("postflight do", cask)
        self.assertIn("com.apple.quarantine", cask)
        self.assertIn("{{staged_path}}", cask)

    def test_a_runtime_requirement_becomes_a_formula_dependency(self) -> None:
        program = rc.Program(
            PROGRAM.repo,
            PROGRAM.binary,
            PROGRAM.description,
            PROGRAM.homepage,
            PROGRAM.targets,
            ["zig"],
        )
        self.assertIn('depends_on formula: "zig"', rc.render(program, "v1.2.3", SUMS))
        self.assertNotIn("depends_on", rc.render(PROGRAM, "v1.2.3", SUMS))

    def test_a_missing_checksum_stops_the_cask(self) -> None:
        sums = dict(SUMS)
        del sums["zigdoc-v1.2.3-linux-arm64.tar.gz"]
        with self.assertRaises(ValueError):
            rc.render(PROGRAM, "v1.2.3", sums)

    def test_the_marker_is_the_first_line(self) -> None:
        self.assertTrue(rc.render(PROGRAM, "v1.2.3", SUMS).startswith(rc.MARKER))


class ParseTest(unittest.TestCase):
    def test_sums_by_file_name(self) -> None:
        text = f"{'a' * 64}  one.tar.gz\n{'b' * 64} *two.tar.gz\nnot a sum\n"
        self.assertEqual(
            rc.parse_sums(text), {"one.tar.gz": "a" * 64, "two.tar.gz": "b" * 64}
        )

    def test_zig_targets_map_to_platforms(self) -> None:
        self.assertEqual(rc.platform_of("x86_64-linux-musl"), ("linux", "intel"))
        self.assertEqual(rc.platform_of("aarch64-linux-gnu"), ("linux", "arm"))
        self.assertEqual(rc.platform_of("aarch64-macos"), ("macos", "arm"))

    def test_an_unknown_target_is_an_error_not_a_skip(self) -> None:
        with self.assertRaises(ValueError):
            rc.platform_of("riscv64-linux-musl")

    def test_the_description_loses_its_period_and_must_fit(self) -> None:
        config = {
            "binary": "x",
            "targets": [{"target": "aarch64-macos", "asset": "macos-arm64"}],
        }
        self.assertEqual(
            rc.program_from("x", config, "Does a thing.", "u").description,
            "Does a thing",
        )
        with self.assertRaises(ValueError):
            rc.program_from("x", config, "x" * 80, "u")
        with self.assertRaises(ValueError):
            rc.program_from("x", config, " . ", "u")


if __name__ == "__main__":
    unittest.main()
