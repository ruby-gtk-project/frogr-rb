# ruby-gnome binding findings

Bugs and behaviour differences found in the Ruby GNOME bindings while porting
frogr from C/GTK3 to Ruby/GTK4. Each entry has a minimal reproduction that was
actually executed, not recalled.

Workarounds for the crashing and silently-failing cases live in
`lib/frogr/gnome_compat.rb`, which is loaded before any GTK code runs. That file
is meant to be deleted once the bindings are fixed upstream; each shim names the
finding it works around.

## Environment

| Component | Version |
|---|---|
| ruby | 3.4.9 |
| `gtk4`, `glib2`, `gobject-introspection`, `adwaita` gems | 4.3.8 |
| GTK runtime | 4.22.4 |
| libadwaita runtime | 1.9.3 |

Run the reproductions with `nix develop --command ruby <file>`.

---

## 1. Assigning a GVariant property from a Ruby value segfaults

**Severity: high — takes the whole process down, no exception to rescue.**

`Gio::SimpleAction#state` unwraps its GVariant into a plain Ruby value on the
way out, but `#state=` does not convert on the way in. It casts whatever it is
given straight to a `GVariant*` without a type check, so the pointer it
dereferences is not a GVariant.

The clearest form of the bug is that a property cannot survive its own round
trip:

```ruby
require 'gtk4'

action = Gio::SimpleAction.new('toggle', nil, GLib::Variant.new(true))
action.state = action.state    # => SIGSEGV
```

**Expected:** either a working assignment, or a `TypeError`.
**Actual:** `rc=139` (SIGSEGV).

What gets assigned decides how it fails, which is what makes this hard to spot:

| Assigned value | Result |
|---|---|
| `true`, `false`, `42`, `:sym` | **SIGSEGV** |
| `"a string"` | `GLib-GIO-CRITICAL ... g_simple_action_set_state: assertion 'value != NULL' failed`, assignment **silently ignored** |
| `nil` | raises (the only case that fails safely) |
| `GLib::Variant.new(...)` | works |

The string case is the more dangerous one in practice: the process keeps
running with the old state, so a radio menu quietly shows the wrong item ticked.

The inconsistency is not uniform across the API — the same class converts Ruby
values happily elsewhere:

```ruby
action.activate('hello')          # converts fine
action.change_state(false)        # converts fine
action.state = false              # SIGSEGV
```

**Workaround:** route `state=` through `change_state`, which validates the value
against the action's state type and accepts both plain values and GVariants.
See `GnomeCompat` in `lib/frogr/gnome_compat.rb`.

## 2. `Gtk::Actionable#action_target=` silently drops a Ruby value

**Severity: medium — silent, no warning at all.**

Same root cause, quieter failure: no crash, no message, the target is simply
never set.

```ruby
require 'gtk4'

button = Gtk::Button.new
button.action_name = 'app.example'

button.action_target = 'hello'
button.action_target                      # => nil        (silently dropped)

button.action_target = GLib::Variant.new('hello')
button.action_target                      # => "hello"    (works)
```

**Workaround:** `GnomeCompat` wraps non-GVariant values before assigning.

## 3. Reading a GVariant property returns an unwrapped Ruby value

**Severity: low — fails loudly, but the C and Vala documentation misleads.**

Every GVariant reaching Ruby is already unwrapped, so the `GVariant` accessors
that the C API documentation tells you to call do not exist:

```ruby
action.state                 # => true, a TrueClass — not a GLib::Variant
action.state.get_boolean     # NoMethodError: undefined method 'get_boolean' for true

action.signal_connect('activate') do |_, parameter|
  parameter                  # => "by_title", a String — not a GLib::Variant
  parameter.get_string       # NoMethodError
end
```

This is defensible as a design choice; it is listed because combining it with
finding 1 produces the round-trip crash, and because porting C or Vala code
line by line walks straight into it.

**No workaround needed** — read the plain value and use it directly.

## 4. Class-level GI methods keep their `get_` prefix

**Severity: cosmetic — a naming inconsistency, not a bug.**

Instance getters drop the `get_` prefix, class-level ones keep it:

```ruby
Gtk::IconTheme.for_display(display)      # NoMethodError
Gtk::IconTheme.get_for_display(display)  # works

icon_theme.search_path                   # works — no get_ prefix here
```

Worth knowing when a documented `gtk_icon_theme_get_for_display` does not appear
where you expect it. `signal_emit` is the same kind of thing: there is no
`emit`, only `signal_emit`.

## 5. Corrections to previously-documented breakage

Two things the `ruby-gtk` skill's `adwaita-quirks.md` listed as unusable are
fine on 4.3.8. Both were verified by constructing them and running a full
activate/present cycle:

```ruby
require 'adwaita'

app = Adwaita::Application.new('org.example.app', :default_flags)
app.signal_connect('activate') do
  window = Adwaita::ApplicationWindow.new(app)
  window.content = Gtk::Label.new('hi')     # note: content=, not child=
  window.present                            # works
  app.quit
end
app.run([])
```

`Adwaita::ApplicationWindow` is worth preferring over `Gtk::ApplicationWindow`:
an `Adwaita::Dialog` presented on it appears *inside* the window, whereas on the
Gtk one it becomes a separate toplevel (`Gtk::Window.list_toplevels.length`
stays at 1 versus rising to 2).

This app uses `Gtk::Application` with `Adwaita::ApplicationWindow` — the
Adwaita application class works, but nothing here needs it.

---

## Reporting upstream

Findings 1 and 2 are genuine bugs worth filing against
[ruby-gnome/ruby-gnome](https://github.com/ruby-gnome/ruby-gnome): a property
setter should never be able to segfault the interpreter from pure Ruby, and
`action.state = action.state` is a one-line reproduction. Not yet filed.
