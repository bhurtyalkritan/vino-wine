# vino-wine

The Wine that [Vino](https://github.com/bhurtyalkritan/vino) uses: CodeWeavers' CrossOver Wine, built for macOS.

Compared with WineHQ's Wine, it adds CodeWeavers' fixes for specific games and apps, and **MSync**, which makes many games run
smoother by using macOS's own synchronisation (turn it on with `WINEMSYNC=1`). It also includes Wine Mono and Wine Gecko,
so .NET apps and built-in web views work and a new bottle never stops to ask to download them.

## Releases

Each release has:

- `vino-wine-<version>.tar.xz`: a self-contained Wine folder (`bin/wine`, `lib`, `share`), and its `.sha256`
- `crossover-sources-<version>.tar.gz`: the exact CodeWeavers source it was built from
- `wine-mono-*-src.tar.xz`, `wine-gecko-*-src.tar.xz` and the (L)GPL libraries' source

## Building

`build.sh` does everything: downloads and checks the CrossOver source, builds 64- and 32-bit Windows support, bundles the
libraries Wine needs, packages it and runs a self-test. It needs an Intel Mac (or Rosetta) with Homebrew:

```
brew install bison flex mingw-w64 pkgconf freetype gnutls sdl2 molten-vk gettext
./build.sh
```

GitHub Actions runs the same script (`.github/workflows/build.yml`); pushing a `v*` tag publishes a release.

## Licenses

Wine is LGPL 2.1, © the Wine project and CodeWeavers; vino-wine builds CodeWeavers' published source unmodified, and each
release attaches that exact source. The bundled libraries (FreeType, GnuTLS, SDL2, MoltenVK and what they depend on) keep
their own licenses: each build lists them in `share/licenses/LIBRARIES.txt` with their license files, and each release
attaches the source of the (L)GPL ones. The build scripts here are MIT.

vino-wine is not affiliated with or endorsed by CodeWeavers. CrossOver and CodeWeavers are trademarks of CodeWeavers, Inc.
