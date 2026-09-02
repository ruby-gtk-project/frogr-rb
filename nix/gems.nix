# The bundled gem environment, shared by the package and the devshell.
#
# nixpkgs' defaultGemConfig already knows how to build the GTK3-era ruby-gnome
# gems (glib2, gio2, cairo, atk, pango, gdk_pixbuf2, gobject-introspection),
# so those are inherited untouched. What it has no entries for is the GTK4
# generation this port is built on — graphene1, gdk4, gsk4, gtk4 and adwaita —
# which is what this file adds.
#
# ruby-gnome drives its extconf.rb entirely through the pkg-config gem, and
# pkg-config resolves `Requires`/`Requires.private` transitively, so each gem
# needs not just its own library but every .pc file that library pulls in.
# A missing one fails the build with `.pc doesn't exist: <foo>`.
{ lib
, stdenv
, bundlerEnv
, ruby
, defaultGemConfig
, pkg-config
, bundler
, rake
, binutils
, wrapGAppsHook4
, gobject-introspection
, glib
, atk
, cairo
, pango
, harfbuzz
, fribidi
, gdk-pixbuf
, graphene
, gtk4
, libadwaita
, pcre2
, libepoxy
, libdatrie
, libthai
, libsysprof-capture
, libdeflate
, libwebp
, lerc
, xz
, zstd
, libpthread-stubs
, libxkbcommon
, util-linux
, libselinux
, libsepol
, systemd
, xorg
}:

let
  # The .pc closure shared by everything downstream of gtk4. Kept in one place
  # because gdk4, gsk4, gtk4 and adwaita all resolve the same graph.
  gtk4Closure = [
    gtk4
    gobject-introspection
    wrapGAppsHook4
    glib
    atk
    cairo
    pango
    harfbuzz
    fribidi
    gdk-pixbuf
    graphene
    pcre2
    libepoxy
    libdatrie
    libthai
    libsysprof-capture
    libdeflate
    libwebp
    lerc
    xz
    zstd
    libpthread-stubs
    libxkbcommon
    xorg.libXdmcp
    xorg.libXtst
  ];

  # ruby-gnome's extconf.rb shells out to rake and bundler while generating
  # its binding sources, so both belong in nativeBuildInputs.
  gnomeGem = propagated: attrs: {
    nativeBuildInputs = [ pkg-config bundler rake binutils ];
    buildInputs = lib.optionals stdenv.hostPlatform.isLinux [
      util-linux
      libselinux
      libsepol
      systemd
    ];
    propagatedBuildInputs = propagated;
  };
in
bundlerEnv {
  name = "frogr-rb-gems";
  inherit ruby;

  gemdir = ../.;
  gemfile = ../Gemfile;
  lockfile = ../Gemfile.lock;
  gemset = ../gemset.nix;

  gemConfig = defaultGemConfig // {
    graphene1 = gnomeGem [ graphene glib gobject-introspection pcre2 ];
    gdk4 = gnomeGem gtk4Closure;
    gsk4 = gnomeGem gtk4Closure;
    gtk4 = gnomeGem gtk4Closure;
    adwaita = gnomeGem (gtk4Closure ++ [ libadwaita ]);
  };
}
