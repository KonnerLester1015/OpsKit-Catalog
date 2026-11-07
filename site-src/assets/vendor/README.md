# Vendored libraries

Pinned copies, served from this site. No CDN. To update one, download the new version from the npm
registry (`npm pack <name>@<version>`), copy the same files into a folder named after the new version,
update the imports in `assets/js/package.js`, and update this table.

| Library | Version | npm package | Files | Licence |
| --- | --- | --- | --- | --- |
| highlight.js | 11.10.0 | `@highlightjs/cdn-assets` | `es/core.min.js`, `es/languages/powershell.min.js`, `es/languages/markdown.min.js` | BSD-3-Clause |
| marked | 12.0.2 | `marked` | `lib/marked.esm.js` | MIT |
| DOMPurify | 3.1.6 | `dompurify` | `dist/purify.es.mjs` (renamed to `.js`) | MPL-2.0 or Apache-2.0 |

The `//# sourceMappingURL` comment was removed from `marked.esm.js` and `purify.es.js`, because the
source maps are not vendored. The files are otherwise unchanged.

SHA-256 of the vendored files:

```
224f718d73f37e1b85fbab697b57d75dc2013e57bc0485a8fa8534070f3e543a  highlight.js-11.10.0/core.min.js
c1e6e89c6dd9396e40685223b74a196dfe90b7bb1c649383416e812707a96766  highlight.js-11.10.0/languages/powershell.min.js
7c4d51048f70942567516362d28ec4db545c50525498e9f44ca769ce7b936e7f  highlight.js-11.10.0/languages/markdown.min.js
b0b3f4422286d6492ea710c5ad3264cfee13c426d2ed2d4a685c63a4ac2b32c7  marked-12.0.2/marked.esm.js
7be83849e5848639dd9dfbffcfa9f6ff90743c33ac289e3dc6d45bab8a10fccd  dompurify-3.1.6/purify.es.js
```
