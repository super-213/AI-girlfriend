This folder bundles markdown-it 14.1.0 and KaTeX 0.18.7 for offline conversation rendering.
Their licenses are included as LICENSE.markdown-it and LICENSE.katex.

Xcode copies these resources into the app bundle's Resources root. The KaTeX CSS
therefore uses font URLs without its original `fonts/` prefix; keep that change
when updating KaTeX.
