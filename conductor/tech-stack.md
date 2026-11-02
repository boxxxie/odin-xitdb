# Tech Stack: `xitdb-odin`

- **Language:** Odin (`core:os`, `core:io`, `core:encoding/endian`, `core:hash`, `core:bytes`, `core:math`, `core:testing`)
- **Language Server:** `ols` ([`ols.json`](../ols.json))
- **Test Runner:** `odin test tests`
- **Wire Protocol:** `xitdb` v1 (Big-endian 9-byte tagged slots, 16-way HAMT/Radix-Trie/B-Tree/B+Tree, CRC-64/XZ commit trailers)
