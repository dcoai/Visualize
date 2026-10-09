# Geographic data for the gallery

## `ne_110m_land.geojson`

Natural Earth's 1:110m physical land (`ne_110m_land`): coastlines and islands, no
borders. The gallery's World Map and Globe draw it through
`Examples.Charts.WorldGeography.land/0`, which reads and decodes it when that module
compiles (#499). It is never fetched at build or test time.

| | |
|---|---|
| Source | Natural Earth's own vector repository, `nvkelso/natural-earth-vector`, release tag `v5.1.2` |
| URL | <https://raw.githubusercontent.com/nvkelso/natural-earth-vector/v5.1.2/geojson/ne_110m_land.geojson> |
| Version | Natural Earth 5.1.2 (released 2022-05-13); the file is byte-identical on `master` (checked 2026-10-09) |
| Fetched | 2026-10-09 |
| SHA-256 | `9e0729ee253ca7d7a5c4ae9395fb1902264c5377c52e224d13dd85010e2835d9` |
| Size | 138,160 bytes; 127 `Polygon` features, 5,143 positions |
| Licence | Public domain. Natural Earth asks for a credit line, which the two maps give. |

The file is stored exactly as published, so its checksum can be compared with the
source. Each feature's properties are Natural Earth's (`featurecla`, `scalerank`,
`min_zoom`), and none of them is a name. `land/0` therefore names each row
`"land-<n>"` by its 1-based position in the file.

To fetch it again, from this directory:

    curl -sSLO https://raw.githubusercontent.com/nvkelso/natural-earth-vector/v5.1.2/geojson/ne_110m_land.geojson
    sha256sum ne_110m_land.geojson
