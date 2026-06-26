name = "kawaz/grapheme"

version = "0.10.3"

readme = "README.md"

repository = "https://github.com/kawaz/grapheme.mbt"

license = "MIT"

keywords = [
  "unicode",
  "grapheme",
  "segmentation",
  "text",
  "uax29",
  "cluster",
  "emoji",
]

description = "Unicode grapheme cluster segmentation library for MoonBit (UAX #29)"

options(
  source: "src",
  exclude: [
    "docs",
    "tools",
    ".unicode-version",
    "justfile",
    "CHANGELOG.md",
    "**/*_test.mbt",
    "**/*_wbtest.mbt",
    "**/*_wbbench.mbt",
  ],
)
