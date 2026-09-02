# frogr-rb

A Ruby port of [frogr](https://gitlab.gnome.org/GNOME/frogr), the Flickr Remote
Organizer for GNOME, rewritten on **GTK4 + Libadwaita** using the
[ruby-gnome](https://github.com/ruby-gnome/ruby-gnome) bindings.

The upstream project is ~21k lines of C (including `flicksoup`, its bundled
Flickr client). This port keeps the same feature set and the same on-disk
configuration format, expressed in the declarative memoized-widget style: every
widget is a memoized method, all styling lives in `tap` blocks, and assembly
happens in a single `build` method per component.

## Running

```sh
nix develop      # ruby + bundled gems + gtk4/libadwaita
ruby bin/frogr
```

or, without entering a shell:

```sh
nix run
```

## Tests

```sh
nix develop --command ruby test/run_tests.rb
```

These cover the places where a subtle mistake would not show up in the UI:
OAuth 1.0a signature base strings, EXIF/XMP parsing, tag quoting, and the two
on-disk formats that must stay compatible with upstream frogr.

The UI is tested by running it, headlessly - no display server needed:

```sh
nix develop --command ruby test/drive_main_window.rb
```

It loads the fixtures, works the menu actions, edits through the details dialog
and checks the model followed, writing screenshots to `tmp/shots/` as it goes.

## Layout

```
bin/frogr              entry point — `Frogr::App.new.build.run`
lib/frogr/
  models/              Picture, PhotoSet, Group, Location, Account
  flickr/              Flickr REST client (replaces flicksoup)
  config.rb            XML settings persistence (~/.config/frogr)
  model.rb             the in-memory document: pictures, sets, groups, tags
  controller.rb        session + upload orchestration
  file_loader.rb       async image loading and thumbnailing
  ui/                  main view and dialogs
data/                  icons, desktop file, appstream metadata, man page
po/, help/             translations and user documentation (carried over)
```

## Notes on the bindings

Binding bugs found during the port - including a GVariant property setter that
segfaults the interpreter - are written up with reproductions in
[FINDINGS.md](FINDINGS.md). The workarounds live in `lib/frogr/gnome_compat.rb`
and are covered by the test suite, which also reports when they stop being
necessary.

The `ruby-gtk` house guide records `Adwaita::ApplicationWindow` as unusable
from Ruby. That is no longer true as of **ruby-gnome 4.3.8**: it builds,
accepts actions, and — unlike `Gtk::ApplicationWindow` — lets `Adwaita::Dialog`
present *inside* the window rather than spawning a separate toplevel. This port
uses it, verified against its full widget tree, actions and dialogs.

`Gtk::IconTheme` exposes `get_for_display`, not `for_display`, and setting
`GtkSettings:gtk-application-prefer-dark-theme` is unsupported under libadwaita
— the dark theme preference goes through `Adwaita::StyleManager#color_scheme`.

## Relocking the gems

```sh
bundle lock --update
bundix --lockfile=Gemfile.lock --gemset=gemset.nix
```

## Licence

GPL-3.0-only, as upstream. See `COPYING`.
