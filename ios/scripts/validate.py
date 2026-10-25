"""Host-side structural checks. This does not type-check Swift or replace Xcode tests.

Install optional parsers into an isolated directory:
  python -m pip install --target ios/.validation-tools tree-sitter tree-sitter-swift PyYAML
Run from any directory:
  python ios/scripts/validate.py
"""
import json
import plistlib
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / ".validation-tools"))
failures = []
try:
    import tree_sitter
    import tree_sitter_swift
    import yaml
except ImportError as error:
    raise SystemExit(f"Missing validation dependency: {error}. See script docstring.")

parser = tree_sitter.Parser(tree_sitter.Language(tree_sitter_swift.language()))
swift_files = [p for p in ROOT.rglob("*.swift") if not any(part in {".validation-tools", ".build", "Build"} for part in p.parts)]
for path in swift_files:
    source = path.read_bytes()
    for number, line in enumerate(source.decode("utf-8").splitlines(), start=1):
        if line.rstrip() != line:
            failures.append(f"{path.relative_to(ROOT)}:{number}: trailing whitespace")
    tree = parser.parse(source)
    def visit(node):
        if node.type == "ERROR" or node.is_missing:
            line, column = node.start_point
            snippet = source[node.start_byte:node.end_byte].decode("utf-8", errors="replace")[:140]
            failures.append(f"{path.relative_to(ROOT)}:{line+1}:{column+1}: {node.type}: {snippet}")
        for child in node.children:
            visit(child)
    visit(tree.root_node)

for path in ROOT.rglob("*.json"):
    if any(part in {".validation-tools", ".build", "Build"} for part in path.parts):
        continue
    json.loads(path.read_text(encoding="utf-8"))
for path in ROOT.rglob("*.plist"):
    if ".validation-tools" not in path.parts:
        plistlib.loads(path.read_bytes())
privacy_path = ROOT / "Flamingo/Resources/PrivacyInfo.xcprivacy"
if privacy_path.exists():
    plistlib.loads(privacy_path.read_bytes())

spec = yaml.safe_load((ROOT / "project.yml").read_text(encoding="utf-8"))
info = plistlib.loads((ROOT / "Flamingo/Info.plist").read_bytes())
for key, value in spec["targets"]["Flamingo"]["info"]["properties"].items():
    if info.get(key) != value:
        failures.append(f"Info.plist disagrees with project.yml: {key}")
for target, value in spec["targets"].items():
    for source in value["sources"]:
        relative = source if isinstance(source, str) else source["path"]
        if not (ROOT / relative).exists():
            failures.append(f"Target {target}: missing source {relative}")
for name, package in spec["packages"].items():
    if not (ROOT / package["path"] / "Package.swift").exists():
        failures.append(f"Missing package manifest: {name}")

workflow_path = ROOT.parent / ".github/workflows/ios.yml"
workflow = yaml.safe_load(workflow_path.read_text(encoding="utf-8"))
assert workflow["jobs"]["build"]["runs-on"].startswith("macos")
source_text = "\n".join(p.read_text(encoding="utf-8") for p in swift_files)
for banned in ("import Android", "import Compose", "TODO", "fatalError("):
    if banned in source_text:
        failures.append(f"Unexpected source marker: {banned}")
assert (ROOT / "Flamingo/Resources/LICENSE.txt").read_bytes() == (ROOT.parent / "LICENSE").read_bytes()
icon = ROOT / "Flamingo/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
assert icon.read_bytes()[:8] == b"\x89PNG\r\n\x1a\n"
if failures:
    print("\n".join(failures))
    raise SystemExit(1)
print(f"PASS: {len(swift_files)} Swift files parsed without syntax errors; project, workflow, assets and property lists validated.")
print("NOT VERIFIED: Swift type checking, iOS compilation, runtime audio, signing, visual fidelity and frame rate. Run scripts/build.sh test on macOS.")
