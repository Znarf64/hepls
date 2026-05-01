# WARNING, STILL IN EARLY DEVELOPMENT

## Language server for the [hephaistos shading language](https://github.com/Znarf64/hephaistos)

## Installation
### Helix
`languages.toml`:
```toml
[[language]]
name             = "hephaistos"
grammar          = "odin"
scope            = "source.hep"
file-types       = [ "hep" ]
comment-token    = "//"
indent           = { tab-width = 4, unit = "\t" }
auto-format      = false
language-servers = [ "hepls" ]

[language-server.hepls]
command = "hepls"
```

## Missing Features
- Completion
- Libraries (other than `exntensions` & `base`)
