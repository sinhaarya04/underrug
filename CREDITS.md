# Rug photographs

Every rug design is a photograph from **The Metropolitan Museum of Art, New York**, released through its
[Open Access](https://www.metmuseum.org/about-the-met/policies-and-documents/open-access) program into the
public domain (CC0). They were cropped to the woven field, turned landscape and resized; nothing else changed.

| Design | Object | Origin | Met |
|---|---|---|---|
| Anatolian Red | Carpet | Turkey, 18th century | [452567](https://www.metmuseum.org/art/collection/search/452567) |
| Persian Medallion | Carpet | Iran, second half 16th century | [446954](https://www.metmuseum.org/art/collection/search/446954) |
| Cairo Medallion | Carpet | Egypt, ca. 1550 | [452309](https://www.metmuseum.org/art/collection/search/452309) |
| Chinese Gold | Carpet | China, late 18th–19th century | [42748](https://www.metmuseum.org/art/collection/search/42748) |
| Cairo Garden | Carpet | Egypt, 17th century | [446957](https://www.metmuseum.org/art/collection/search/446957) |
| Anatolian Gold | Carpet | Turkey, 17th century | [447544](https://www.metmuseum.org/art/collection/search/447544) |
| Ivory Field | Carpet | Turkey, 18th century | [452569](https://www.metmuseum.org/art/collection/search/452569) |
| Prayer Rug | Carpet | Turkey, 1774 | [451690](https://www.metmuseum.org/art/collection/search/451690) |

To add one: download a public-domain carpet's full image from the Met, then
`swiftc -O scripts/crop-rug.swift -o /tmp/crop-rug && /tmp/crop-rug in.jpg Rugs/<objectID>.jpg 2200`,
and add a case to `Pattern` in `Sources/Patterns.swift`.
