#!/usr/bin/env bash
# Transpile and execute gleam_json's test suite through gekko across MoonBit
# targets (wasm, wasm-gc, js, native).
#
# Environment overrides:
#   GEKKO            - gekko CLI command or binary path (default: gekko)
#   TARGETS          - space-separated MoonBit targets (default: "wasm wasm-gc js native")
#   GEKKO_STDLIB_DIR - local path to gekko_gleam_stdlib (default: clone over HTTPS)
#   GEKKO_STDLIB_REF - git ref when fetching gekko_gleam_stdlib (default: main)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GEKKO="${GEKKO:-gekko}"
TARGETS="${TARGETS:-wasm wasm-gc js native}"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

# Why stage a temporary test project instead of running `gekko test` directly in $ROOT:
# 1. Upstream `gleam.toml` declares `gleam_stdlib = ">= 0.51.0 and < 2.0.0"`, which
#    resolves to upstream Hex `gleam_stdlib` (without MoonBit FFI). Here we wire
#    `gleam_stdlib` to `gekko_gleam_stdlib` (via local path or git fork).
# 2. `test/gleam_json_test.gleam` imports `gleeunit/should`, while `gekko` skips the
#    `gleeunit` Hex package, so we provide a minimal `src/gleeunit/should.gleam` shim.
PROJECT_DIR="$TMP_DIR/json_parity"
OUT_DIR="$TMP_DIR/json_parity_mbt"
mkdir -p "$PROJECT_DIR/src/gleeunit" "$PROJECT_DIR/test"

if [ -n "${GEKKO_STDLIB_DIR:-}" ]; then
  STDLIB_ABS="$(cd "$GEKKO_STDLIB_DIR" && pwd)"
  STDLIB_DEP="gleam_stdlib = { path = \"$STDLIB_ABS\" }"
else
  STDLIB_DEP="gleam_stdlib = { git = \"https://github.com/spiral-nights/gekko_gleam_stdlib.git\", ref = \"${GEKKO_STDLIB_REF:-main}\" }"
fi

cat > "$PROJECT_DIR/gleam.toml" <<EOF
name = "json_parity"
version = "0.1.0"

[dependencies]
$STDLIB_DEP
gleam_json = { path = "$ROOT" }
EOF

cat > "$PROJECT_DIR/src/gleeunit/should.gleam" <<'EOF'
pub fn equal(a: t, b: t) -> Nil {
  assert a == b
  Nil
}
EOF

cat > "$PROJECT_DIR/src/json_parity.gleam" <<'EOF'
pub fn main() -> Nil {
  Nil
}
EOF

# Keep all 25 upstream tests in `test/gleam_json_test.gleam`, only replacing
# `gleeunit.main()` (since MoonBit runs each `*_test` function directly via `moon test`).
awk '
  BEGIN { found_imp = 0; found_main = 0 }
  $0 == "import gleeunit" {
    found_imp = 1
    next
  }
  $0 == "  gleeunit.main()" {
    found_main = 1
    print "  Nil"
    next
  }
  { print }
  END {
    if (!found_imp || !found_main) {
      print "FAIL: expected gleeunit markers not found in gleam_json_test.gleam" > "/dev/stderr"
      exit 1
    }
  }
' "$ROOT/test/gleam_json_test.gleam" > "$PROJECT_DIR/test/json_parity_test.gleam"

# Extra end-to-end check covering nested decoders (`decode.field`, `decode.optional`,
# `decode.dict`, `decode.at`) and parse error formatting alongside the 25 upstream tests.
cat > "$PROJECT_DIR/test/json_roundtrip_extra_test.gleam" <<'EOF'
import gleam/dict
import gleam/dynamic
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option.{None}

pub fn nested_json_roundtrip_and_decode_errors_test() {
  let j =
    json.object([
      #("name", json.string("gleam")),
      #("nums", json.array([1, 2, 3], of: json.int)),
      #("ratio", json.float(1.5)),
      #("ok", json.bool(True)),
      #("opt", json.nullable(None, of: json.int)),
    ])
  let j_str = json.to_string(j)
  let rec_decoder = {
    use name <- decode.field("name", decode.string)
    use nums <- decode.field("nums", decode.list(decode.int))
    use ratio <- decode.field("ratio", decode.float)
    use ok <- decode.field("ok", decode.bool)
    use opt <- decode.field("opt", decode.optional(decode.int))
    decode.success(#(name, nums, ratio, ok, opt))
  }
  assert json.parse(j_str, rec_decoder) == Ok(#("gleam", [1, 2, 3], 1.5, True, None))

  let dict_dyn =
    [#("a", 10), #("b", 20)]
    |> list.map(fn(p) { #(dynamic.string(p.0), dynamic.int(p.1)) })
    |> dynamic.properties
  assert dynamic.classify(dict_dyn) == "Dict"
  assert decode.run(dict_dyn, decode.dict(decode.string, decode.int))
    == Ok(dict.from_list([#("a", 10), #("b", 20)]))

  assert json.parse("[", decode.list(decode.int))
    == Error(json.UnexpectedEndOfInput)
  let assert Error(json.UnexpectedByte("0x69")) =
    json.parse("{invalid}", decode.dynamic)
  assert decode.run(dynamic.int(5), decode.at([0], decode.int)) != Ok(5)
}
EOF

echo "=== Downloading dependencies and transpiling json_parity ==="
(cd "$PROJECT_DIR" && gleam deps download)
"$GEKKO" check --root "$PROJECT_DIR" --out "$OUT_DIR" --target wasm

# Verify zero warnings (`moon check --deny-warn`) and run all 26 tests per target.
for target in $TARGETS; do
  echo "=== Running json_parity tests on $target ==="
  (cd "$OUT_DIR" && moon check --deny-warn --target "$target")
  out="$(cd "$OUT_DIR" && moon test --target "$target")"
  echo "$out"
  case "$out" in
    *"passed: 26, failed: 0"*) ;;
    *)
      echo "FAIL [json_parity/$target]: expected 'passed: 26, failed: 0'" >&2
      exit 1
      ;;
  esac
done

echo "gleam_json MoonBit tests passed on all targets ($TARGETS)."
