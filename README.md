# json 🐑

> [!WARNING]
> **Deprecated:** This forked `gleam_json` repository is deprecated in favor of unmodified upstream Hex [`gleam_json`](https://hex.pm/packages/gleam_json) paired with the companion shim [`gekko_json`](https://github.com/spiral-nights/gekko_json) (and `gleam_stdlib` + [`gekko_stdlib`](https://github.com/spiral-nights/gekko_stdlib)).
>
> **Migrate your `gleam.toml`:**
>
> ```toml
> [dependencies]
> gleam_stdlib = ">= 1.0.0 and < 2.0.0"
> gleam_json = ">= 3.0.0 and < 4.0.0"
> gekko_stdlib = { git = "https://github.com/spiral-nights/gekko_stdlib.git", ref = "main" }
> gekko_json = { git = "https://github.com/spiral-nights/gekko_json.git", ref = "main" }
> ```
>
> This repository remains available read-only so existing pinned commits continue to resolve, and will no longer receive updates.

Work with JSON in Gleam!

## Installation

```shell
gleam add gleam_json@3
```

## Encoding

```gleam
import myapp.{type Cat}
import gleam/json

pub fn cat_to_json(cat: Cat) -> String {
  json.object([
    #("name", json.string(cat.name)),
    #("lives", json.int(cat.lives)),
    #("flaws", json.null()),
    #("nicknames", json.array(cat.nicknames, of: json.string)),
  ])
  |> json.to_string
}
```

## Parsing

JSON is parsed into a `Dynamic` value which can be decoded using the
`gleam/dynamic/decode` module from the Gleam standard library.

```gleam
import myapp.{type Cat, Cat}
import gleam/json
import gleam/dynamic/decode

pub fn cat_from_json(json_string: String) -> Result(Cat, json.DecodeError) {
  let cat_decoder = {
    use name <- decode.field("name", decode.string)
    use lives <- decode.field("lives", decode.int)
    use nicknames <- decode.field("nicknames", decode.list(decode.string))
    decode.success(Cat(name:, lives:, nicknames:))
  }
  json.parse(from: json_string, using: cat_decoder)
}
```
