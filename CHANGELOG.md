# Changelog

## [v1.3.2](https://github.com/bensheldon/good_job/tree/v1.3.2) (2020-11-12)

[Full Changelog](https://github.com/bensheldon/good_job/compare/v1.3.1...v1.3.2)

**Fixed bugs:**

- \(bug\) MultiScheduler polling bug [\#171](https://github.com/bensheldon/good_job/issues/171)
- MultiScheduler should delegate to all schedulers when state is nil [\#172](https://github.com/bensheldon/good_job/pull/172) ([bensheldon](https://github.com/bensheldon))

## [v1.3.1](https://github.com/bensheldon/good_job/tree/v1.3.1) (2020-11-01)

[Full Changelog](https://github.com/bensheldon/good_job/compare/v1.3.0...v1.3.1)

**Implemented enhancements:**

- Extract polling from scheduler into Polling object [\#128](https://github.com/bensheldon/good_job/issues/128)
- Format serialized params to ease reading [\#170](https://github.com/bensheldon/good_job/pull/170) ([morgoth](https://github.com/morgoth))

**Fixed bugs:**

- Don't disconnect a nil activerecord connection [\#161](https://github.com/bensheldon/good_job/pull/161) ([bensheldon](https://github.com/bensheldon))

**Closed issues:**

- Propose addition of GoodJob to queue-shootout benchmarks [\#40](https://github.com/bensheldon/good_job/issues/40)

**Merged pull requests:**

- Ensure Rails is a development dependency [\#169](https://github.com/bensheldon/good_job/pull/169) ([bensheldon](https://github.com/bensheldon))
- Fix Ruby 2.7 GH action by setting default bundler explicitly [\#166](https://github.com/bensheldon/good_job/pull/166) ([bensheldon](https://github.com/bensheldon))
- Cache ruby version explicitly in Github Action [\#165](https://github.com/bensheldon/good_job/pull/165) ([bensheldon](https://github.com/bensheldon))
- Update development dependencies, rubocop [\#164](https://github.com/bensheldon/good_job/pull/164) ([bensheldon](https://github.com/bensheldon))
- Fix intended constant hierarchy of GoodJob::Scheduler::ThreadPoolExecutor [\#158](https://github.com/bensheldon/good_job/pull/158) ([bensheldon](https://github.com/bensheldon))
- Add bin/test\_app executable for Rails debugging [\#157](https://github.com/bensheldon/good_job/pull/157) ([bensheldon](https://github.com/bensheldon))
- Extract Scheduler polling behavior to its own object [\#152](https://github.com/bensheldon/good_job/pull/152) ([bensheldon](https://github.com/bensheldon))

## [v1.3.0](https://github.com/bensheldon/good_job/tree/v1.3.0) (2020-10-03)

[Full Changelog](https://github.com/bensheldon/good_job/compare/v1.2.6...v1.3.0)

**Implemented enhancements:**

- Lengthen default poll interval from 1 to 5 seconds [\#156](https://github.com/bensheldon/good_job/pull/156) ([bensheldon](https://github.com/bensheldon))

**Merged pull requests:**

- Rename reperform\_jobs\_on\_standard\_error to retry\_on\_unhandled\_error [\#154](https://github.com/bensheldon/good_job/pull/154) ([morgoth](https://github.com/morgoth))

## [v1.2.6](https://github.com/bensheldon/good_job/tree/v1.2.6) (2020-09-29)

[Full Changelog](https://github.com/bensheldon/good_job/compare/v1.2.5...v1.2.6)

**Implemented enhancements:**

- Preserve only failed jobs [\#136](https://github.com/bensheldon/good_job/issues/136)
- Add `GoodJob.preserve\_job\_records = :on\_unhandled\_error` option to only preserve jobs that errored [\#145](https://github.com/bensheldon/good_job/pull/145) ([morgoth](https://github.com/morgoth))

**Fixed bugs:**

- Fix LogSubscriber notifications for finished\_timer\_task and finished\_job\_task [\#148](https://github.com/bensheldon/good_job/pull/148) ([bensheldon](https://github.com/bensheldon))

**Closed issues:**

- run-once guarantee? [\#151](https://github.com/bensheldon/good_job/issues/151)

**Merged pull requests:**

- Add info how to setup basic auth for engine [\#153](https://github.com/bensheldon/good_job/pull/153) ([morgoth](https://github.com/morgoth))
- Add documentation for Dashboard Rails::Engine [\#149](https://github.com/bensheldon/good_job/pull/149) ([bensheldon](https://github.com/bensheldon))
- Style cleanup to Job error handling [\#147](https://github.com/bensheldon/good_job/pull/147) ([bensheldon](https://github.com/bensheldon))
- Replace gerund titles in Readme [\#146](https://github.com/bensheldon/good_job/pull/146) ([bensheldon](https://github.com/bensheldon))
- Only allow Scheduler to be initialized with max\_threads and poll\_interval; remove full access to pool and timer\_task options [\#137](https://github.com/bensheldon/good_job/pull/137) ([bensheldon](https://github.com/bensheldon))

## [v1.2.5](https://github.com/bensheldon/good_job/tree/v1.2.5) (2020-09-17)

[Full Changelog](https://github.com/bensheldon/good_job/compare/v1.2.4...v1.2.5)

**Implemented enhancements:**

- Use Zeitwerk for auto-loading [\#87](https://github.com/bensheldon/good_job/issues/87)
- Spike on data dashboard; pull in full Bootstrap CSS and JS [\#131](https://github.com/bensheldon/good_job/pull/131) ([bensheldon](https://github.com/bensheldon))

**Fixed bugs:**

- `poll-interval=-1` does not disable polling as intended [\#133](https://github.com/bensheldon/good_job/issues/133)
- Update Gemspec to reflect that GoodJob is not compatible with Rails 5.1 [\#143](https://github.com/bensheldon/good_job/pull/143) ([bensheldon](https://github.com/bensheldon))
- Prevent jobs hanging [\#141](https://github.com/bensheldon/good_job/pull/141) ([morgoth](https://github.com/morgoth))
- Add explicit require\_paths to gemspec for engine [\#134](https://github.com/bensheldon/good_job/pull/134) ([bensheldon](https://github.com/bensheldon))
- Use `connection.quote\_table\_name` and add spacing for SQL concatenation [\#124](https://github.com/bensheldon/good_job/pull/124) ([bensheldon](https://github.com/bensheldon))

**Closed issues:**

- Lint - Introduce line character limits [\#122](https://github.com/bensheldon/good_job/issues/122)
- Jobs are not processed in multi schema setup. Apartment + GoodJob \( post 1.1.2 \) [\#117](https://github.com/bensheldon/good_job/issues/117)
- Host a documentation sprint [\#48](https://github.com/bensheldon/good_job/issues/48)

**Merged pull requests:**

- Test GoodJob against Rails HEAD [\#144](https://github.com/bensheldon/good_job/pull/144) ([bensheldon](https://github.com/bensheldon))
- Drop Ruby 2.4 support [\#142](https://github.com/bensheldon/good_job/pull/142) ([morgoth](https://github.com/morgoth))
- Remove arguments from perform method [\#140](https://github.com/bensheldon/good_job/pull/140) ([morgoth](https://github.com/morgoth))
- Extract "execute" method to reduce "perform" method complexity [\#138](https://github.com/bensheldon/good_job/pull/138) ([morgoth](https://github.com/morgoth))
- Correct example on how to configure multiple queues by command line. [\#135](https://github.com/bensheldon/good_job/pull/135) ([morgoth](https://github.com/morgoth))
- Update ActionMailer Job class, to match the default [\#130](https://github.com/bensheldon/good_job/pull/130) ([morgoth](https://github.com/morgoth))
- Add initial Engine scaffold [\#125](https://github.com/bensheldon/good_job/pull/125) ([bensheldon](https://github.com/bensheldon))
- Zeitwerk Loader Implementation [\#123](https://github.com/bensheldon/good_job/pull/123) ([gadimbaylisahil](https://github.com/gadimbaylisahil))
- Update code-level documentation [\#111](https://github.com/bensheldon/good_job/pull/111) ([bensheldon](https://github.com/bensheldon))

## [v1.2.4](https://github.com/bensheldon/good_job/tree/v1.2.4) (2020-09-01)

[Full Changelog](https://github.com/bensheldon/good_job/compare/v1.2.3...v1.2.4)

**Implemented enhancements:**

- Add environment variable to mirror `cleanup\_preserved\_jobs --before-seconds-ago=SECONDS` [\#110](https://github.com/bensheldon/good_job/issues/110)
- Allow env variable config for cleanups [\#114](https://github.com/bensheldon/good_job/pull/114) ([gadimbaylisahil](https://github.com/gadimbaylisahil))

**Fixed bugs:**

- Better table name detection for Job queries [\#119](https://github.com/bensheldon/good_job/pull/119) ([gadimbaylisahil](https://github.com/gadimbaylisahil))

**Closed issues:**

- Remove unused PgLocks class [\#121](https://github.com/bensheldon/good_job/issues/121)
- Fix minor issue with CommandLine option links in README.md [\#116](https://github.com/bensheldon/good_job/issues/116)
- Unused .advisory\_lock\_details in PgLocks [\#105](https://github.com/bensheldon/good_job/issues/105)

**Merged pull requests:**

- Remove unused PgLocks class [\#120](https://github.com/bensheldon/good_job/pull/120) ([gadimbaylisahil](https://github.com/gadimbaylisahil))
- Fix readme CommandLine option links [\#115](https://github.com/bensheldon/good_job/pull/115) ([gadimbaylisahil](https://github.com/gadimbaylisahil))
- Have YARD render markdown files with GFM \(Github Flavored Markdown\) [\#113](https://github.com/bensheldon/good_job/pull/113) ([bensheldon](https://github.com/bensheldon))
- Add markdownlint to lint readme [\#109](https://github.com/bensheldon/good_job/pull/109) ([bensheldon](https://github.com/bensheldon))
- Remove unused method in PgLocks [\#107](https://github.com/bensheldon/good_job/pull/107) ([gadimbaylisahil](https://github.com/gadimbaylisahil))
- Re-organize Readme: frontload configuration, add Table of Contents  [\#106](https://github.com/bensheldon/good_job/pull/106) ([bensheldon](https://github.com/bensheldon))

## [v1.2.3](https://github.com/bensheldon/good_job/tree/v1.2.3) (2020-08-27)

[Full Changelog](https://github.com/bensheldon/good_job/compare/v1.2.2...v1.2.3)

**Closed issues:**

- requiring more dependencies in then needed [\#103](https://github.com/bensheldon/good_job/issues/103)

**Merged pull requests:**

- stop depending on all rails libs [\#104](https://github.com/bensheldon/good_job/pull/104) ([thilo](https://github.com/thilo))

## [v1.2.2](https://github.com/bensheldon/good_job/tree/v1.2.2) (2020-08-27)

[Full Changelog](https://github.com/bensheldon/good_job/compare/v1.2.1...v1.2.2)

**Implemented enhancements:**

- Run Github Action tests against Ruby 2.5, 2.6, 2.7 [\#100](https://github.com/bensheldon/good_job/issues/100)

**Fixed bugs:**

- Freezes puma on code change [\#95](https://github.com/bensheldon/good_job/issues/95)
- Ruby 2.7 keyword arguments warning [\#93](https://github.com/bensheldon/good_job/issues/93)

**Closed issues:**

- Add test for `rails g good\_job:install` [\#57](https://github.com/bensheldon/good_job/issues/57)

**Merged pull requests:**

- Use more ActiveRecord in Lockable and not connection.execute [\#102](https://github.com/bensheldon/good_job/pull/102) ([bensheldon](https://github.com/bensheldon))
- Run CI tests on Ruby 2.5, 2.6, and 2.7 [\#101](https://github.com/bensheldon/good_job/pull/101) ([arku](https://github.com/arku))
- Return to using executor.wrap around Scheduler execution task [\#99](https://github.com/bensheldon/good_job/pull/99) ([bensheldon](https://github.com/bensheldon))
- Fix Ruby 2.7 keyword arguments warning [\#98](https://github.com/bensheldon/good_job/pull/98) ([arku](https://github.com/arku))
- Remove executor/reloader for less interlocking [\#97](https://github.com/bensheldon/good_job/pull/97) ([sj26](https://github.com/sj26))
- Name the thread pools [\#96](https://github.com/bensheldon/good_job/pull/96) ([sj26](https://github.com/sj26))
- Add test for `rails g good\_job:install` [\#94](https://github.com/bensheldon/good_job/pull/94) ([arku](https://github.com/arku))

## [v1.2.1](https://github.com/bensheldon/good_job/tree/v1.2.1) (2020-08-21)

[Full Changelog](https://github.com/bensheldon/good_job/compare/v1.2.0...v1.2.1)

**Fixed bugs:**

- undefined method `thread\_mattr\_accessor' when not requiring the Sprockets Railstie [\#85](https://github.com/bensheldon/good_job/issues/85)

**Closed issues:**

- Document comparison of GoodJob with other backends [\#51](https://github.com/bensheldon/good_job/issues/51)

**Merged pull requests:**

- Explicitly require thread\_mattr\_accessor from ActiveSupport [\#86](https://github.com/bensheldon/good_job/pull/86) ([bensheldon](https://github.com/bensheldon))
- Add comparison of other backends to Readme [\#84](https://github.com/bensheldon/good_job/pull/84) ([bensheldon](https://github.com/bensheldon))

## [v1.2.0](https://github.com/bensheldon/good_job/tree/v1.2.0) (2020-08-20)

[Full Changelog](https://github.com/bensheldon/good_job/compare/v1.1.4...v1.2.0)

**Merged pull requests:**

- Document GoodJob module [\#83](https://github.com/bensheldon/good_job/pull/83) ([bensheldon](https://github.com/bensheldon))

## [v1.1.4](https://github.com/bensheldon/good_job/tree/v1.1.4) (2020-08-19)

[Full Changelog](https://github.com/bensheldon/good_job/compare/v1.1.3...v1.1.4)

**Implemented enhancements:**

- Explicitly name threads for easier debugging [\#64](https://github.com/bensheldon/good_job/issues/64)
- Investigate Listen/Notify as alternative to polling [\#54](https://github.com/bensheldon/good_job/issues/54)

**Merged pull requests:**

- Add Postgres LISTEN/NOTIFY support [\#82](https://github.com/bensheldon/good_job/pull/82) ([bensheldon](https://github.com/bensheldon))
- Allow Schedulers to filter \#create\_thread to avoid flood of queries when running async with multiple schedulers [\#81](https://github.com/bensheldon/good_job/pull/81) ([bensheldon](https://github.com/bensheldon))
- Fully name scheduler threadpools and thread names; refactor CLI STDOUT [\#80](https://github.com/bensheldon/good_job/pull/80) ([bensheldon](https://github.com/bensheldon))

## [v1.1.3](https://github.com/bensheldon/good_job/tree/v1.1.3) (2020-08-14)

[Full Changelog](https://github.com/bensheldon/good_job/compare/v1.1.2...v1.1.3)

**Fixed bugs:**

- Job exceptions not properly attached to good\_jobs record  [\#72](https://github.com/bensheldon/good_job/issues/72)

**Merged pull requests:**

- Capture errors via instrumentation from retry\_on and discard\_on [\#79](https://github.com/bensheldon/good_job/pull/79) ([bensheldon](https://github.com/bensheldon))
- Document GoodJob::Scheduler with Yard [\#78](https://github.com/bensheldon/good_job/pull/78) ([bensheldon](https://github.com/bensheldon))

## [v1.1.2](https://github.com/bensheldon/good_job/tree/v1.1.2) (2020-08-13)

[Full Changelog](https://github.com/bensheldon/good_job/compare/v1.1.1...v1.1.2)

**Implemented enhancements:**

- Allow the omission of queue names within a scheduler [\#73](https://github.com/bensheldon/good_job/issues/73)

**Merged pull requests:**

- Allow named queues to be excluded with a minus [\#77](https://github.com/bensheldon/good_job/pull/77) ([bensheldon](https://github.com/bensheldon))

## [v1.1.1](https://github.com/bensheldon/good_job/tree/v1.1.1) (2020-08-12)

[Full Changelog](https://github.com/bensheldon/good_job/compare/v1.1.0...v1.1.1)

**Implemented enhancements:**

- Allow multiple schedulers within the same process. e.g. `queues=mice:2,elephants:4` [\#45](https://github.com/bensheldon/good_job/issues/45)

**Merged pull requests:**

- Allow instantiation of multiple schedulers via --queues [\#76](https://github.com/bensheldon/good_job/pull/76) ([bensheldon](https://github.com/bensheldon))
- Extract options parsing to Configuration object [\#74](https://github.com/bensheldon/good_job/pull/74) ([bensheldon](https://github.com/bensheldon))

## [v1.1.0](https://github.com/bensheldon/good_job/tree/v1.1.0) (2020-08-10)

[Full Changelog](https://github.com/bensheldon/good_job/compare/v1.0.3...v1.1.0)

**Closed issues:**

- Document reliability guarantees [\#59](https://github.com/bensheldon/good_job/issues/59)
- Document how to hook in exception monitor \(Sentry, Rollbar, etc\) [\#47](https://github.com/bensheldon/good_job/issues/47)
- Allow an Async mode [\#27](https://github.com/bensheldon/good_job/issues/27)

**Merged pull requests:**

- Add a callable hook on thread errors [\#71](https://github.com/bensheldon/good_job/pull/71) ([bensheldon](https://github.com/bensheldon))
- Clarify reliability guarantees [\#70](https://github.com/bensheldon/good_job/pull/70) ([bensheldon](https://github.com/bensheldon))
- Clean up Readme formatting; re-arrange tests for clarity and values [\#69](https://github.com/bensheldon/good_job/pull/69) ([bensheldon](https://github.com/bensheldon))
- Create an Async execution mode [\#68](https://github.com/bensheldon/good_job/pull/68) ([bensheldon](https://github.com/bensheldon))
- Move all stdout to LogSubscriber [\#67](https://github.com/bensheldon/good_job/pull/67) ([bensheldon](https://github.com/bensheldon))
- Allow schedulers to be restarted; separate unit tests from integration tests [\#66](https://github.com/bensheldon/good_job/pull/66) ([bensheldon](https://github.com/bensheldon))

## [v1.0.3](https://github.com/bensheldon/good_job/tree/v1.0.3) (2020-07-26)

[Full Changelog](https://github.com/bensheldon/good_job/compare/v1.0.2...v1.0.3)

**Fixed bugs:**

- Preserve GoodJob::Jobs when a StandardError is raised [\#60](https://github.com/bensheldon/good_job/issues/60)

**Closed issues:**

- Have an initial setup generator [\#6](https://github.com/bensheldon/good_job/issues/6)

**Merged pull requests:**

- Re-perform a job if a StandardError bubbles up; better document job reliability [\#62](https://github.com/bensheldon/good_job/pull/62) ([bensheldon](https://github.com/bensheldon))
- Update the setup documentation to use correct bin setup command [\#61](https://github.com/bensheldon/good_job/pull/61) ([jm96441n](https://github.com/jm96441n))

## [v1.0.2](https://github.com/bensheldon/good_job/tree/v1.0.2) (2020-07-25)

[Full Changelog](https://github.com/bensheldon/good_job/compare/v1.0.1...v1.0.2)

**Fixed bugs:**

- Fix counting of available execution threads [\#58](https://github.com/bensheldon/good_job/pull/58) ([bensheldon](https://github.com/bensheldon))

**Merged pull requests:**

- Add migration generator [\#56](https://github.com/bensheldon/good_job/pull/56) ([thedanbob](https://github.com/thedanbob))
- Fix migration script in readme [\#55](https://github.com/bensheldon/good_job/pull/55) ([thedanbob](https://github.com/thedanbob))

## [v1.0.1](https://github.com/bensheldon/good_job/tree/v1.0.1) (2020-07-22)

[Full Changelog](https://github.com/bensheldon/good_job/compare/v1.0.0...v1.0.1)

**Merged pull requests:**

- Change threadpool idletime default to 60 seconds from 0 [\#49](https://github.com/bensheldon/good_job/pull/49) ([bensheldon](https://github.com/bensheldon))

## [v1.0.0](https://github.com/bensheldon/good_job/tree/v1.0.0) (2020-07-20)

[Full Changelog](https://github.com/bensheldon/good_job/compare/v0.9.0...v1.0.0)

## [v0.9.0](https://github.com/bensheldon/good_job/tree/v0.9.0) (2020-07-20)

[Full Changelog](https://github.com/bensheldon/good_job/compare/v0.8.2...v0.9.0)

**Merged pull requests:**

- Allow preservation of finished job records [\#46](https://github.com/bensheldon/good_job/pull/46) ([bensheldon](https://github.com/bensheldon))

## [v0.8.2](https://github.com/bensheldon/good_job/tree/v0.8.2) (2020-07-18)

[Full Changelog](https://github.com/bensheldon/good_job/compare/v0.8.1...v0.8.2)

**Closed issues:**

- Add a job timeout configuration to time out jobs that have run too long [\#19](https://github.com/bensheldon/good_job/issues/19)

**Merged pull requests:**

- Run Github Action tests on PRs from forks [\#44](https://github.com/bensheldon/good_job/pull/44) ([bensheldon](https://github.com/bensheldon))
- Fix Rubygems homepage URL [\#43](https://github.com/bensheldon/good_job/pull/43) ([joshmn](https://github.com/joshmn))

## [v0.8.1](https://github.com/bensheldon/good_job/tree/v0.8.1) (2020-07-18)

[Full Changelog](https://github.com/bensheldon/good_job/compare/v0.8.0...v0.8.1)

**Merged pull requests:**

- Move where\(scheduled\_at: Time.current\) into dynamic part of GoodJob::Job::Performer [\#42](https://github.com/bensheldon/good_job/pull/42) ([bensheldon](https://github.com/bensheldon))

## [v0.8.0](https://github.com/bensheldon/good_job/tree/v0.8.0) (2020-07-17)

[Full Changelog](https://github.com/bensheldon/good_job/compare/v0.7.0...v0.8.0)

**Merged pull requests:**

- Replace Adapter inline boolean kwarg with execution\_mode instead [\#41](https://github.com/bensheldon/good_job/pull/41) ([bensheldon](https://github.com/bensheldon))

## [v0.7.0](https://github.com/bensheldon/good_job/tree/v0.7.0) (2020-07-16)

[Full Changelog](https://github.com/bensheldon/good_job/compare/v0.6.0...v0.7.0)

**Closed issues:**

- Always store a default priority \(0\) and scheduled\_at\(Time.current\) [\#30](https://github.com/bensheldon/good_job/issues/30)

**Merged pull requests:**

- Add more examples to Readme [\#39](https://github.com/bensheldon/good_job/pull/39) ([bensheldon](https://github.com/bensheldon))
- Add additional Rubocops and lint [\#38](https://github.com/bensheldon/good_job/pull/38) ([bensheldon](https://github.com/bensheldon))
- Always store a default queue\_name, priority and scheduled\_at; index by queue\_name and scheduled\_at [\#37](https://github.com/bensheldon/good_job/pull/37) ([bensheldon](https://github.com/bensheldon))

## [v0.6.0](https://github.com/bensheldon/good_job/tree/v0.6.0) (2020-07-15)

[Full Changelog](https://github.com/bensheldon/good_job/compare/v0.5.0...v0.6.0)

**Closed issues:**

- Improve the command line options [\#32](https://github.com/bensheldon/good_job/issues/32)
- Allow config.active\_job.queue\_adapter = :good\_job to work [\#5](https://github.com/bensheldon/good_job/issues/5)

**Merged pull requests:**

- Improve generation of changelog [\#36](https://github.com/bensheldon/good_job/pull/36) ([bensheldon](https://github.com/bensheldon))
- Update Github Action Workflow for Backlog Project Board [\#35](https://github.com/bensheldon/good_job/pull/35) ([bensheldon](https://github.com/bensheldon))
- Add configuration options to good\_job executable [\#33](https://github.com/bensheldon/good_job/pull/33) ([bensheldon](https://github.com/bensheldon))
- Extract Job querying behavior out of Scheduler [\#31](https://github.com/bensheldon/good_job/pull/31) ([bensheldon](https://github.com/bensheldon))
- Allow configuration of Rails queue adapter with `:good\_job` [\#28](https://github.com/bensheldon/good_job/pull/28) ([bensheldon](https://github.com/bensheldon))

## [v0.5.0](https://github.com/bensheldon/good_job/tree/v0.5.0) (2020-07-13)

[Full Changelog](https://github.com/bensheldon/good_job/compare/v0.4.0...v0.5.0)

**Merged pull requests:**

- Update development Ruby to 2.6.6 and gems [\#29](https://github.com/bensheldon/good_job/pull/29) ([bensheldon](https://github.com/bensheldon))

## [v0.4.0](https://github.com/bensheldon/good_job/tree/v0.4.0) (2020-03-31)

[Full Changelog](https://github.com/bensheldon/good_job/compare/v0.3.0...v0.4.0)

**Merged pull requests:**

- Improve ActiveRecord usage for advisory locking [\#24](https://github.com/bensheldon/good_job/pull/24) ([bensheldon](https://github.com/bensheldon))
- Remove support for Rails 5.1 [\#23](https://github.com/bensheldon/good_job/pull/23) ([bensheldon](https://github.com/bensheldon))

## [v0.3.0](https://github.com/bensheldon/good_job/tree/v0.3.0) (2020-03-22)

[Full Changelog](https://github.com/bensheldon/good_job/compare/v0.2.2...v0.3.0)

**Merged pull requests:**

- Update development Ruby to 2.6.5 [\#22](https://github.com/bensheldon/good_job/pull/22) ([bensheldon](https://github.com/bensheldon))
- Simplify the internal API, removing JobWrapper and InlineScheduler [\#21](https://github.com/bensheldon/good_job/pull/21) ([bensheldon](https://github.com/bensheldon))
- Generate a new future for every executed job [\#20](https://github.com/bensheldon/good_job/pull/20) ([bensheldon](https://github.com/bensheldon))
- Configuration for maximum number of job execution threads [\#18](https://github.com/bensheldon/good_job/pull/18) ([bensheldon](https://github.com/bensheldon))

## [v0.2.2](https://github.com/bensheldon/good_job/tree/v0.2.2) (2020-03-08)

[Full Changelog](https://github.com/bensheldon/good_job/compare/v0.2.1...v0.2.2)

**Merged pull requests:**

- Gracefully shutdown Scheduler when executable receives TERM or INT [\#17](https://github.com/bensheldon/good_job/pull/17) ([bensheldon](https://github.com/bensheldon))
- Update Appraisals [\#16](https://github.com/bensheldon/good_job/pull/16) ([bensheldon](https://github.com/bensheldon))

## [v0.2.1](https://github.com/bensheldon/good_job/tree/v0.2.1) (2020-03-07)

[Full Changelog](https://github.com/bensheldon/good_job/compare/v0.2.0...v0.2.1)

**Merged pull requests:**

- Clean up Gemspec [\#15](https://github.com/bensheldon/good_job/pull/15) ([bensheldon](https://github.com/bensheldon))
- Set up Rubocop [\#14](https://github.com/bensheldon/good_job/pull/14) ([bensheldon](https://github.com/bensheldon))
- Add pg gem as explicit dependency [\#13](https://github.com/bensheldon/good_job/pull/13) ([bensheldon](https://github.com/bensheldon))
- Bump nokogiri from 1.10.7 to 1.10.9 [\#12](https://github.com/bensheldon/good_job/pull/12) ([dependabot[bot]](https://github.com/apps/dependabot))
- Add Appraisal with tests for Rails 5.1, 5.2, 6.0 [\#11](https://github.com/bensheldon/good_job/pull/11) ([bensheldon](https://github.com/bensheldon))

## [v0.2.0](https://github.com/bensheldon/good_job/tree/v0.2.0) (2020-03-06)

[Full Changelog](https://github.com/bensheldon/good_job/compare/v0.1.0...v0.2.0)

**Merged pull requests:**

- Use Rails.logger and ActiveSupport::Notifications for logging instead of puts [\#10](https://github.com/bensheldon/good_job/pull/10) ([bensheldon](https://github.com/bensheldon))
- Remove minitest files [\#9](https://github.com/bensheldon/good_job/pull/9) ([bensheldon](https://github.com/bensheldon))
- Use scheduled\_at and priority for scheduling [\#8](https://github.com/bensheldon/good_job/pull/8) ([bensheldon](https://github.com/bensheldon))
- Create Github Action workflow for PRs and Issues [\#7](https://github.com/bensheldon/good_job/pull/7) ([bensheldon](https://github.com/bensheldon))

## [v0.1.0](https://github.com/bensheldon/good_job/tree/v0.1.0) (2020-03-03)

[Full Changelog](https://github.com/bensheldon/good_job/compare/6866006239f1a6b7fcb7103f5df60d904952fb84...v0.1.0)

**Merged pull requests:**

- Add executable with Thor [\#4](https://github.com/bensheldon/good_job/pull/4) ([bensheldon](https://github.com/bensheldon))
- Refactor adapter enqueing methods; expand Readme, tests, editorconfig [\#3](https://github.com/bensheldon/good_job/pull/3) ([bensheldon](https://github.com/bensheldon))
- Fetch new jobs within the worker thread itself; incrementally grow worker threads [\#2](https://github.com/bensheldon/good_job/pull/2) ([bensheldon](https://github.com/bensheldon))
- Set up Github Workflows for tests [\#1](https://github.com/bensheldon/good_job/pull/1) ([bensheldon](https://github.com/bensheldon))



\* *This Changelog was automatically generated by [github_changelog_generator](https://github.com/github-changelog-generator/github-changelog-generator)*
