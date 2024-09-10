# Change Log

All notable changes to this project will be documented in this file.
See [Conventional Commits](Https://conventionalcommits.org) for commit guidelines.

<!-- changelog -->
## [v0.1.4](https://github.com/ibarakaiev/fireside/compare/v0.1.3...v0.1.4) (2024-09-09)

### Fixes
- use `Igniter.Util.DepsCompile.run()` instead of `Mix.Task.run("deps.compile")`
- upgrade deprecated code

## [v0.1.3](https://github.com/ibarakaiev/fireside/compare/v0.1.2...v0.1.3) (2024-08-16)

### Fixes
- remove `append?: true` when installing components (will be reverted)
- minor wording changes across documentation

## [v0.1.2](https://github.com/ibarakaiev/fireside/compare/v0.1.1...v0.1.2) (2024-08-14)

### Improvements
- add small Fireside logo to docs

## [v0.1.1](https://github.com/ibarakaiev/fireside/compare/v0.1.0...v0.1.1) (2024-08-14)

### Improvements
- add Fireside logo and hex badges

### Fixes
- typos

## [v0.1.0](https://github.com/ibarakaiev/fireside/compare/v0.0.3...v0.1.0) (2024-08-14)

### Improvements

- change the format of `fireside.exs` and `config/fireside.exs`
- add `fireside.unlock` and `fireside.uninstall`
- add versioning and component upgrades
- add `--unlocked` option to `fireside.install` and `--yes` option to all tasks
- add Git and Github support
- documentation improvements

## [v0.0.3](https://github.com/ibarakaiev/fireside/compare/v0.0.2...v0.0.3) (2024-08-01)

### Improvements

- Add Changelog to docs

### Bug fixes

- support no `overwritable` in `fireside.install`.

## [v0.0.2](https://github.com/ibarakaiev/fireside/compare/v0.0.1...v0.0.2) (2024-07-21)

### Improvements

- replace OTP application name in addition to module prefixes
  (i.e. :my_app in addition to MyApp)
