# The bundled gem environment, shared by the package and the devshell.
#
# Every ruby-gnome gem is a C extension that links against the corresponding
# system library, so each one needs an explicit gemConfig entry naming its
# pkg-config inputs — nixpkgs' defaultGemConfig only covers the GTK3-era gems.
{ lib
, bundlerEnv
, ruby
, pkg-config
, defaultGemConfig
, glib
, gobject-introspection
, atk
, cairo
, pango
, gdk-pixbuf
, graphene
, gtk4
, libadwaita
, libffi
, harfbuzz
}:

let
  # ruby-gnome's extconf.rb drives everything through the pkg-config gem, so a
  # gem builds as soon as its libraries are on PKG_CONFIG_PATH.
  gnomeGem = buildInputs: attrs: {
    nativeBuildInputs = [ pkg-config ];
    inherit buildInputs;
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
    glib2 = gnomeGem [ glib ];
    gobject-introspection = gnomeGem [ glib gobject-introspection ];
    gio2 = gnomeGem [ glib gobject-introspection ];
    atk = gnomeGem [ glib atk ];
    cairo = gnomeGem [ cairo ];
    cairo-gobject = gnomeGem [ glib cairo ];
    pango = gnomeGem [ glib cairo pango harfbuzz ];
    gdk_pixbuf2 = gnomeGem [ glib gdk-pixbuf ];
    graphene1 = gnomeGem [ glib graphene ];
    gdk4 = gnomeGem [ glib gtk4 ];
    gsk4 = gnomeGem [ glib gtk4 graphene ];
    gtk4 = gnomeGem [ glib gtk4 ];
    adwaita = gnomeGem [ glib gtk4 libadwaita ];
    fiddle = gnomeGem [ libffi ];
  };
}
