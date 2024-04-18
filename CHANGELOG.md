# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed

- Prevent infinite loops when throttling an enumerator

### Added

- Support for Ruby versions 3.2 and 3.3

### Changed

- Move RuboCop configuration closer to defaults
- Treat throttler max wait time as a hard cap

## [0.8.2] - 2022-10-20

### Added

- Support for Ruby versions 3.0 and 3.1
- Support for Faraday versions 1.x and 2.x

### Changed

- Moved build to GitHub Actions
- Update RuboCop to target Ruby 2.7

### Removed

- Support for EOL Ruby versions 2.5 and 2.6

## [0.8.1] - 2020-06-09

### Added

- Ability to add a single decorator

## [0.8.0] - 2020-06-09

### Added

- Support for Ruby versions 2.6 and 2.7
- Support for Freno's "low priority" checks

### Changed

- Update RuboCop to target Ruby 2.5
- Changed authorship to "GitHub"

### Removed

- Support for EOL Ruby versions 2.3 and 2.4

## [0.7.0] - 2019-01-23

### Added

- Support for Ruby version 2.7

### Changed

- Prevent decorator reuse

### Removed

- Support for EOL Ruby versions 2.1 and 2.2

## [0.6.0] - 2017-10-09

### Added

- Throttlers!

## [0.5.0] - 2017-10-09

### Added

- Custom error classes

### Changed

- Simplify gem release and its documentation

## [0.4.0] - 2017-08-29

### Added

- RuboCop configuration and build step
- Wrapping raised errors in Freno::Error

## [0.3.0] - 2017-07-07

### Changed

- Require a Ruby version 2.0 or greater
- Relax Faraday's version requirement

## [0.2.0] - 2017-07-07

### Added

- Initial import
- Change ownership and contact information to GitHub

[unreleased]: https://github.com/github/freno-client/compare/v0.8.2...HEAD
[0.8.2]: https://github.com/github/freno-client/compare/v0.8.1...v0.8.2
[0.8.1]: https://github.com/github/freno-client/compare/v0.8.0...v0.8.1
[0.8.0]: https://github.com/github/freno-client/compare/v0.7.0...v0.8.0
[0.7.0]: https://github.com/github/freno-client/compare/v0.6.0...v0.7.0
[0.6.0]: https://github.com/github/freno-client/compare/v0.5.0...v0.6.0
[0.5.0]: https://github.com/github/freno-client/compare/v0.4.0...v0.5.0
[0.4.0]: https://github.com/github/freno-client/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/github/freno-client/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/github/freno-client/commits/v0.2.0
