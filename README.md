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

## Relocking the gems

```sh
bundle lock --update
bundix --lockfile=Gemfile.lock --gemset=gemset.nix
```

## Licence

GPL-3.0-only, as upstream. See `COPYING`.
