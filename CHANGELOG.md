# Changelog

## [0.1.11] - 2025-06-08

- Add automatic cleanup of completed journeys after a configurable time period
- Add `HousekeepingJob` to run cleanup and recovery tasks
- Add ability to extend all StepperMotor jobs with custom configuration
- Merge V2/V1 job variants into single classes with backward compatibility
- Pin standardrb version to avoid Rubocop errors
- Improve documentation and test coverage

## [0.1.10] - 2025-05-28

- Remove `algorithm: :concurrently` from migrations. If a user needs to conform with strong_migrations
  they can always edit the migration themselves.

## [0.1.9] - 2025-05-25

- Repair bodged migration from the previous release

## [0.1.8] - 2025-05-25

- Add ability to pause and resume journeys (https://github.com/stepper-motor/stepper_motor/pull/24)
- Add basic exception rescue during steps (https://github.com/stepper-motor/stepper_motor/pull/23)
- Add idempotency keys when performing steps (https://github.com/stepper-motor/stepper_motor/pull/21)
- Add support for blockless step definitions (https://github.com/stepper-motor/stepper_motor/pull/22)
- Migrate from RSpec to Minitest (https://github.com/stepper-motor/stepper_motor/pull/19)
- Add Rake task for recovery
- Add proper Rails engine tests
- Improve test organization and coverage
- Add frozen string literals
- Relocate Recovery into a module

## [0.1.7] - 2025-05-19

- Improve Rails integration reliability:
  - Load Railtie earlier in the boot process
  - Fix generator loading to use relative paths instead of load paths
- Improve database migration for stuck journeys:
  - Add concurrent index creation for better performance
  - Fix index creation to work in all environments

## [0.1.6] - 2025-05-19

- Add functionality to recover journeys stuck in "performing" state
- Add `RecoverStuckJourneysJobV1` with two recovery modes:
  - `:reattempt`: Tries to restart the step where the journey hung
  - `:cancel`: Cancels the journey
- Add database index to assist with stuck journey recovery
- Add test coverage for recovery scenarios
- Add ability to configure recovery behavior per journey class

## [0.1.5] - 2025-03-17

- Refactor PerformStepJob to use Journey class in job arguments
- Remove GlobalID dependency
- Add ability to resolve Journey from base class using `find()`

## [0.1.4] - 2025-03-11

- Fix critical bug with endless self-replication of PerformStepJobs
- Fix misnamed ActiveJob parameter that caused immediate job execution
- Add test to ensure proper parameter passing to ActiveJob
- Improve job scheduling reliability

## [0.1.3] - 2025-02-28

- Add test suite with journey behavior testing
- Add support for UUID foreign keys in migrations
- Add Rails engine integration with Railtie
- Add support for concurrent index creation
- Add error handling for database initialization
- Add support for eager loading in Rails applications
- Add logging with tagged contexts
- Add support for step reattempts and cancellations
- Add support for multiple journeys per hero with `allow_multiple` option
- Add state tracking with steps_entered and steps_completed counters
- Add support for both wait: and after: timing options in steps
- Add error handling for invalid step configurations

## [0.1.2] - 2025-01-01

- Fix Railtie integration
- Ensure proper Rails engine functionality

## [0.1.1] - 2025-01-01

- Update dependencies
- Improve compatibility with latest gem versions

## [0.1.0] - 2024-09-29

- Initial release
- Add basic stepper motor functionality
- Add Rails integration support
