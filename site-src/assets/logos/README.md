# Package logos

The tile next to a package on the Home and Browse pages shows its vendor's logo when there is a file
here, and two or three letters (AD, CS, 365) when there isn't.

- Name the file after the package id (letter case does not matter): `ActiveDirectory.svg`, `Microsoft365.svg`, `Rubrik.png`.
- SVG is best. PNG or WebP work too; make them at least 96×96.
- Square, with the mark centred and little or no padding. The tile adds its own padding on a white
  background in both themes, so dark and coloured marks both read.
- No `<script>`, external references or embedded fonts in SVGs. Logos are shown with `<img>`, which
  blocks scripts anyway, but keep them clean.

The build writes `assets/logos/index.json` listing the files it finds, and the site only requests the
logos in that list. Check each vendor's brand guidelines before adding its logo.
