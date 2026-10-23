# redmine_ulysses

Ulysses is a Redmine plugin for editing the issue page and the issue list in place, one field at a
time, each edit journaled as the edit form's would be. Its design is gh-plan's
[issue page and issue list design](https://github.com/pjfitzgibbons/gh-plan/blob/main/docs/design/0004-issue-ux.md).

This release edits nothing yet. It draws every Redmine page from the Ulysses theme, which a site
can change in one file (see *Theming*). It adds Turbo to Redmine's importmap and loads it on the
issue page only, with Turbo Drive off, so core's links and forms navigate as they always have. It
registers the plugin's Stimulus controllers beside core's.

It needs Redmine 7.0.2 or later. It changes no table, adds no migration and leaves the REST API
as core has it.

## Installing

1. Put the plugin in Redmine's `plugins/` directory as `redmine_ulysses`:
   ```
   cd /path/to/redmine
   git clone https://github.com/pjfitzgibbons/redmine_ulysses.git plugins/redmine_ulysses
   ```
   In the official Redmine Docker image, `/path/to/redmine` is `/usr/src/redmine`. Mounting the
   checkout at `/usr/src/redmine/plugins/redmine_ulysses` works as well.
2. In production, compile the assets again: `RAILS_ENV=production bin/rails assets:precompile`.
3. Restart Redmine. *Administration › Plugins* lists Ulysses.

To remove it, delete `plugins/redmine_ulysses` and restart Redmine. There is nothing to migrate
down.

## Theming

Ulysses draws Redmine from the `--uly-*` custom properties of its theme contract, listed in
`lib/redmine_ulysses/theme.rb`. Every page loads, after core's stylesheet:

1. `tokens.css`, the reference theme: a value for every property, in light and dark, with IBM Plex
   served from the plugin.
2. `base.css`, which points core's colour and font variables at the contract and restyles the few
   places core uses a literal colour. It sets no value of its own.
3. `public/ulysses/theme.css`, the site's theme, when the file exists.

Ulysses isn't a Redmine theme. Leave *Administration › Settings › Display › Theme* on Default;
another theme loads before Ulysses and its colours are overridden where the contract reaches.

[`docs/design-book.html`](docs/design-book.html) shows every property of the reference in light and
dark, with the contrast of each text and ground pair. Browsers won't let a page read a stylesheet's
rules over `file://`, so serve the checkout and open it there:
`ruby -run -e httpd . -p 8000`, then `http://127.0.0.1:8000/docs/design-book.html`.

### Writing `public/ulysses/theme.css`

Set only the properties you change; the reference supplies the rest. A file holds `:root` blocks,
one dark block, a reduced-motion block and `@font-face` rules, and nothing else:

```css
@font-face {
  font-family: "Source Serif";
  src: url("fonts/SourceSerif4-Semibold.woff2") format("woff2");
  font-weight: 600;
}

:root {
  --uly-primary: #00563f;
  --uly-primary-fill: #00563f;
  --uly-header-to: #00563f;
  --uly-font-serif: "Source Serif", Georgia, serif;
}

@media (prefers-color-scheme: dark) {
  :root {
    --uly-primary: #6fd3a8;
    --uly-header-to: #003d2c;
  }
}
```

- A value in `:root` applies in light and in dark, unless the dark block sets the property again.
  Set a colour in both when the light value won't read on the dark grounds.
- Fonts go beside the file, in `public/ulysses/fonts/`, and the `url()` is relative to it. Serve
  them from Redmine itself: Ulysses loads nothing from another host.
- Values are plain CSS. The check reads colours as `#rgb`, `#rrggbb`, `rgb()` or `var()` of another
  `--uly-*` property.
- Redmine serves `public/` as it is. The link carries the file's modification time, so a saved
  change shows on the next page load, with no restart and no asset compile.

### Checking a theme

```
bin/rake redmine_ulysses:theme:check
bin/rake "redmine_ulysses:theme:check[path/to/theme.css]"
```

Run it from Redmine's directory. With no argument it checks `public/ulysses/theme.css`. It fails on
a property the contract doesn't have, on anything in the file besides the blocks above, on a colour
it can't read, and on any text and ground pair under 4.5:1, or header text under 5.6:1, in light
or dark, measured on the reference with your file applied. It needs no database, so it runs
before a deploy as well as on the server.

## Testing

```
bin/test
```

builds the test harness, runs every plugin test through
`bin/rake redmine:plugins:test NAME=redmine_ulysses`, unit to system, the system tests in Chromium,
and takes the harness down again. It needs Docker, and runs on arm64 and amd64. Arguments go to
the rake task, as in `bin/test TESTOPTS=-v`.

| File | Holds |
|---|---|
| `test/Dockerfile` | Redmine 7.0.2 with the test gems, a compiler for them and a migrated SQLite test database |
| `test/compose.yml` | That image, with the plugin mounted at `plugins/redmine_ulysses`, and a Chromium container for the system tests |
| `test/database.yml` | The `test:` database, on SQLite |
| `test/support/` | A probe page and endpoint the system tests drive Turbo through. It and its routes exist only while the system tests run |
| `test/snapshots/` | The key paths of `/issues/:id.json` and `/issues.json` |

The tests use Redmine's own fixtures and invented data, nothing else.

The containers run only while `bin/test` does. The images stay on disk afterwards so the next run
starts at once; `docker image rm redmine-ulysses-test:7.0.2` and the Chromium image free the space.
On a first run it downloads:

| What | From | Size on disk |
|---|---|---|
| `redmine:7.0.2` | Docker Hub | about 1.1 GB |
| `build-essential` and its dependencies | Debian's package mirrors | |
| Redmine's test and development gems, about 50 | rubygems.org | |
| The built test image, all of the above | | about 1.6 GB |
| `selenium/standalone-chromium:155.0.8059.39-chromedriver-155.0.8059.39-grid-4.51.0-20261010` | Docker Hub | about 3.4 GB |

The API key snapshots fail when the plugin adds or loses a key. After a Redmine upgrade, check
that the new keys are core's, then rewrite them with `ULYSSES_SNAPSHOT=1 bin/test`.

## Third-party code

`assets/javascripts/turbo.js` is [Turbo](https://turbo.hotwired.dev) 8.0.23,
`dist/turbo.es2017-esm.js` from the npm package `@hotwired/turbo`, unchanged, under the MIT
licence, © 37signals LLC; its notice is in `licenses/turbo.txt`.

`assets/stylesheets/fonts/` holds [IBM Plex](https://github.com/IBM/plex) Sans, Serif and Mono as
WOFF2, from the npm packages `@ibm/plex-sans` 1.1.0, `@ibm/plex-serif` 2.0.0 and
`@ibm/plex-mono` 2.5.0, unchanged, under the SIL Open Font License 1.1, © IBM Corp.; the licence is
in `licenses/ibm-plex.txt`.

`docs/theme-candidates.html`, the palettes and fonts weighed before this one, loads its fonts from
Google Fonts. It's a record of that choice and isn't part of the plugin.

## Licence

GPL-2.0-or-later. See [LICENSE](LICENSE).
