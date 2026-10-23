# redmine_ulysses

Ulysses is a Redmine plugin for editing the issue page and the issue list in place, one field at a
time, each edit journaled as the edit form's would be. Its design is gh-plan's
[issue page and issue list design](https://github.com/pjfitzgibbons/gh-plan/blob/main/docs/design/0004-issue-ux.md).

This release loads and does nothing yet. It adds Turbo to Redmine's importmap and loads it on the
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

## Licence

GPL-2.0-or-later. See [LICENSE](LICENSE).
