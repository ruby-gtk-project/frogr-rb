{
  adwaita = {
    dependencies = ["gtk4" "rake"];
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.org"];
      sha256 = "0qbk27kw9bama2s3sz7f9zwkwk11mjxsbp1rhdihhmnxmxzmwwkk";
      type = "gem";
    };
    version = "4.3.8";
  };
  atk = {
    dependencies = ["glib2" "rake"];
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.org"];
      sha256 = "0574x56ia234w93wshmj72lq9b8c98xl898mqiva28i71rdv7c2q";
      type = "gem";
    };
    version = "4.3.8";
  };
  cairo = {
    dependencies = ["pkg-config" "red-colors"];
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.org"];
      sha256 = "08x6f2idyfnylq0b66mqi8lf5mjvff2y2q02n5hq0x4i3ha5cwz5";
      type = "gem";
    };
    version = "1.18.5";
  };
  cairo-gobject = {
    dependencies = ["cairo" "glib2"];
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.org"];
      sha256 = "1v4kbpp3mh26r4ii0nhk28vsaypisiwsj9is998iv08dh3bklwff";
      type = "gem";
    };
    version = "4.3.8";
  };
  fiddle = {
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.org"];
      sha256 = "1vifygrkw22gcd4wzh8gc4pv6h1zpk6kll6mmprrf5174wvfxa3z";
      type = "gem";
    };
    version = "1.1.8";
  };
  gdk4 = {
    dependencies = ["cairo-gobject" "gdk_pixbuf2" "pango" "rake"];
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.org"];
      sha256 = "16gycdnj6alljcxgwn9jj21w797li46fnv9697sjy4gpvlr9wnkb";
      type = "gem";
    };
    version = "4.3.8";
  };
  gdk_pixbuf2 = {
    dependencies = ["gio2" "rake"];
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.org"];
      sha256 = "13jw3gkzcn4wrna8dnrckiflaw3mv675idmd0iybz8zg599fv2ky";
      type = "gem";
    };
    version = "4.3.8";
  };
  gio2 = {
    dependencies = ["fiddle" "gobject-introspection"];
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.org"];
      sha256 = "0i6zqxq83m79cdf00xqg8zdfcjdkl9bfz8ny37v10ygd65gfmx06";
      type = "gem";
    };
    version = "4.3.8";
  };
  glib2 = {
    dependencies = ["native-package-installer" "pkg-config"];
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.org"];
      sha256 = "1d3ijq8nqaw4c40whvm0zchgm91c5vrgkvjj0li5zil472n4v33v";
      type = "gem";
    };
    version = "4.3.8";
  };
  gobject-introspection = {
    dependencies = ["glib2"];
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.org"];
      sha256 = "08859brzkd7ql1hnx8czpyxw4gjxckbplx7brpjdb5qg6fwnic65";
      type = "gem";
    };
    version = "4.3.8";
  };
  graphene1 = {
    dependencies = ["gobject-introspection"];
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.org"];
      sha256 = "04xw4amm43qb4f0qd99hakh5qqa1c8xg02yxsxqc1xkqji5dfhiq";
      type = "gem";
    };
    version = "4.3.8";
  };
  gsk4 = {
    dependencies = ["gdk4" "graphene1"];
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.org"];
      sha256 = "040g47ah520g9jaa8pgnlazp0k61fprd74ypn9a8clf4swbv98cq";
      type = "gem";
    };
    version = "4.3.8";
  };
  gtk4 = {
    dependencies = ["atk" "gdk4" "gsk4"];
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.org"];
      sha256 = "1asbhbclh3n93j61wgxnmr2pb1zc9shvrk5sdaijk70zsgd6bgpc";
      type = "gem";
    };
    version = "4.3.8";
  };
  json = {
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.org"];
      sha256 = "0shwgjqbj856mb6m9kgkpy08nhym2gdvc2yaprlimfmky9y3n78z";
      type = "gem";
    };
    version = "2.21.2";
  };
  matrix = {
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.org"];
      sha256 = "0nscas3a4mmrp1rc07cdjlbbpb2rydkindmbj3v3z5y1viyspmd0";
      type = "gem";
    };
    version = "0.4.3";
  };
  native-package-installer = {
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.org"];
      sha256 = "0bvr9q7qwbmg9jfg85r1i5l7d0yxlgp0l2jg62j921vm49mipd7v";
      type = "gem";
    };
    version = "1.1.9";
  };
  pango = {
    dependencies = ["cairo-gobject" "gobject-introspection"];
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.org"];
      sha256 = "1gk43gwsnfkywz5fqjxcjf5jl5bh60zj2v597s9k3cfa19ks0y60";
      type = "gem";
    };
    version = "4.3.8";
  };
  pkg-config = {
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.org"];
      sha256 = "0cy75ssbwjzi9z3zwfx2zq3b8xvpy9rbdf1rnhi3v612acfgiy9k";
      type = "gem";
    };
    version = "1.6.5";
  };
  rake = {
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.org"];
      sha256 = "009p524zl0p0kfa65nii8wdmaigkmawv9pbvlcffky7islmmp0nb";
      type = "gem";
    };
    version = "13.4.2";
  };
  red-colors = {
    dependencies = ["json" "matrix"];
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.org"];
      sha256 = "16lj0h6gzmc07xp5rhq5b7c1carajjzmyr27m96c99icg2hfnmi3";
      type = "gem";
    };
    version = "0.4.0";
  };
  rexml = {
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.org"];
      sha256 = "0hninnbvqd2pn40h863lbrn9p11gvdxp928izkag5ysx8b1s5q0r";
      type = "gem";
    };
    version = "3.4.4";
  };
}
