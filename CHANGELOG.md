# Changelog

## [v3.4.5](https://github.com/bensheldon/good_job/tree/v3.4.5) (2022-09-12)

[Full Changelog](https://github.com/bensheldon/good_job/compare/v3.4.4...v3.4.5)

**Fixed bugs:**

- Dashboard: Remove translation\_missing red highlighting; remove number\_to\_human.hundreds; add form labels [\#708](https://github.com/bensheldon/good_job/pull/708) ([bensheldon](https://github.com/bensheldon))

**Closed issues:**

- pg\_xact No Such File error in logs [\#709](https://github.com/bensheldon/good_job/issues/709)
- Broken upgrade to v3. [\#703](https://github.com/bensheldon/good_job/issues/703)

**Merged pull requests:**

- Sentry integration Docs [\#711](https://github.com/bensheldon/good_job/pull/711) ([remy727](https://github.com/remy727))
- Add an `Execution` `after_perform_unlocked` callback [\#706](https://github.com/bensheldon/good_job/pull/706) ([bensheldon](https://github.com/bensheldon))

## [v3.4.4](https://github.com/bensheldon/good_job/tree/v3.4.4) (2022-08-20)

[Full Changelog](https://github.com/bensheldon/good_job/compare/v3.4.3...v3.4.4)

**Fixed bugs:**

- Keep locale param when submitting dashboard filter [\#707](https://github.com/bensheldon/good_job/pull/707) ([aki77](https://github.com/aki77))

**Merged pull requests:**

- Fix document [\#704](https://github.com/bensheldon/good_job/pull/704) ([aki77](https://github.com/aki77))
- Describe pessimistic usecases [\#702](https://github.com/bensheldon/good_job/pull/702) ([shouichi](https://github.com/shouichi))

## [v3.4.3](https://github.com/bensheldon/good_job/tree/v3.4.3) (2022-08-15)

[Full Changelog](https://github.com/bensheldon/good_job/compare/v3.4.2...v3.4.3)

**Closed issues:**

- How to run multiple workers? [\#699](https://github.com/bensheldon/good_job/issues/699)
- Getting Postgres Errors on killing development server after setting up Goodjob [\#692](https://github.com/bensheldon/good_job/issues/692)

**Merged pull requests:**

- Fix Project v2 GitHub Actions [\#701](https://github.com/bensheldon/good_job/pull/701) ([bensheldon](https://github.com/bensheldon))
- Remove development dependencies: memory\_profiler, rbtrace, sigdump [\#700](https://github.com/bensheldon/good_job/pull/700) ([bensheldon](https://github.com/bensheldon))
- Allow concurrency limits to be configured dynamically with lambda/proc [\#696](https://github.com/bensheldon/good_job/pull/696) ([baka-san](https://github.com/baka-san))
- Add additional details to Concurrency Control explanation [\#695](https://github.com/bensheldon/good_job/pull/695) ([bensheldon](https://github.com/bensheldon))

## [v3.4.2](https://github.com/bensheldon/good_job/tree/v3.4.2) (2022-08-13)

[Full Changelog](https://github.com/bensheldon/good_job/compare/v3.4.1...v3.4.2)

**Fixed bugs:**

- Jobs enqueued via dashboard ignores app default\_locale [\#697](https://github.com/bensheldon/good_job/issues/697)
- Include better exception log messages, including class and backtrace [\#693](https://github.com/bensheldon/good_job/pull/693) ([bensheldon](https://github.com/bensheldon))

**Closed issues:**

- Do we need to implement concurrency with scheduled cron jobs? [\#690](https://github.com/bensheldon/good_job/issues/690)
- Uninitialized constant GoodJob::JobsController [\#674](https://github.com/bensheldon/good_job/issues/674)
- ActiveRecord::StatementInvalid: PG::ConnectionBad: PQsocket\(\) can't get socket descriptor every 30 minutes aprox. [\#579](https://github.com/bensheldon/good_job/issues/579)
- Handle assets in dashboard when rails app is behind proxy path [\#424](https://github.com/bensheldon/good_job/issues/424)

**Merged pull requests:**

- Enqueues Cron jobs with I18n default locale [\#698](https://github.com/bensheldon/good_job/pull/698) ([esasse](https://github.com/esasse))

## [v3.4.1](https://github.com/bensheldon/good_job/tree/v3.4.1) (2022-08-06)

[Full Changelog](https://github.com/bensheldon/good_job/compare/v3.4.0...v3.4.1)

**Closed issues:**

- Add `cron_enabled` to Process state [\#673](https://github.com/bensheldon/good_job/issues/673)
- Good job is using a lot of memory / ram [\#613](https://github.com/bensheldon/good_job/issues/613)

**Merged pull requests:**

- Only report Notifier connection errors once after they happen 3 consecutive times [\#689](https://github.com/bensheldon/good_job/pull/689) ([bensheldon](https://github.com/bensheldon))

## [v3.4.0](https://github.com/bensheldon/good_job/tree/v3.4.0) (2022-08-05)

[Full Changelog](https://github.com/bensheldon/good_job/compare/v3.3.3...v3.4.0)

**Implemented enhancements:**

- Add cron\_enabled attribute to good\_job and pass it to process current state [\#675](https://github.com/bensheldon/good_job/pull/675) ([saksham-jain](https://github.com/saksham-jain))
- Reverse Dashboard Filter Hierarchy to be: queues+jobs then state [\#666](https://github.com/bensheldon/good_job/pull/666) ([bensheldon](https://github.com/bensheldon))
- Allow cron entries to be temporarily disabled and re-enabled through the Dashboard [\#649](https://github.com/bensheldon/good_job/pull/649) ([alex-klepa](https://github.com/alex-klepa))
- Add Configuration.total\_estimated\_threads to report number of threads consumed by GoodJob [\#645](https://github.com/bensheldon/good_job/pull/645) ([bensheldon](https://github.com/bensheldon))

**Closed issues:**

- Cron Schedule jobs add disable action [\#540](https://github.com/bensheldon/good_job/issues/540)

**Merged pull requests:**

- Removed text that implied an existing feature had not been finished [\#688](https://github.com/bensheldon/good_job/pull/688) ([pgvsalamander](https://github.com/pgvsalamander))

## [v3.3.3](https://github.com/bensheldon/good_job/tree/v3.3.3) (2022-08-02)

[Full Changelog](https://github.com/bensheldon/good_job/compare/v3.3.2...v3.3.3)

**Fixed bugs:**

- Detect usage of `puma` CLI for async mode [\#686](https://github.com/bensheldon/good_job/pull/686) ([bensheldon](https://github.com/bensheldon))

**Closed issues:**

- Async not working Rails 7 with puma CLI [\#685](https://github.com/bensheldon/good_job/issues/685)

## [v3.3.2](https://github.com/bensheldon/good_job/tree/v3.3.2) (2022-07-27)

[Full Changelog](https://github.com/bensheldon/good_job/compare/v3.3.1...v3.3.2)

**Fixed bugs:**

- Defer setting Adapter's execution mode until Rails initializes [\#683](https://github.com/bensheldon/good_job/pull/683) ([bensheldon](https://github.com/bensheldon))

## [v3.3.1](https://github.com/bensheldon/good_job/tree/v3.3.1) (2022-07-26)

[Full Changelog](https://github.com/bensheldon/good_job/compare/v3.3.0...v3.3.1)

**Implemented enhancements:**

- Show basename of proctitle [\#679](https://github.com/bensheldon/good_job/pull/679) ([bkeepers](https://github.com/bkeepers))

**Fixed bugs:**

- Only count \_active\_ processes in the Navbar [\#680](https://github.com/bensheldon/good_job/pull/680) ([bensheldon](https://github.com/bensheldon))
- Remove Zeitwerk and use explicit requires to be more like an engine [\#677](https://github.com/bensheldon/good_job/pull/677) ([bensheldon](https://github.com/bensheldon))

**Closed issues:**

- Dashboard UI Invalid count of running process  [\#678](https://github.com/bensheldon/good_job/issues/678)

**Merged pull requests:**

- Lock to dotenv 2.7.x for Ruby 2.5 compatibility [\#682](https://github.com/bensheldon/good_job/pull/682) ([bensheldon](https://github.com/bensheldon))
- Create global GoodJob.configuration object [\#681](https://github.com/bensheldon/good_job/pull/681) ([bensheldon](https://github.com/bensheldon))

## [v3.3.0](https://github.com/bensheldon/good_job/tree/v3.3.0) (2022-07-24)

[Full Changelog](https://github.com/bensheldon/good_job/compare/v3.2.0...v3.3.0)

**Implemented enhancements:**

- Dashboard: Update cron and processes to match jobs listing [\#676](https://github.com/bensheldon/good_job/pull/676) ([bkeepers](https://github.com/bkeepers))
- Dashboard: improvements to jobs index and show pages [\#672](https://github.com/bensheldon/good_job/pull/672) ([bkeepers](https://github.com/bkeepers))

**Fixed bugs:**

- Replace "timestamp" column-type in migrations with "datetime" [\#671](https://github.com/bensheldon/good_job/pull/671) ([bensheldon](https://github.com/bensheldon))

**Closed issues:**

- Readme should consistently encourage usage of `config.good_job....` instead of `GoodJob.` configuration [\#628](https://github.com/bensheldon/good_job/issues/628)
- Improve the "Gem development" section of README? [\#551](https://github.com/bensheldon/good_job/issues/551)
- Simplify Rails initialization to only be a mountable Engine [\#543](https://github.com/bensheldon/good_job/issues/543)

**Merged pull requests:**

- Improve Readme description of v3 job preservation defaults [\#670](https://github.com/bensheldon/good_job/pull/670) ([bensheldon](https://github.com/bensheldon))
- update Gemfile.lock to latest dependencies [\#647](https://github.com/bensheldon/good_job/pull/647) ([jrochkind](https://github.com/jrochkind))

## [v3.2.0](https://github.com/bensheldon/good_job/tree/v3.2.0) (2022-07-12)

[Full Changelog](https://github.com/bensheldon/good_job/compare/v3.1.0...v3.2.0)

**Implemented enhancements:**

- Ordered queue handling by workers [\#665](https://github.com/bensheldon/good_job/pull/665) ([jrochkind](https://github.com/jrochkind))

## [v3.1.0](https://github.com/bensheldon/good_job/tree/v3.1.0) (2022-07-11)

[Full Changelog](https://github.com/bensheldon/good_job/compare/v3.0.2...v3.1.0)

**Implemented enhancements:**

- Show job/cron/process counts in the Navbar [\#663](https://github.com/bensheldon/good_job/pull/663) ([bensheldon](https://github.com/bensheldon))
- Improve Dashboard display of parameters \(CronEntry kwargs; Process configuration; Job and Execution database values\) [\#662](https://github.com/bensheldon/good_job/pull/662) ([bensheldon](https://github.com/bensheldon))
- Dequeing should be first-in first-out [\#651](https://github.com/bensheldon/good_job/pull/651) ([jrochkind](https://github.com/jrochkind))

**Fixed bugs:**

- Don't delegate `GoodJob::Job#status` to executions to avoid race condition [\#661](https://github.com/bensheldon/good_job/pull/661) ([bensheldon](https://github.com/bensheldon))

**Closed issues:**

- How to suppress repetitive logs in development? [\#658](https://github.com/bensheldon/good_job/issues/658)
- 500 Internal Server Error Exception in web interface trying to view running jobs [\#656](https://github.com/bensheldon/good_job/issues/656)
- Cron schedule page in dashboard not showing kwargs [\#608](https://github.com/bensheldon/good_job/issues/608)
- Paralelism x database connections [\#569](https://github.com/bensheldon/good_job/issues/569)

## [v3.0.2](https://github.com/bensheldon/good_job/tree/v3.0.2) (2022-07-10)

[Full Changelog](https://github.com/bensheldon/good_job/compare/v3.0.1...v3.0.2)

**Fixed bugs:**

- Copy forward concurrency key value when retrying a job, rather than regenerating it [\#622](https://github.com/bensheldon/good_job/issues/622)
- All concurrency controlled jobs throw exceptions and are rescheduled if they are called using perform\_now [\#591](https://github.com/bensheldon/good_job/issues/591)

**Closed issues:**

- Queue config not respecting limits [\#659](https://github.com/bensheldon/good_job/issues/659)
- UI engine does not work without explicit require [\#646](https://github.com/bensheldon/good_job/issues/646)
- Should `:inline` adapter mode retry jobs? [\#611](https://github.com/bensheldon/good_job/issues/611)
- Error Job Not Preserved  [\#594](https://github.com/bensheldon/good_job/issues/594)
- Jobs never get run... [\#516](https://github.com/bensheldon/good_job/issues/516)
- Release GoodJob 3.0 [\#507](https://github.com/bensheldon/good_job/issues/507)
- Improve security of Gem releases [\#422](https://github.com/bensheldon/good_job/issues/422)

**Merged pull requests:**

- Preserve initial concurrency key when retrying jobs [\#657](https://github.com/bensheldon/good_job/pull/657) ([bensheldon](https://github.com/bensheldon))
- Add Dashboard troubleshooting note to explicitly require the engine [\#654](https://github.com/bensheldon/good_job/pull/654) ([bensheldon](https://github.com/bensheldon))
- Removes wrong parentheses [\#653](https://github.com/bensheldon/good_job/pull/653) ([esasse](https://github.com/esasse))

## [v3.0.1](https://github.com/bensheldon/good_job/tree/v3.0.1) (2022-07-02)

[Full Changelog](https://github.com/bensheldon/good_job/compare/v3.0.0...v3.0.1)

**Fixed bugs:**

- Fix `GoodJob.cleanup_preserved_jobs` to use `delete_all` instead of `destroy_all` [\#652](https://github.com/bensheldon/good_job/pull/652) ([bensheldon](https://github.com/bensheldon))

**Closed issues:**

- ERROR:  relation "good\_jobs" does not exist at character 454 [\#308](https://github.com/bensheldon/good_job/issues/308)

**Merged pull requests:**

- Create codeql-analysis.yml [\#648](https://github.com/bensheldon/good_job/pull/648) ([bensheldon](https://github.com/bensheldon))

## [v3.0.0](https://github.com/bensheldon/good_job/tree/v3.0.0) (2022-06-26)

[Full Changelog](https://github.com/bensheldon/good_job/compare/v2.99.0...v3.0.0)

**Implemented enhancements:**

- By default, preserve job records and automatically them clean up [\#545](https://github.com/bensheldon/good_job/pull/545) ([bensheldon](https://github.com/bensheldon))

**Merged pull requests:**

- Update tests to reflect default of `GoodJob.preserve_job_records = true`; update appraisal Gemfiles too [\#643](https://github.com/bensheldon/good_job/pull/643) ([bensheldon](https://github.com/bensheldon))
- Remove database migration shims and old migrations [\#642](https://github.com/bensheldon/good_job/pull/642) ([bensheldon](https://github.com/bensheldon))
- Remove support for EOL Rails 5.2 [\#637](https://github.com/bensheldon/good_job/pull/637) ([bensheldon](https://github.com/bensheldon))
- Remove/rename deprecated behavior and constants for GoodJob v3  [\#633](https://github.com/bensheldon/good_job/pull/633) ([bensheldon](https://github.com/bensheldon))

## [v2.99.0](https://github.com/bensheldon/good_job/tree/v2.99.0) (2022-06-26)

[Full Changelog](https://github.com/bensheldon/good_job/compare/v2.17.1...v2.99.0)

**Closed issues:**

- How to accomplish user controlled recurring jobs? [\#640](https://github.com/bensheldon/good_job/issues/640)
- "uninitialized constant GoodJob::Execution" in development env [\#634](https://github.com/bensheldon/good_job/issues/634)

**Merged pull requests:**

- Create upgrade instructions for v2.99 -\> v3.0.0 [\#641](https://github.com/bensheldon/good_job/pull/641) ([bensheldon](https://github.com/bensheldon))
- Update development dependencies; delete Gemfile.lock in CI to avoid Ruby version dependency mismatches [\#639](https://github.com/bensheldon/good_job/pull/639) ([bensheldon](https://github.com/bensheldon))
- Put more model files in `lib/models` and align specs too [\#638](https://github.com/bensheldon/good_job/pull/638) ([bensheldon](https://github.com/bensheldon))
- Generate sha256 checksums on gem release too [\#636](https://github.com/bensheldon/good_job/pull/636) ([bensheldon](https://github.com/bensheldon))

## [v2.17.1](https://github.com/bensheldon/good_job/tree/v2.17.1) (2022-06-24)

[Full Changelog](https://github.com/bensheldon/good_job/compare/v2.17.0...v2.17.1)

**Fixed bugs:**

- Move models out of `app` into `lib/models` [\#635](https://github.com/bensheldon/good_job/pull/635) ([bensheldon](https://github.com/bensheldon))

**Closed issues:**

- dashboard "delete all" does not work [\#630](https://github.com/bensheldon/good_job/issues/630)
- Concurrency controlled jobs cause infinite loops when perform\_limit is exceeded in test environments [\#609](https://github.com/bensheldon/good_job/issues/609)

**Merged pull requests:**

- Better isolate test environment: run server integration tests on port 3009 with custom pidfile; scope advisory lock counts to test database [\#632](https://github.com/bensheldon/good_job/pull/632) ([bensheldon](https://github.com/bensheldon))

## [v2.17.0](https://github.com/bensheldon/good_job/tree/v2.17.0) (2022-06-23)

[Full Changelog](https://github.com/bensheldon/good_job/compare/v2.16.1...v2.17.0)

**Merged pull requests:**

- Remove nonexistant `engine/lib` from $LOAD\_PATH [\#629](https://github.com/bensheldon/good_job/pull/629) ([bensheldon](https://github.com/bensheldon))
- Mention in README that dashboard can't see completed jobs unless they are preserved [\#627](https://github.com/bensheldon/good_job/pull/627) ([jrochkind](https://github.com/jrochkind))
- Clarify README on default in development [\#623](https://github.com/bensheldon/good_job/pull/623) ([jrochkind](https://github.com/jrochkind))
- Convert GoodJob into a single mountable engine \(instead of a plugin plus optional engine\) [\#554](https://github.com/bensheldon/good_job/pull/554) ([bensheldon](https://github.com/bensheldon))

## [v2.16.1](https://github.com/bensheldon/good_job/tree/v2.16.1) (2022-06-18)

[Full Changelog](https://github.com/bensheldon/good_job/compare/v2.16.0...v2.16.1)

**Fixed bugs:**

- Fix `:inline` mode with future behavior to run unscheduled jobs immediately [\#620](https://github.com/bensheldon/good_job/pull/620) ([bensheldon](https://github.com/bensheldon))

**Merged pull requests:**

- Version check `Zeitwerk::Loader.new(warn_on_extra_files: false)` flag [\#619](https://github.com/bensheldon/good_job/pull/619) ([bensheldon](https://github.com/bensheldon))

## [v2.16.0](https://github.com/bensheldon/good_job/tree/v2.16.0) (2022-06-17)

[Full Changelog](https://github.com/bensheldon/good_job/compare/v2.15.2...v2.16.0)

**Implemented enhancements:**

- Allow inline executor to respect scheduled jobs; deprecate old behavior. Add `GoodJob.perform_inline` [\#615](https://github.com/bensheldon/good_job/pull/615) ([bensheldon](https://github.com/bensheldon))

**Closed issues:**

- Upgrading zeitwerk to 2.6.0 causes a warning related to good\_job [\#616](https://github.com/bensheldon/good_job/issues/616)

## [v2.15.2](https://github.com/bensheldon/good_job/tree/v2.15.2) (2022-06-17)

[Full Changelog](https://github.com/bensheldon/good_job/compare/v2.15.1...v2.15.2)

**Closed issues:**

- ActiveRecord::StatementInvalid PG::ProgramLimitExceeded:  ERROR: index row size 3296 exceeds btree version 4 maximum 2704 for index [\#612](https://github.com/bensheldon/good_job/issues/612)

**Merged pull requests:**

- Zeitwerk ignore `lib/active_job` [\#617](https://github.com/bensheldon/good_job/pull/617) ([bensheldon](https://github.com/bensheldon))

## [v2.15.1](https://github.com/bensheldon/good_job/tree/v2.15.1) (2022-05-24)

[Full Changelog](https://github.com/bensheldon/good_job/compare/v2.15.0...v2.15.1)

**Closed issues:**

- dashboard/engine – i18n: Wrong translation scope [\#605](https://github.com/bensheldon/good_job/issues/605)
- Concurrency not properly putting jobs in the queue [\#603](https://github.com/bensheldon/good_job/issues/603)
- Some dashboard actions have a routing error [\#602](https://github.com/bensheldon/good_job/issues/602)

**Merged pull requests:**

- Fix/i18n status scopes [\#607](https://github.com/bensheldon/good_job/pull/607) ([Jay-Schneider](https://github.com/Jay-Schneider))
- Make "Live Polling" ToC entry clickable [\#606](https://github.com/bensheldon/good_job/pull/606) ([aried3r](https://github.com/aried3r))
- Update readme explaining Concurrency implementation and how to integrate Dashboard with API-only Rails apps [\#604](https://github.com/bensheldon/good_job/pull/604) ([bensheldon](https://github.com/bensheldon))

## [v2.15.0](https://github.com/bensheldon/good_job/tree/v2.15.0) (2022-05-18)

[Full Changelog](https://github.com/bensheldon/good_job/compare/v2.14.4...v2.15.0)

**Implemented enhancements:**

- Remove ability to destroy individual Executions from Dashboard; rename "Toggle" to "Inspect" everywhere [\#601](https://github.com/bensheldon/good_job/pull/601) ([bensheldon](https://github.com/bensheldon))
- Adds the ability to delete jobs on the dashboard; add `cleanup_discarded_jobs` option to retain discarded jobs during cleanup [\#597](https://github.com/bensheldon/good_job/pull/597) ([TAGraves](https://github.com/TAGraves))
- Dashboard: show more details about jobs [\#575](https://github.com/bensheldon/good_job/pull/575) ([bkeepers](https://github.com/bkeepers))

**Closed issues:**

- Show status on jobs\#show page [\#547](https://github.com/bensheldon/good_job/issues/547)

**Merged pull requests:**

- Disable ActiveRecord Connection Reaper in test [\#600](https://github.com/bensheldon/good_job/pull/600) ([bensheldon](https://github.com/bensheldon))
- Update README dashboard screenshot [\#599](https://github.com/bensheldon/good_job/pull/599) ([aried3r](https://github.com/aried3r))

## [v2.14.4](https://github.com/bensheldon/good_job/tree/v2.14.4) (2022-05-15)

[Full Changelog](https://github.com/bensheldon/good_job/compare/v2.14.3...v2.14.4)

**Fixed bugs:**

- Fix Concurrency extension to not break `perform_now` [\#593](https://github.com/bensheldon/good_job/pull/593) ([bensheldon](https://github.com/bensheldon))

## [v2.14.3](https://github.com/bensheldon/good_job/tree/v2.14.3) (2022-05-13)

[Full Changelog](https://github.com/bensheldon/good_job/compare/v2.14.2...v2.14.3)

**Fixed bugs:**

- Bind probe server to all interfaces [\#598](https://github.com/bensheldon/good_job/pull/598) ([Timmitry](https://github.com/Timmitry))

**Closed issues:**

- NoMethodError: undefined method `current\_tags' for nil:NilClass  [\#596](https://github.com/bensheldon/good_job/issues/596)
- When running rspec, I get: current transaction is aborted, commands ignored until end of transaction block [\#595](https://github.com/bensheldon/good_job/issues/595)
- CLI healtheck only listening on localhost, not reachable for Kubernetes [\#592](https://github.com/bensheldon/good_job/issues/592)

**Merged pull requests:**

- Improve development instructions and tooling \(rename bin/rails, add bin/appraisal\) [\#590](https://github.com/bensheldon/good_job/pull/590) ([bensheldon](https://github.com/bensheldon))
- Replace test Instrumentation mocking with temporary subscriptions [\#589](https://github.com/bensheldon/good_job/pull/589) ([bensheldon](https://github.com/bensheldon))
- Update to development to Ruby 3.0.4, include `matrix` gem in development Gemfile [\#588](https://github.com/bensheldon/good_job/pull/588) ([bensheldon](https://github.com/bensheldon))

## [v2.14.2](https://github.com/bensheldon/good_job/tree/v2.14.2) (2022-05-01)

[Full Changelog](https://github.com/bensheldon/good_job/compare/v2.14.1...v2.14.2)

**Fixed bugs:**

- Reintroduce fixed "Apply to all" mass action [\#586](https://github.com/bensheldon/good_job/pull/586) ([bensheldon](https://github.com/bensheldon))

**Closed issues:**

- how to get the number of tasks in the queue and the size of the queue? [\#564](https://github.com/bensheldon/good_job/issues/564)
- GoodJob tells me to upgrade but migrations fail [\#544](https://github.com/bensheldon/good_job/issues/544)

**Merged pull requests:**

- Update development dependencies [\#584](https://github.com/bensheldon/good_job/pull/584) ([bensheldon](https://github.com/bensheldon))
- Refactor Dashboard Live Poll javascript [\#582](https://github.com/bensheldon/good_job/pull/582) ([bensheldon](https://github.com/bensheldon))

## [v2.14.1](https://github.com/bensheldon/good_job/tree/v2.14.1) (2022-04-26)

[Full Changelog](https://github.com/bensheldon/good_job/compare/v2.14.0...v2.14.1)

**Fixed bugs:**

- Temporarily disable Mass Action "Apply to all" because the action is badly scoped [\#583](https://github.com/bensheldon/good_job/pull/583) ([bensheldon](https://github.com/bensheldon))

## [v2.14.0](https://github.com/bensheldon/good_job/tree/v2.14.0) (2022-04-26)

[Full Changelog](https://github.com/bensheldon/good_job/compare/v2.13.2...v2.14.0)

**Implemented enhancements:**

- Add mass update operations for jobs to Dashboard [\#578](https://github.com/bensheldon/good_job/pull/578) ([bensheldon](https://github.com/bensheldon))

**Closed issues:**

- Allow "mass"-actions through Dashboard \(e.g. retry all\) [\#446](https://github.com/bensheldon/good_job/issues/446)

**Merged pull requests:**

- Track down incompatibility/race condition between JRuby and RSpec mocks in tests [\#581](https://github.com/bensheldon/good_job/pull/581) ([bensheldon](https://github.com/bensheldon))

## [v2.13.2](https://github.com/bensheldon/good_job/tree/v2.13.2) (2022-04-25)

[Full Changelog](https://github.com/bensheldon/good_job/compare/v2.13.1...v2.13.2)

**Fixed bugs:**

- Namespaces assets per Rails docs [\#580](https://github.com/bensheldon/good_job/pull/580) ([kylekthompson](https://github.com/kylekthompson))

## [v2.13.1](https://github.com/bensheldon/good_job/tree/v2.13.1) (2022-04-22)

[Full Changelog](https://github.com/bensheldon/good_job/compare/v2.13.0...v2.13.1)

**Implemented enhancements:**

- Dashboard: Use toasts to show notices and alerts [\#577](https://github.com/bensheldon/good_job/pull/577) ([bkeepers](https://github.com/bkeepers))
- Remove executions from the dashboard [\#576](https://github.com/bensheldon/good_job/pull/576) ([bkeepers](https://github.com/bkeepers))

**Fixed bugs:**

- `ActionMailer::MailDeliveryJob` executing twice [\#329](https://github.com/bensheldon/good_job/issues/329)
- Email job breaks dashboard [\#313](https://github.com/bensheldon/good_job/issues/313)

**Closed issues:**

- Possible encryption feature? [\#561](https://github.com/bensheldon/good_job/issues/561)
- Inconsistencies in configuration settings [\#380](https://github.com/bensheldon/good_job/issues/380)
- Lockable should accept an explicit keys on class methods too [\#341](https://github.com/bensheldon/good_job/issues/341)
- Run Scheduler\#cache\_warm on global thread pool instead of Scheduler's thread pool [\#286](https://github.com/bensheldon/good_job/issues/286)

**Merged pull requests:**

- Use javascript importmaps for Dashboard [\#574](https://github.com/bensheldon/good_job/pull/574) ([bensheldon](https://github.com/bensheldon))

## [v2.13.0](https://github.com/bensheldon/good_job/tree/v2.13.0) (2022-04-19)

[Full Changelog](https://github.com/bensheldon/good_job/compare/v2.12.2...v2.13.0)

**Implemented enhancements:**

- Dashboard UI updates: sticky navbar, statuses as tabs [\#572](https://github.com/bensheldon/good_job/pull/572) ([bkeepers](https://github.com/bkeepers))

**Closed issues:**

- Internationalize/I18n the Dashboard Engine [\#408](https://github.com/bensheldon/good_job/issues/408)

**Merged pull requests:**

- Fix Russian translation linting [\#573](https://github.com/bensheldon/good_job/pull/573) ([bensheldon](https://github.com/bensheldon))

## [v2.12.2](https://github.com/bensheldon/good_job/tree/v2.12.2) (2022-04-18)

[Full Changelog](https://github.com/bensheldon/good_job/compare/v2.12.1...v2.12.2)

**Fixed bugs:**

- Un-deprecate Adapter's `execution_mode` argument [\#567](https://github.com/bensheldon/good_job/pull/567) ([bensheldon](https://github.com/bensheldon))

**Merged pull requests:**

- Dashboard: added NL translations [\#568](https://github.com/bensheldon/good_job/pull/568) ([eelcoj](https://github.com/eelcoj))

## [v2.12.1](https://github.com/bensheldon/good_job/tree/v2.12.1) (2022-04-18)

[Full Changelog](https://github.com/bensheldon/good_job/compare/v2.12.0...v2.12.1)

**Implemented enhancements:**

- Dashboard: adding Russian translation [\#565](https://github.com/bensheldon/good_job/pull/565) ([skatkov](https://github.com/skatkov))

**Fixed bugs:**

- I18n::InvalidLocale \(:en is not a valid locale\): [\#549](https://github.com/bensheldon/good_job/issues/549)
- FIX: make 'default\_url\_options' method private [\#562](https://github.com/bensheldon/good_job/pull/562) ([friendlyantz](https://github.com/friendlyantz))

**Closed issues:**

- Exponential backoff by default? [\#563](https://github.com/bensheldon/good_job/issues/563)
- Finished without Error [\#552](https://github.com/bensheldon/good_job/issues/552)
- Track processes in the database [\#421](https://github.com/bensheldon/good_job/issues/421)

**Merged pull requests:**

- Remove WIP comments from dashboard [\#566](https://github.com/bensheldon/good_job/pull/566) ([bkeepers](https://github.com/bkeepers))
- Add i18n-tasks to linter, add binstub and move config to project root [\#559](https://github.com/bensheldon/good_job/pull/559) ([bensheldon](https://github.com/bensheldon))

## [v2.12.0](https://github.com/bensheldon/good_job/tree/v2.12.0) (2022-04-05)

[Full Changelog](https://github.com/bensheldon/good_job/compare/v2.11.3...v2.12.0)

**Closed issues:**

- TimeTask timeouts are now ignored as these were not able to be implemented correctly [\#555](https://github.com/bensheldon/good_job/issues/555)
- undefined method `relative\_time' when include\_all\_helpers is false [\#550](https://github.com/bensheldon/good_job/issues/550)
- ArgumentError: wrong number of arguments \(given 1, expected 0; required keyword: schedule\) - cron [\#546](https://github.com/bensheldon/good_job/issues/546)

**Merged pull requests:**

- Deprecate Adapter configuration of job execution/cron [\#558](https://github.com/bensheldon/good_job/pull/558) ([bensheldon](https://github.com/bensheldon))
- Remove usage of Concurrent::TimerTask's timeout\_interval [\#557](https://github.com/bensheldon/good_job/pull/557) ([bensheldon](https://github.com/bensheldon))
- Include locale in html lang attribute [\#556](https://github.com/bensheldon/good_job/pull/556) ([bensheldon](https://github.com/bensheldon))
- Rename `GoodJob::BaseController` to `GoodJob::ApplicationController` [\#553](https://github.com/bensheldon/good_job/pull/553) ([shouichi](https://github.com/shouichi))
- Internationalize/I18n the Dashboard Engine [\#497](https://github.com/bensheldon/good_job/pull/497) ([JuanVqz](https://github.com/JuanVqz))

## [v2.11.3](https://github.com/bensheldon/good_job/tree/v2.11.3) (2022-03-30)

[Full Changelog](https://github.com/bensheldon/good_job/compare/v2.11.2...v2.11.3)

**Fixed bugs:**

- Add explicit `kwargs:` key to cron configuration [\#548](https://github.com/bensheldon/good_job/pull/548) ([bensheldon](https://github.com/bensheldon))

**Closed issues:**

- How to run clean up preserved jobs in cron? [\#541](https://github.com/bensheldon/good_job/issues/541)
- Erroring with "Too many open files" when good\_job tries reconnecting to database [\#530](https://github.com/bensheldon/good_job/issues/530)
- Can't cast Array [\#529](https://github.com/bensheldon/good_job/issues/529)

**Merged pull requests:**

- Use bundle add instead [\#542](https://github.com/bensheldon/good_job/pull/542) ([glaucocustodio](https://github.com/glaucocustodio))
- Update Readme to better explain queues, pools, threads, and database connections; update CLI to frontload queue option [\#539](https://github.com/bensheldon/good_job/pull/539) ([bensheldon](https://github.com/bensheldon))

## [v2.11.2](https://github.com/bensheldon/good_job/tree/v2.11.2) (2022-03-03)

[Full Changelog](https://github.com/bensheldon/good_job/compare/v2.11.1...v2.11.2)

**Closed issues:**

- Best practices in deploying and monitoring a queue [\#523](https://github.com/bensheldon/good_job/issues/523)

**Merged pull requests:**

- Wrap Rspec before and example blocks with a mutex for JRuby [\#537](https://github.com/bensheldon/good_job/pull/537) ([bensheldon](https://github.com/bensheldon))
- Delegate `ActiveJobJob.table_name` to `Execution` and prevent it from being directly assignable [\#536](https://github.com/bensheldon/good_job/pull/536) ([bensheldon](https://github.com/bensheldon))
- Enable DB table names customization [\#535](https://github.com/bensheldon/good_job/pull/535) ([dimvic](https://github.com/dimvic))
- Added a chapter on how to prepare for production. [\#525](https://github.com/bensheldon/good_job/pull/525) ([stas](https://github.com/stas))

## [v2.11.1](https://github.com/bensheldon/good_job/tree/v2.11.1) (2022-03-01)

[Full Changelog](https://github.com/bensheldon/good_job/compare/v2.11.0...v2.11.1)

**Fixed bugs:**

- Ensure sticky footer doesn't overlap paginater; fix polling interval to 30 seconds, not ms [\#534](https://github.com/bensheldon/good_job/pull/534) ([bensheldon](https://github.com/bensheldon))

**Closed issues:**

- Pagination buttons hidden behind footer [\#533](https://github.com/bensheldon/good_job/issues/533)

## [v2.11.0](https://github.com/bensheldon/good_job/tree/v2.11.0) (2022-02-27)

[Full Changelog](https://github.com/bensheldon/good_job/compare/v2.10.0...v2.11.0)

**Implemented enhancements:**

- Add support for live polling the dashboard [\#528](https://github.com/bensheldon/good_job/pull/528) ([danielwestendorf](https://github.com/danielwestendorf))

**Closed issues:**

- How do I ensure that a the same job can't run twice? \(unique job / avoid duplicates\) [\#531](https://github.com/bensheldon/good_job/issues/531)
- Bulk reschedule and discard jobs via dashboard [\#527](https://github.com/bensheldon/good_job/issues/527)
- "Live Poll" dashboard [\#526](https://github.com/bensheldon/good_job/issues/526)

## [v2.10.0](https://github.com/bensheldon/good_job/tree/v2.10.0) (2022-02-18)

[Full Changelog](https://github.com/bensheldon/good_job/compare/v2.9.6...v2.10.0)

**Implemented enhancements:**

- Dashboard: update search filters and some small UI updates [\#518](https://github.com/bensheldon/good_job/pull/518) ([multiplegeorges](https://github.com/multiplegeorges))

**Closed issues:**

- Cron jobs not getting run [\#519](https://github.com/bensheldon/good_job/issues/519)
- Slow queries with many finished entries and concurrency control [\#514](https://github.com/bensheldon/good_job/issues/514)
- Make default retry behaviour safer [\#505](https://github.com/bensheldon/good_job/issues/505)

**Merged pull requests:**

- Fix Benchmark job throughput script   [\#522](https://github.com/bensheldon/good_job/pull/522) ([douglara](https://github.com/douglara))
- Update development Gemfile.lock [\#521](https://github.com/bensheldon/good_job/pull/521) ([bensheldon](https://github.com/bensheldon))
- Ensure Rails 6.0 is tested against Ruby 3.0; use Ruby 3.0 in demo environment [\#520](https://github.com/bensheldon/good_job/pull/520) ([bensheldon](https://github.com/bensheldon))
- Document safer setting for retry\_on\_unhandled\_error [\#517](https://github.com/bensheldon/good_job/pull/517) ([tamaloa](https://github.com/tamaloa))

## [v2.9.6](https://github.com/bensheldon/good_job/tree/v2.9.6) (2022-02-07)

[Full Changelog](https://github.com/bensheldon/good_job/compare/v2.9.5...v2.9.6)

**Merged pull requests:**

- Limit query for allowed concurrent jobs to unfinished [\#515](https://github.com/bensheldon/good_job/pull/515) ([til](https://github.com/til))

## [v2.9.5](https://github.com/bensheldon/good_job/tree/v2.9.5) (2022-02-07)

[Full Changelog](https://github.com/bensheldon/good_job/compare/v2.9.4...v2.9.5)

**Fixed bugs:**

- Transactions in "aborting" threads do not commit; causes GoodJob::Process record not destroyed on exit [\#489](https://github.com/bensheldon/good_job/issues/489)
- Deserialize ActiveJob arguments when manually retrying a job [\#513](https://github.com/bensheldon/good_job/pull/513) ([bensheldon](https://github.com/bensheldon))

**Closed issues:**

- Concurrency key proc is missing `arguments` when retrying a discarded job. [\#512](https://github.com/bensheldon/good_job/issues/512)
- Cron Schedule not visible in dashboard [\#496](https://github.com/bensheldon/good_job/issues/496)

**Merged pull requests:**

- Rename methods to `advisory_lock_key` and allow it to take a block instead of `with_advisory_lock` [\#511](https://github.com/bensheldon/good_job/pull/511) ([bensheldon](https://github.com/bensheldon))
- README: Limiting concurrency - fetch symbol instead of string [\#510](https://github.com/bensheldon/good_job/pull/510) ([BenSto](https://github.com/BenSto))
- Add arbitrary lock on class level too [\#499](https://github.com/bensheldon/good_job/pull/499) ([pandwoter](https://github.com/pandwoter))

## [v2.9.4](https://github.com/bensheldon/good_job/tree/v2.9.4) (2022-01-31)

[Full Changelog](https://github.com/bensheldon/good_job/compare/v2.9.3...v2.9.4)

**Fixed bugs:**

- Fix navbar toggler [\#506](https://github.com/bensheldon/good_job/pull/506) ([JuanVqz](https://github.com/JuanVqz))
- Guard LogSubscriber against tagged logger without a formatter [\#504](https://github.com/bensheldon/good_job/pull/504) ([bensheldon](https://github.com/bensheldon))
- Markdown lint fixes + Added missing responsive meta tag  [\#492](https://github.com/bensheldon/good_job/pull/492) ([zeevy](https://github.com/zeevy))

**Closed issues:**

- The navbar icon doesn't show the navbar menu when clicking it [\#503](https://github.com/bensheldon/good_job/issues/503)
- Not all loggers have a formatter [\#502](https://github.com/bensheldon/good_job/issues/502)
- Error logs from failed jobs used all storage space [\#495](https://github.com/bensheldon/good_job/issues/495)

**Merged pull requests:**

- Update Code of Conduct to Contributor Covenant 2.1 [\#501](https://github.com/bensheldon/good_job/pull/501) ([bensheldon](https://github.com/bensheldon))
- Test with Ruby 3.1 [\#498](https://github.com/bensheldon/good_job/pull/498) ([aried3r](https://github.com/aried3r))

## [v2.9.3](https://github.com/bensheldon/good_job/tree/v2.9.3) (2022-01-23)

[Full Changelog](https://github.com/bensheldon/good_job/compare/v2.9.2...v2.9.3)

**Fixed bugs:**

- Use `*_url` route helpers for Dashboard assets to avoid being overridden by `config.asset_host` [\#493](https://github.com/bensheldon/good_job/pull/493) ([bensheldon](https://github.com/bensheldon))

**Closed issues:**

- Assets not loaded when Rails is configured with a different hostname for assets [\#491](https://github.com/bensheldon/good_job/issues/491)

## [v2.9.2](https://github.com/bensheldon/good_job/tree/v2.9.2) (2022-01-19)

[Full Changelog](https://github.com/bensheldon/good_job/compare/v2.9.1...v2.9.2)

**Fixed bugs:**

- Error on GJ admin UI search form [\#487](https://github.com/bensheldon/good_job/issues/487)
- Use `websearch_to_tsquery` or \(`plainto_tsquery` for Postgres \< v11\) for Dashboard search filter [\#488](https://github.com/bensheldon/good_job/pull/488) ([bensheldon](https://github.com/bensheldon))

**Merged pull requests:**

- Update README to illustrate using named arguments for the unique key. [\#486](https://github.com/bensheldon/good_job/pull/486) ([phallstrom](https://github.com/phallstrom))
- Add details about exactly where to require the engine. [\#485](https://github.com/bensheldon/good_job/pull/485) ([phallstrom](https://github.com/phallstrom))
- $ symbol gets copied when clicking on the copy button [\#484](https://github.com/bensheldon/good_job/pull/484) ([zeevy](https://github.com/zeevy))

## [v2.9.1](https://github.com/bensheldon/good_job/tree/v2.9.1) (2022-01-13)

[Full Changelog](https://github.com/bensheldon/good_job/compare/v2.9.0...v2.9.1)

**Fixed bugs:**

- Start async adapters once `ActiveRecord` and `ActiveJob` have loaded, potentially before `Rails.application.initialized?` [\#483](https://github.com/bensheldon/good_job/pull/483) ([bensheldon](https://github.com/bensheldon))

**Closed issues:**

- Graceful fallback to polling when LISTEN/NOTIFY isn't available [\#482](https://github.com/bensheldon/good_job/issues/482)
- Long running locks on latest good job [\#480](https://github.com/bensheldon/good_job/issues/480)

## [v2.9.0](https://github.com/bensheldon/good_job/tree/v2.9.0) (2022-01-09)

[Full Changelog](https://github.com/bensheldon/good_job/compare/v2.8.1...v2.9.0)

**Implemented enhancements:**

- Add JRuby / JDBC support for LISTEN  [\#479](https://github.com/bensheldon/good_job/pull/479) ([bensheldon](https://github.com/bensheldon))

**Merged pull requests:**

- Remove demo CleanupJob in favor of using built-in cleanup intervals [\#478](https://github.com/bensheldon/good_job/pull/478) ([bensheldon](https://github.com/bensheldon))

## [v2.8.1](https://github.com/bensheldon/good_job/tree/v2.8.1) (2022-01-03)

[Full Changelog](https://github.com/bensheldon/good_job/compare/v2.8.0...v2.8.1)

**Implemented enhancements:**

- Add indexes to `good_jobs.finished_at` and have `GoodJob.cleanup_preserved_jobs` delete all executions for a given job [\#477](https://github.com/bensheldon/good_job/pull/477) ([bensheldon](https://github.com/bensheldon))

**Closed issues:**

- finished\_at should be indexed and clean up should clean up all of a job's executions [\#476](https://github.com/bensheldon/good_job/issues/476)

**Merged pull requests:**

- Update development Ruby \(2.7.5\) and Rails \(6.1.4.4\) versions [\#475](https://github.com/bensheldon/good_job/pull/475) ([bensheldon](https://github.com/bensheldon))
- Clean up server integration tests [\#474](https://github.com/bensheldon/good_job/pull/474) ([bensheldon](https://github.com/bensheldon))

## [v2.8.0](https://github.com/bensheldon/good_job/tree/v2.8.0) (2021-12-31)

[Full Changelog](https://github.com/bensheldon/good_job/compare/v2.7.4...v2.8.0)

**Implemented enhancements:**

- GoodJob should automatically clean up after itself and delete old job records [\#412](https://github.com/bensheldon/good_job/issues/412)
- Track processes in the database and on the Dashboard [\#472](https://github.com/bensheldon/good_job/pull/472) ([bensheldon](https://github.com/bensheldon))
- Allow Scheduler to automatically clean up preserved jobs every N jobs or seconds [\#465](https://github.com/bensheldon/good_job/pull/465) ([bensheldon](https://github.com/bensheldon))

**Closed issues:**

- Is there a way to show how many worker/process is running currently [\#471](https://github.com/bensheldon/good_job/issues/471)
- Jobs stuck in the unfinished state [\#448](https://github.com/bensheldon/good_job/issues/448)

**Merged pull requests:**

- Doublequote Ruby 3.0 in testing matrix [\#473](https://github.com/bensheldon/good_job/pull/473) ([bensheldon](https://github.com/bensheldon))
- Have demo CleanupJob use GoodJob.cleanup\_preserved\_jobs [\#470](https://github.com/bensheldon/good_job/pull/470) ([bensheldon](https://github.com/bensheldon))
- Test with Rails 7.0.0 [\#469](https://github.com/bensheldon/good_job/pull/469) ([aried3r](https://github.com/aried3r))

## [v2.7.4](https://github.com/bensheldon/good_job/tree/v2.7.4) (2021-12-16)

[Full Changelog](https://github.com/bensheldon/good_job/compare/v2.7.3...v2.7.4)

**Fixed bugs:**

- Add nonce: true to javascript\_include\_tag in dashboard [\#468](https://github.com/bensheldon/good_job/pull/468) ([bouk](https://github.com/bouk))

**Closed issues:**

- Add nonce: true to engine views  [\#467](https://github.com/bensheldon/good_job/issues/467)
- Updating good\_job breaks my Rails 7 alpha 2 local development [\#462](https://github.com/bensheldon/good_job/issues/462)

**Merged pull requests:**

- Update appraisal for Rails 7.0.0.rc1 [\#466](https://github.com/bensheldon/good_job/pull/466) ([bensheldon](https://github.com/bensheldon))

## [v2.7.3](https://github.com/bensheldon/good_job/tree/v2.7.3) (2021-11-30)

[Full Changelog](https://github.com/bensheldon/good_job/compare/v2.7.2...v2.7.3)

**Fixed bugs:**

- Logger error on 2.7.2 [\#463](https://github.com/bensheldon/good_job/issues/463)
- Fix Railtie configuration assignment when Rails configuration is a Hash, not an OrderedOptions [\#464](https://github.com/bensheldon/good_job/pull/464) ([bensheldon](https://github.com/bensheldon))

## [v2.7.2](https://github.com/bensheldon/good_job/tree/v2.7.2) (2021-11-29)

[Full Changelog](https://github.com/bensheldon/good_job/compare/v2.7.1...v2.7.2)

**Implemented enhancements:**

- Allow GoodJob global configuration accessors to also be set via Rails config hash [\#460](https://github.com/bensheldon/good_job/pull/460) ([bensheldon](https://github.com/bensheldon))

**Merged pull requests:**

- Use `ActiveRecord::Relation::QueryAttribute` when setting up bindings for `exec_query` [\#461](https://github.com/bensheldon/good_job/pull/461) ([bensheldon](https://github.com/bensheldon))
- Configure RSpec `config.example_status_persistence_file_path` [\#459](https://github.com/bensheldon/good_job/pull/459) ([bensheldon](https://github.com/bensheldon))
- Defer async initialization until Rails fully initialized [\#454](https://github.com/bensheldon/good_job/pull/454) ([bensheldon](https://github.com/bensheldon))

## [v2.7.1](https://github.com/bensheldon/good_job/tree/v2.7.1) (2021-11-26)

[Full Changelog](https://github.com/bensheldon/good_job/compare/v2.7.0...v2.7.1)

**Fixed bugs:**

- Unclear error when database can't be reached [\#457](https://github.com/bensheldon/good_job/issues/457)
- Remove Concurrent::Delay wrapping of database-loading methods [\#458](https://github.com/bensheldon/good_job/pull/458) ([bensheldon](https://github.com/bensheldon))
- Do not delete csp policies when checking csp policies [\#456](https://github.com/bensheldon/good_job/pull/456) ([JonathanFrias](https://github.com/JonathanFrias))

**Closed issues:**

- How to suppress job scheduler logs? [\#455](https://github.com/bensheldon/good_job/issues/455)
- Configuration in environments/\*.rb overrides application.rb [\#453](https://github.com/bensheldon/good_job/issues/453)
- Testing jobs synchronously [\#435](https://github.com/bensheldon/good_job/issues/435)
- HTTP health check endpoint [\#403](https://github.com/bensheldon/good_job/issues/403)

## [v2.7.0](https://github.com/bensheldon/good_job/tree/v2.7.0) (2021-11-10)

[Full Changelog](https://github.com/bensheldon/good_job/compare/v2.6.2...v2.7.0)

**Implemented enhancements:**

- Add http probe for CLI healthcheck/readiness/liveliness [\#452](https://github.com/bensheldon/good_job/pull/452) ([bensheldon](https://github.com/bensheldon))
- Add explicit Content Security Policy \(CSP\) for Dashboard [\#449](https://github.com/bensheldon/good_job/pull/449) ([bensheldon](https://github.com/bensheldon))

**Closed issues:**

- Add a default Content-Security-Policy for the Dashboard [\#420](https://github.com/bensheldon/good_job/issues/420)

## [v2.6.2](https://github.com/bensheldon/good_job/tree/v2.6.2) (2021-11-05)

[Full Changelog](https://github.com/bensheldon/good_job/compare/v2.6.1...v2.6.2)

**Fixed bugs:**

- Rename Filterable\#search to Filterable\#search\_text to avoid name collision [\#451](https://github.com/bensheldon/good_job/pull/451) ([bensheldon](https://github.com/bensheldon))

**Closed issues:**

- v2.6.1 is incompatible with gem thinking-sphinx [\#450](https://github.com/bensheldon/good_job/issues/450)

## [v2.6.1](https://github.com/bensheldon/good_job/tree/v2.6.1) (2021-11-05)

[Full Changelog](https://github.com/bensheldon/good_job/compare/v2.6.0...v2.6.1)

**Implemented enhancements:**

- Allow job management \(retry, destroy\) through the Web UI [\#256](https://github.com/bensheldon/good_job/issues/256)
- Add fulltext search filter [\#440](https://github.com/bensheldon/good_job/pull/440) ([bensheldon](https://github.com/bensheldon))

**Fixed bugs:**

- Unsubscribed LISTEN forever after database connection lost [\#303](https://github.com/bensheldon/good_job/issues/303)
- Add `PG::UnableToSend` and `PG::Error` as a Notifier connection error [\#445](https://github.com/bensheldon/good_job/pull/445) ([bensheldon](https://github.com/bensheldon))

**Closed issues:**

- Question: what's the correct way to handle database connection pool size when using cron [\#443](https://github.com/bensheldon/good_job/issues/443)
- Add a search bar to Dashboard [\#432](https://github.com/bensheldon/good_job/issues/432)
- Hacktoberfest 2021 [\#393](https://github.com/bensheldon/good_job/issues/393)
- Ideas for improvements to Cron [\#392](https://github.com/bensheldon/good_job/issues/392)
- Fix flakey test that times out [\#382](https://github.com/bensheldon/good_job/issues/382)

**Merged pull requests:**

- Update development dependencies [\#447](https://github.com/bensheldon/good_job/pull/447) ([bensheldon](https://github.com/bensheldon))
- Replace Chartist.js with Chart.js [\#444](https://github.com/bensheldon/good_job/pull/444) ([bensheldon](https://github.com/bensheldon))
- Fix JRuby flake: "Scheduler\#create\_thread returns false if there are no threads available" [\#442](https://github.com/bensheldon/good_job/pull/442) ([bensheldon](https://github.com/bensheldon))

## [v2.6.0](https://github.com/bensheldon/good_job/tree/v2.6.0) (2021-10-30)

[Full Changelog](https://github.com/bensheldon/good_job/compare/v2.5.0...v2.6.0)

**Implemented enhancements:**

- Allow for cron schedules to be expressed using fugit natural language parsing [\#441](https://github.com/bensheldon/good_job/pull/441) ([jgrau](https://github.com/jgrau))
- Add Rails UJS javascript to Dashboard along with confirmations [\#437](https://github.com/bensheldon/good_job/pull/437) ([bensheldon](https://github.com/bensheldon))
- Reorganize Cron dashboard screen; add jobs drill-drown and enqueue-now action [\#436](https://github.com/bensheldon/good_job/pull/436) ([bensheldon](https://github.com/bensheldon))

**Closed issues:**

- Ability to express cron schedule using fugit natural language parser [\#439](https://github.com/bensheldon/good_job/issues/439)
- Best way to ensure ordering of a queue. [\#402](https://github.com/bensheldon/good_job/issues/402)
- ActiveJob concurrency raises FrozenError [\#386](https://github.com/bensheldon/good_job/issues/386)

## [v2.5.0](https://github.com/bensheldon/good_job/tree/v2.5.0) (2021-10-25)

[Full Changelog](https://github.com/bensheldon/good_job/compare/v2.4.2...v2.5.0)

**Implemented enhancements:**

- Add Reschedule, Discard, Retry Job buttons to Dashboard [\#425](https://github.com/bensheldon/good_job/pull/425) ([bensheldon](https://github.com/bensheldon))
- Use unique index on \[cron\_key, cron\_at\] columns to prevent duplicate cron jobs from being enqueued [\#423](https://github.com/bensheldon/good_job/pull/423) ([bensheldon](https://github.com/bensheldon))

**Fixed bugs:**

- Dashboard fix preservation of `limit` and `queue_name` filter params; add pager to jobs [\#434](https://github.com/bensheldon/good_job/pull/434) ([bensheldon](https://github.com/bensheldon))

**Closed issues:**

- PgLock state inspection is not isolated to current database  [\#431](https://github.com/bensheldon/good_job/issues/431)
- Race condition with concurency control [\#378](https://github.com/bensheldon/good_job/issues/378)

**Merged pull requests:**

- Add Readme note about race conditions in Concurrency's `enqueue\_limit` and `perform\_limit [\#433](https://github.com/bensheldon/good_job/pull/433) ([bensheldon](https://github.com/bensheldon))
- Test harness should only force-unlock db connections for the current database [\#430](https://github.com/bensheldon/good_job/pull/430) ([bensheldon](https://github.com/bensheldon))

## [v2.4.2](https://github.com/bensheldon/good_job/tree/v2.4.2) (2021-10-19)

[Full Changelog](https://github.com/bensheldon/good_job/compare/v2.4.1...v2.4.2)

**Implemented enhancements:**

- Add migration version to install/update generator templates [\#426](https://github.com/bensheldon/good_job/pull/426) ([bensheldon](https://github.com/bensheldon))

**Fixed bugs:**

- Explicitly unscope queries within block yielded to Lockable.within\_advisory\_lock [\#429](https://github.com/bensheldon/good_job/pull/429) ([bensheldon](https://github.com/bensheldon))
- Fix Demo CleanupJob args [\#427](https://github.com/bensheldon/good_job/pull/427) ([bensheldon](https://github.com/bensheldon))

**Merged pull requests:**

- Remove v1.99/v2 transitional extra advisory lock [\#428](https://github.com/bensheldon/good_job/pull/428) ([bensheldon](https://github.com/bensheldon))

## [v2.4.1](https://github.com/bensheldon/good_job/tree/v2.4.1) (2021-10-11)

[Full Changelog](https://github.com/bensheldon/good_job/compare/v2.4.0...v2.4.1)

**Implemented enhancements:**

- Support Datadog APM / `dd-trace-rb` [\#323](https://github.com/bensheldon/good_job/issues/323)
- Display info about used timezone. [\#398](https://github.com/bensheldon/good_job/pull/398) ([morgoth](https://github.com/morgoth))
- Display cron schedules args in dashboard [\#396](https://github.com/bensheldon/good_job/pull/396) ([aried3r](https://github.com/aried3r))

**Fixed bugs:**

- Inline adapter should raise unhandled exceptions during execution [\#416](https://github.com/bensheldon/good_job/pull/416) ([bensheldon](https://github.com/bensheldon))
- Enforce english locale in UI [\#407](https://github.com/bensheldon/good_job/pull/407) ([morgoth](https://github.com/morgoth))

**Closed issues:**

- Finished jobs don't show up as finished [\#415](https://github.com/bensheldon/good_job/issues/415)
- Inline adapter should raise unhandled exceptions during execution [\#410](https://github.com/bensheldon/good_job/issues/410)
- Rewrite Scheduler "worker" thread name to be `thread` [\#406](https://github.com/bensheldon/good_job/issues/406)
- "WARNING: you don't own a lock of type ExclusiveLock" in Development [\#388](https://github.com/bensheldon/good_job/issues/388)
- Improve Readme's "Optimize queues, threads, processes" section [\#132](https://github.com/bensheldon/good_job/issues/132)

**Merged pull requests:**

- Ignore Rails HEAD Appraisal until `rails new` fixed [\#419](https://github.com/bensheldon/good_job/pull/419) ([bensheldon](https://github.com/bensheldon))
- Warn in Readme that configuration should not go into `config/initializers/*.rb` [\#418](https://github.com/bensheldon/good_job/pull/418) ([bensheldon](https://github.com/bensheldon))
- Replace worker wording [\#409](https://github.com/bensheldon/good_job/pull/409) ([Hugo-Hache](https://github.com/Hugo-Hache))
- Improve Readme's "Optimize queues, threads, processes" section [\#405](https://github.com/bensheldon/good_job/pull/405) ([Hugo-Hache](https://github.com/Hugo-Hache))
- Update GH Test Matrix with more PG versions [\#401](https://github.com/bensheldon/good_job/pull/401) ([tedhexaflow](https://github.com/tedhexaflow))
- Extract cron configuration hash into CronEntry ActiveModel objects [\#400](https://github.com/bensheldon/good_job/pull/400) ([bensheldon](https://github.com/bensheldon))
- Remove errant copy-paste from app.json [\#397](https://github.com/bensheldon/good_job/pull/397) ([morgoth](https://github.com/morgoth))

## [v2.4.0](https://github.com/bensheldon/good_job/tree/v2.4.0) (2021-10-02)

[Full Changelog](https://github.com/bensheldon/good_job/compare/v2.3.1...v2.4.0)

**Implemented enhancements:**

- Display schedule time relative to now. [\#394](https://github.com/bensheldon/good_job/pull/394) ([morgoth](https://github.com/morgoth))
- Display cron schedules properties in dashboard [\#391](https://github.com/bensheldon/good_job/pull/391) ([aried3r](https://github.com/aried3r))

**Fixed bugs:**

- Correct icon for alert flash [\#395](https://github.com/bensheldon/good_job/pull/395) ([morgoth](https://github.com/morgoth))

## [v2.3.1](https://github.com/bensheldon/good_job/tree/v2.3.1) (2021-09-30)

[Full Changelog](https://github.com/bensheldon/good_job/compare/v2.3.0...v2.3.1)

**Fixed bugs:**

- Wrap Scheduler task execution with Rails `reloader` instead of `executor` to avoid database connection changing during code reload [\#389](https://github.com/bensheldon/good_job/pull/389) ([bensheldon](https://github.com/bensheldon))

**Merged pull requests:**

- Log Cleanup thread tests, introduce "Slow" ExampleJob type, refactor ExampleJob types, run cron and log Postgres warnings in GoodJob Development harness [\#390](https://github.com/bensheldon/good_job/pull/390) ([bensheldon](https://github.com/bensheldon))

## [v2.3.0](https://github.com/bensheldon/good_job/tree/v2.3.0) (2021-09-25)

[Full Changelog](https://github.com/bensheldon/good_job/compare/v2.2.0...v2.3.0)

**Implemented enhancements:**

- Create an ActiveJobJob model and Dashboard [\#383](https://github.com/bensheldon/good_job/pull/383) ([bensheldon](https://github.com/bensheldon))
- Preserve page filter when deleting execution [\#381](https://github.com/bensheldon/good_job/pull/381) ([morgoth](https://github.com/morgoth))

**Merged pull requests:**

- Update GH Test Matrix with latest JRuby 9.3.0.0 [\#387](https://github.com/bensheldon/good_job/pull/387) ([tedhexaflow](https://github.com/tedhexaflow))
- Improve test support's ShellOut command's process termination and add test logs [\#385](https://github.com/bensheldon/good_job/pull/385) ([bensheldon](https://github.com/bensheldon))
- @bensheldon Add Rails 7 alpha to Appraisal; update development dependencies [\#384](https://github.com/bensheldon/good_job/pull/384) ([bensheldon](https://github.com/bensheldon))

## [v2.2.0](https://github.com/bensheldon/good_job/tree/v2.2.0) (2021-09-15)

[Full Changelog](https://github.com/bensheldon/good_job/compare/v2.1.0...v2.2.0)

**Implemented enhancements:**

- Add dashboard for cron-style jobs [\#367](https://github.com/bensheldon/good_job/pull/367) ([aried3r](https://github.com/aried3r))

**Fixed bugs:**

- Fix Dashboard navigation active class for Scheduled Jobs [\#375](https://github.com/bensheldon/good_job/pull/375) ([bensheldon](https://github.com/bensheldon))

**Closed issues:**

- Rename `GoodJob::Job` to be `GoodJob::Execution` [\#376](https://github.com/bensheldon/good_job/issues/376)
- More recognition in Rails community [\#370](https://github.com/bensheldon/good_job/issues/370)
- Concurrency control for all queued jobs [\#366](https://github.com/bensheldon/good_job/issues/366)

**Merged pull requests:**

- Rename `GoodJob::Job` to `GoodJob::Execution` [\#377](https://github.com/bensheldon/good_job/pull/377) ([bensheldon](https://github.com/bensheldon))
- Add example execution behavior \(errored, retried, dead\) to demo ExampleJob [\#374](https://github.com/bensheldon/good_job/pull/374) ([bensheldon](https://github.com/bensheldon))
- Add Passenger info for running in async mode [\#373](https://github.com/bensheldon/good_job/pull/373) ([aried3r](https://github.com/aried3r))
- Update bootstrap to latest 5.1.1 [\#372](https://github.com/bensheldon/good_job/pull/372) ([morgoth](https://github.com/morgoth))

## [v2.1.0](https://github.com/bensheldon/good_job/tree/v2.1.0) (2021-09-09)

[Full Changelog](https://github.com/bensheldon/good_job/compare/v2.0.5...v2.1.0)

**Implemented enhancements:**

- Add `total_limit:` option to GoodJob::Concurrency to be inclusive of counting both enqueued and performing jobs [\#369](https://github.com/bensheldon/good_job/pull/369) ([bensheldon](https://github.com/bensheldon))
- Add button to toggle all job params in Dashboard [\#365](https://github.com/bensheldon/good_job/pull/365) ([bensheldon](https://github.com/bensheldon))

**Fixed bugs:**

- Fix unlock key for Lockable\#with\_advisory\_lock [\#368](https://github.com/bensheldon/good_job/pull/368) ([bensheldon](https://github.com/bensheldon))

**Closed issues:**

- Cron-like jobs not always executed, possible reasons? [\#359](https://github.com/bensheldon/good_job/issues/359)

**Merged pull requests:**

- When shelling out in tests, send SIGKILL if process does not exit [\#371](https://github.com/bensheldon/good_job/pull/371) ([bensheldon](https://github.com/bensheldon))
- Have all tests use stubbed TestJob [\#364](https://github.com/bensheldon/good_job/pull/364) ([bensheldon](https://github.com/bensheldon))

## [v2.0.5](https://github.com/bensheldon/good_job/tree/v2.0.5) (2021-09-06)

[Full Changelog](https://github.com/bensheldon/good_job/compare/v2.0.4...v2.0.5)

**Closed issues:**

- Serialized Params and ActiveJob extensions [\#362](https://github.com/bensheldon/good_job/issues/362)

**Merged pull requests:**

- `deep_dup` serialized job data instead of`attr_readonly` to prevent overwriting [\#363](https://github.com/bensheldon/good_job/pull/363) ([bensheldon](https://github.com/bensheldon))

## [v2.0.4](https://github.com/bensheldon/good_job/tree/v2.0.4) (2021-08-31)

[Full Changelog](https://github.com/bensheldon/good_job/compare/v2.0.3...v2.0.4)

**Fixed bugs:**

- Remove `NOW()` from Dashboard SQL; fix chart x-axis order left-to-right, old-to-new [\#355](https://github.com/bensheldon/good_job/pull/355) ([bensheldon](https://github.com/bensheldon))

**Closed issues:**

- Content security policy for dashboard; nest shared view partials; problematic NOW\(\) SQL in Dashboard query   [\#304](https://github.com/bensheldon/good_job/issues/304)

**Merged pull requests:**

- Update development dependencies and ruby to 2.7.4 [\#358](https://github.com/bensheldon/good_job/pull/358) ([bensheldon](https://github.com/bensheldon))
- Add info about how to disable polling to README [\#357](https://github.com/bensheldon/good_job/pull/357) ([aried3r](https://github.com/aried3r))

## [v2.0.3](https://github.com/bensheldon/good_job/tree/v2.0.3) (2021-08-31)

[Full Changelog](https://github.com/bensheldon/good_job/compare/v2.0.2...v2.0.3)

**Implemented enhancements:**

- Implement `GoodJob.cleanup_preserved_jobs`, fixes \#351 [\#356](https://github.com/bensheldon/good_job/pull/356) ([aried3r](https://github.com/aried3r))

**Closed issues:**

- Expose CLI `cleanup_preserved_jobs` functionality via `GoodJob`? [\#351](https://github.com/bensheldon/good_job/issues/351)

## [v2.0.2](https://github.com/bensheldon/good_job/tree/v2.0.2) (2021-08-27)

[Full Changelog](https://github.com/bensheldon/good_job/compare/v1.99.1...v2.0.2)

**Fixed bugs:**

- v2.0: Generators support multiple databases: `--database` option, `migrations_paths`, custom `GoodJob.active_record_parent_class` [\#354](https://github.com/bensheldon/good_job/pull/354) ([bensheldon](https://github.com/bensheldon))

**Closed issues:**

- Migrations generator assumes migrations are in db/migrate [\#352](https://github.com/bensheldon/good_job/issues/352)

**Merged pull requests:**

- README style/typo fixes: "web server" and possessive "Rails'" [\#350](https://github.com/bensheldon/good_job/pull/350) ([aried3r](https://github.com/aried3r))
- Add examples of setting config.good\_job.queues [\#349](https://github.com/bensheldon/good_job/pull/349) ([zachmargolis](https://github.com/zachmargolis))

## [v1.99.1](https://github.com/bensheldon/good_job/tree/v1.99.1) (2021-08-27)

[Full Changelog](https://github.com/bensheldon/good_job/compare/v2.0.1...v1.99.1)

**Closed issues:**

- Does Good job support delay method? [\#344](https://github.com/bensheldon/good_job/issues/344)

## [v2.0.1](https://github.com/bensheldon/good_job/tree/v2.0.1) (2021-08-24)

[Full Changelog](https://github.com/bensheldon/good_job/compare/v2.0.0...v2.0.1)

**Implemented enhancements:**

- Suppress backtrace of ConcurrencyExceededError [\#348](https://github.com/bensheldon/good_job/pull/348) ([reczy](https://github.com/reczy))

**Closed issues:**

- Is there any value in seeing a backtrace for ConcurrencyExceededError? [\#347](https://github.com/bensheldon/good_job/issues/347)
- Release GoodJob 2.0 [\#307](https://github.com/bensheldon/good_job/issues/307)
- Unhandled ActiveJob errors should trigger GoodJob.on\_thread\_error [\#247](https://github.com/bensheldon/good_job/issues/247)

## [v2.0.0](https://github.com/bensheldon/good_job/tree/v2.0.0) (2021-08-24)

[Full Changelog](https://github.com/bensheldon/good_job/compare/v1.99.0...v2.0.0)

**Implemented enhancements:**

- Concurrency's enqueue\_limit should exclude performing jobs from count [\#317](https://github.com/bensheldon/good_job/issues/317)
- Rename `:async` to `:async_all`; `:async_server` to `:async` and set as Development environment default; do not poll in async development [\#343](https://github.com/bensheldon/good_job/pull/343) ([bensheldon](https://github.com/bensheldon))
- Exclude executing jobs from Concurrency's enqueue\_limit's count [\#342](https://github.com/bensheldon/good_job/pull/342) ([bensheldon](https://github.com/bensheldon))
- Unhandled ActiveJob errors should trigger GoodJob.on\_thread\_error [\#312](https://github.com/bensheldon/good_job/pull/312) ([bensheldon](https://github.com/bensheldon))

**Closed issues:**

- Swap behavior of `async` with `async_server`; rename `async` execution mode to be `async_all`; default `async` in Development; [\#340](https://github.com/bensheldon/good_job/issues/340)
- Add hyphen to lock key. e.g. "\[table\_name\]-\[column\]" instead of "\[table\_name\]\[column\]" [\#335](https://github.com/bensheldon/good_job/issues/335)
- Use `async_server` as default execution mode in Development environment [\#139](https://github.com/bensheldon/good_job/issues/139)

**Merged pull requests:**

- Remove v1.0 deprecation notices and incremental migrations [\#338](https://github.com/bensheldon/good_job/pull/338) ([bensheldon](https://github.com/bensheldon))
- Lock GoodJob::Job on active\_job\_id instead of the row id; adds separator hyphen to lock key [\#337](https://github.com/bensheldon/good_job/pull/337) ([bensheldon](https://github.com/bensheldon))

## [v1.99.0](https://github.com/bensheldon/good_job/tree/v1.99.0) (2021-08-24)

[Full Changelog](https://github.com/bensheldon/good_job/compare/v1.13.2...v1.99.0)

**Closed issues:**

- Set Advisory Lock on ActiveJob job uuid instead of GoodJob's job uuid [\#272](https://github.com/bensheldon/good_job/issues/272)

**Merged pull requests:**

- Add upgrade instructions for v1 to v2 [\#345](https://github.com/bensheldon/good_job/pull/345) ([bensheldon](https://github.com/bensheldon))
- Add transitional/temporary additional lock on good\_jobs-\[active\_job\_id\] [\#336](https://github.com/bensheldon/good_job/pull/336) ([bensheldon](https://github.com/bensheldon))

## [v1.13.2](https://github.com/bensheldon/good_job/tree/v1.13.2) (2021-08-18)

[Full Changelog](https://github.com/bensheldon/good_job/compare/v1.13.1...v1.13.2)

**Merged pull requests:**

- Add deprecation notice that `async` mode will be renamed `async_all` in GoodJob v2.0 [\#339](https://github.com/bensheldon/good_job/pull/339) ([bensheldon](https://github.com/bensheldon))

## [v1.13.1](https://github.com/bensheldon/good_job/tree/v1.13.1) (2021-08-18)

[Full Changelog](https://github.com/bensheldon/good_job/compare/v1.13.0...v1.13.1)

**Fixed bugs:**

- Don’t attempt to enforce concurrency limits with other queue adapters [\#333](https://github.com/bensheldon/good_job/pull/333) ([codyrobbins](https://github.com/codyrobbins))

## [v1.13.0](https://github.com/bensheldon/good_job/tree/v1.13.0) (2021-08-18)

[Full Changelog](https://github.com/bensheldon/good_job/compare/v1.12.2...v1.13.0)

**Implemented enhancements:**

- Track if a GoodJob::Job has been subsequently retried [\#331](https://github.com/bensheldon/good_job/pull/331) ([bensheldon](https://github.com/bensheldon))
- Wrap and truncate error message, which can be a huge text [\#294](https://github.com/bensheldon/good_job/pull/294) ([morgoth](https://github.com/morgoth))

**Closed issues:**

- Add hyphen to lock string. e.g. "table\_name-column" instead of "table\_namecolumn [\#334](https://github.com/bensheldon/good_job/issues/334)
- Optimize db indexes in advance of v2.0.0 [\#332](https://github.com/bensheldon/good_job/issues/332)
- wait\_until in development? [\#330](https://github.com/bensheldon/good_job/issues/330)
- Race conditions in ActiveJob concurrency extension [\#325](https://github.com/bensheldon/good_job/issues/325)
- Store in database if a job has been ActiveJob retried [\#321](https://github.com/bensheldon/good_job/issues/321)
- Revisit and embrace concurrency control, scheduled jobs, and other extensions of ActiveJob [\#255](https://github.com/bensheldon/good_job/issues/255)
- Why 1 million jobs per day? [\#222](https://github.com/bensheldon/good_job/issues/222)

## [v1.12.2](https://github.com/bensheldon/good_job/tree/v1.12.2) (2021-08-13)

[Full Changelog](https://github.com/bensheldon/good_job/compare/v1.12.1...v1.12.2)

**Fixed bugs:**

- Fixes for race conditions in ActiveJob concurrency extension [\#326](https://github.com/bensheldon/good_job/pull/326) ([codyrobbins](https://github.com/codyrobbins))

**Merged pull requests:**

- On gem release, add instructions to author a Github Release [\#324](https://github.com/bensheldon/good_job/pull/324) ([bensheldon](https://github.com/bensheldon))

## [v1.12.1](https://github.com/bensheldon/good_job/tree/v1.12.1) (2021-08-05)

[Full Changelog](https://github.com/bensheldon/good_job/compare/v1.12.0...v1.12.1)

**Fixed bugs:**

- Ensure CLI can shutdown cleanly with multiple queues and timeout [\#319](https://github.com/bensheldon/good_job/pull/319) ([bensheldon](https://github.com/bensheldon))

**Closed issues:**

- Setting a shutdown timeout causes the CLI executor to throw an exception on shutdown. [\#318](https://github.com/bensheldon/good_job/issues/318)
- PgBouncer and prepared statements [\#269](https://github.com/bensheldon/good_job/issues/269)
- Question about locking internals [\#212](https://github.com/bensheldon/good_job/issues/212)
- Encoding::UndefinedConversionError \("\xE2" from ASCII-8BIT to UTF-8\) [\#198](https://github.com/bensheldon/good_job/issues/198)

**Merged pull requests:**

- Fix Readme lint warnings [\#320](https://github.com/bensheldon/good_job/pull/320) ([bensheldon](https://github.com/bensheldon))

## [v1.12.0](https://github.com/bensheldon/good_job/tree/v1.12.0) (2021-07-27)

[Full Changelog](https://github.com/bensheldon/good_job/compare/v1.11.3...v1.12.0)

**Implemented enhancements:**

- Add the ability to schedule repeating / recurring / cron-like jobs [\#53](https://github.com/bensheldon/good_job/issues/53)
- Add cron-like support for recurring/repeating jobs [\#297](https://github.com/bensheldon/good_job/pull/297) ([bensheldon](https://github.com/bensheldon))

**Fixed bugs:**

- Place Dashboard shared view partials under `good_job` namespace [\#310](https://github.com/bensheldon/good_job/pull/310) ([bensheldon](https://github.com/bensheldon))
- Ensure Dashboard inline javascript has CSP nonce for strict Content-Security Policy [\#309](https://github.com/bensheldon/good_job/pull/309) ([bensheldon](https://github.com/bensheldon))

## [v1.11.3](https://github.com/bensheldon/good_job/tree/v1.11.3) (2021-07-25)

[Full Changelog](https://github.com/bensheldon/good_job/compare/v1.11.2...v1.11.3)

**Closed issues:**

- Add Frozen String Literal to all files [\#298](https://github.com/bensheldon/good_job/issues/298)
- Support for good\_job without Rails? [\#295](https://github.com/bensheldon/good_job/issues/295)

**Merged pull requests:**

- Have prettier Dashboard asset urls e.g. `bootstrap.css` instead of `bootstrap_css.css` [\#306](https://github.com/bensheldon/good_job/pull/306) ([bensheldon](https://github.com/bensheldon))
- Create dashboard demo app on Heroku [\#305](https://github.com/bensheldon/good_job/pull/305) ([bensheldon](https://github.com/bensheldon))
- Add Frozen String Literal to all files [\#302](https://github.com/bensheldon/good_job/pull/302) ([tedhexaflow](https://github.com/tedhexaflow))

## [v1.11.2](https://github.com/bensheldon/good_job/tree/v1.11.2) (2021-07-20)

[Full Changelog](https://github.com/bensheldon/good_job/compare/v1.11.1...v1.11.2)

**Fixed bugs:**

- Notifier waits to retry listening when database is unavailable [\#301](https://github.com/bensheldon/good_job/pull/301) ([bensheldon](https://github.com/bensheldon))

**Closed issues:**

- Handle database connection drops [\#296](https://github.com/bensheldon/good_job/issues/296)
- Using the `async` worker results in `ActiveModel::UnknownAttributeError  unknown attribute 'create_with_advisory_lock' for GoodJob::Job`. [\#290](https://github.com/bensheldon/good_job/issues/290)

**Merged pull requests:**

- Rename development and test databases to be `good_job` [\#300](https://github.com/bensheldon/good_job/pull/300) ([bensheldon](https://github.com/bensheldon))
- Move generators spec into top-level spec directory; update dependencies [\#299](https://github.com/bensheldon/good_job/pull/299) ([bensheldon](https://github.com/bensheldon))

## [v1.11.1](https://github.com/bensheldon/good_job/tree/v1.11.1) (2021-07-07)

[Full Changelog](https://github.com/bensheldon/good_job/compare/v1.11.0...v1.11.1)

**Fixed bugs:**

- Defer accessing ActiveRecord `primary_key` in Lockable [\#293](https://github.com/bensheldon/good_job/pull/293) ([bensheldon](https://github.com/bensheldon))

**Closed issues:**

- Database connection required while loading the code on 1.10.x [\#291](https://github.com/bensheldon/good_job/issues/291)

## [v1.11.0](https://github.com/bensheldon/good_job/tree/v1.11.0) (2021-07-07)

[Full Changelog](https://github.com/bensheldon/good_job/compare/v1.10.1...v1.11.0)

**Implemented enhancements:**

- Add concurrency extension for ActiveJob [\#281](https://github.com/bensheldon/good_job/pull/281) ([bensheldon](https://github.com/bensheldon))

**Closed issues:**

- Investigate GoodJob concurrency [\#289](https://github.com/bensheldon/good_job/issues/289)
- Problem with migrating database on 1.10.0 [\#287](https://github.com/bensheldon/good_job/issues/287)
- Support migration --database option for install task? [\#267](https://github.com/bensheldon/good_job/issues/267)
- Add GoodJob to Ruby Toolbox [\#243](https://github.com/bensheldon/good_job/issues/243)
- Custom advisory locks to prevent certain jobs from being worked on concurrently? [\#206](https://github.com/bensheldon/good_job/issues/206)

## [v1.10.1](https://github.com/bensheldon/good_job/tree/v1.10.1) (2021-06-30)

[Full Changelog](https://github.com/bensheldon/good_job/compare/v1.10.0...v1.10.1)

**Fixed bugs:**

- Remove `FOR UPDATE SKIP LOCKED` from job locking sql statement [\#288](https://github.com/bensheldon/good_job/pull/288) ([bensheldon](https://github.com/bensheldon))

**Merged pull requests:**

- Update GH Test Matrix with latest JRuby 9.2.19.0 [\#283](https://github.com/bensheldon/good_job/pull/283) ([tedhexaflow](https://github.com/tedhexaflow))

## [v1.10.0](https://github.com/bensheldon/good_job/tree/v1.10.0) (2021-06-29)

[Full Changelog](https://github.com/bensheldon/good_job/compare/v1.9.6...v1.10.0)

**Implemented enhancements:**

- Use `pg_advisory_unlock_all` after each thread's job execution; fix Lockable return values; improve test stability [\#285](https://github.com/bensheldon/good_job/pull/285) ([bensheldon](https://github.com/bensheldon))
- Add `rails g good_job:update` command to add idempotent migration files, including `active_job_id`, `concurrency_key`, `cron_key` columns [\#266](https://github.com/bensheldon/good_job/pull/266) ([bensheldon](https://github.com/bensheldon))

**Fixed bugs:**

- Dashboard AssetsController does not raise if verify\_authenticity\_token is not in the callback chain [\#284](https://github.com/bensheldon/good_job/pull/284) ([bensheldon](https://github.com/bensheldon))

**Closed issues:**

- \[Question\] Dashboard assets not showing [\#282](https://github.com/bensheldon/good_job/issues/282)

**Merged pull requests:**

- Separately cache Appraisal gems in GH Action [\#280](https://github.com/bensheldon/good_job/pull/280) ([bensheldon](https://github.com/bensheldon))
- Use custom RSpec doc formatter to show spec examples that are running [\#279](https://github.com/bensheldon/good_job/pull/279) ([bensheldon](https://github.com/bensheldon))
- Update development dependencies [\#278](https://github.com/bensheldon/good_job/pull/278) ([bensheldon](https://github.com/bensheldon))
- Fix Scheduler integration spec to ensure jobs are run in the Scheduler under test [\#276](https://github.com/bensheldon/good_job/pull/276) ([bensheldon](https://github.com/bensheldon))
- Add example benchmark for job throughput [\#275](https://github.com/bensheldon/good_job/pull/275) ([bensheldon](https://github.com/bensheldon))
- Allow Lockable to be passed custom column, key, and Postgres advisory lock/unlock function [\#273](https://github.com/bensheldon/good_job/pull/273) ([bensheldon](https://github.com/bensheldon))

## [v1.9.6](https://github.com/bensheldon/good_job/tree/v1.9.6) (2021-06-04)

[Full Changelog](https://github.com/bensheldon/good_job/compare/v1.9.5...v1.9.6)

**Implemented enhancements:**

- Add deleting jobs from UI. [\#265](https://github.com/bensheldon/good_job/pull/265) ([morgoth](https://github.com/morgoth))
- Collapse Dashboard params by default [\#263](https://github.com/bensheldon/good_job/pull/263) ([morgoth](https://github.com/morgoth))

**Closed issues:**

- Pause jobs during migration / maintenance? [\#257](https://github.com/bensheldon/good_job/issues/257)
- How to properly report errors to error tracker service [\#159](https://github.com/bensheldon/good_job/issues/159)

## [v1.9.5](https://github.com/bensheldon/good_job/tree/v1.9.5) (2021-05-24)

[Full Changelog](https://github.com/bensheldon/good_job/compare/v1.9.4...v1.9.5)

**Implemented enhancements:**

- Update Dashboard to Bootstrap 5 [\#260](https://github.com/bensheldon/good_job/pull/260) ([morgoth](https://github.com/morgoth))

**Closed issues:**

- Update from bootstrap 4 to bootstrap 5 [\#258](https://github.com/bensheldon/good_job/issues/258)

**Merged pull requests:**

- Serve Dashboard assets as discrete paths instead of inlining [\#262](https://github.com/bensheldon/good_job/pull/262) ([bensheldon](https://github.com/bensheldon))
- Fix Gemfile.lock's missing JRuby dependencies; fix release script and add check [\#261](https://github.com/bensheldon/good_job/pull/261) ([bensheldon](https://github.com/bensheldon))

## [v1.9.4](https://github.com/bensheldon/good_job/tree/v1.9.4) (2021-05-18)

[Full Changelog](https://github.com/bensheldon/good_job/compare/v1.9.3...v1.9.4)

**Implemented enhancements:**

- Add "running" jobs state to Dashboard [\#253](https://github.com/bensheldon/good_job/pull/253) ([morgoth](https://github.com/morgoth))

**Fixed bugs:**

- Unify displaying timestamps [\#252](https://github.com/bensheldon/good_job/pull/252) ([morgoth](https://github.com/morgoth))
- Fix dashboard jobs endless pagination with timezone handling [\#251](https://github.com/bensheldon/good_job/pull/251) ([morgoth](https://github.com/morgoth))

**Closed issues:**

- exception\_executions not counted correctly? [\#215](https://github.com/bensheldon/good_job/issues/215)
- Document issues with PgBouncer and session-level Advisory Locks [\#52](https://github.com/bensheldon/good_job/issues/52)

**Merged pull requests:**

- Add handy scope for filtering by job class [\#259](https://github.com/bensheldon/good_job/pull/259) ([morgoth](https://github.com/morgoth))
- Nest exception stub within job class and cleanup let! precedence to fix flakey JRuby tests [\#254](https://github.com/bensheldon/good_job/pull/254) ([bensheldon](https://github.com/bensheldon))
- Move good\_job\_spec.rb to proper location in lib directory [\#250](https://github.com/bensheldon/good_job/pull/250) ([bensheldon](https://github.com/bensheldon))
- Refactor deprecated wait parameter and assorted improvements [\#249](https://github.com/bensheldon/good_job/pull/249) ([bensheldon](https://github.com/bensheldon))
- Update development dependencies \(Rails v6.1.3.2\) [\#248](https://github.com/bensheldon/good_job/pull/248) ([bensheldon](https://github.com/bensheldon))
- Update YARD documentation param types and return values [\#239](https://github.com/bensheldon/good_job/pull/239) ([bensheldon](https://github.com/bensheldon))

## [v1.9.3](https://github.com/bensheldon/good_job/tree/v1.9.3) (2021-05-10)

[Full Changelog](https://github.com/bensheldon/good_job/compare/v1.9.2...v1.9.3)

**Implemented enhancements:**

- Add async\_server detection for extensions of rack handler [\#246](https://github.com/bensheldon/good_job/pull/246) ([bensheldon](https://github.com/bensheldon))

**Closed issues:**

- Not processing unfinished jobs across server restarts using async\_server mode on Iodine server [\#244](https://github.com/bensheldon/good_job/issues/244)
- No connection pool for 'ActiveRecord::Base' found [\#236](https://github.com/bensheldon/good_job/issues/236)

## [v1.9.2](https://github.com/bensheldon/good_job/tree/v1.9.2) (2021-05-10)

[Full Changelog](https://github.com/bensheldon/good_job/compare/v1.9.1...v1.9.2)

**Fixed bugs:**

- Run Scheduler\#warm\_cache operation in threadpool executor [\#242](https://github.com/bensheldon/good_job/pull/242) ([bensheldon](https://github.com/bensheldon))

**Closed issues:**

- Jobs not visible in dashboard [\#245](https://github.com/bensheldon/good_job/issues/245)

**Merged pull requests:**

- Use GoodJob::Job::ExecutionResult object instead of job execution returning an ordered array [\#241](https://github.com/bensheldon/good_job/pull/241) ([bensheldon](https://github.com/bensheldon))
- Update development dependencies [\#240](https://github.com/bensheldon/good_job/pull/240) ([bensheldon](https://github.com/bensheldon))

## [v1.9.1](https://github.com/bensheldon/good_job/tree/v1.9.1) (2021-04-19)

[Full Changelog](https://github.com/bensheldon/good_job/compare/v1.9.0...v1.9.1)

**Implemented enhancements:**

- Allow to specify parent class for active record [\#238](https://github.com/bensheldon/good_job/pull/238) ([morgoth](https://github.com/morgoth))

## [v1.9.0](https://github.com/bensheldon/good_job/tree/v1.9.0) (2021-04-16)

[Full Changelog](https://github.com/bensheldon/good_job/compare/v1.8.0...v1.9.0)

**Implemented enhancements:**

- Add `async_server` option to run async only in Rails web server process [\#230](https://github.com/bensheldon/good_job/pull/230) ([bensheldon](https://github.com/bensheldon))
- FreeBSD startup script [\#221](https://github.com/bensheldon/good_job/pull/221) ([lauer](https://github.com/lauer))

**Fixed bugs:**

- Fix instrumentation of GoodJob::Poller finished\_timer\_task event [\#233](https://github.com/bensheldon/good_job/pull/233) ([bensheldon](https://github.com/bensheldon))

**Closed issues:**

- Cannot run db:migrate when execution mode is :async [\#229](https://github.com/bensheldon/good_job/issues/229)
- How do you enqueue a job to be executed immediately outside of Rails \(eg. creating a new record of good\_jobs in Postgresql\)? [\#225](https://github.com/bensheldon/good_job/issues/225)
- Feature Ideas [\#220](https://github.com/bensheldon/good_job/issues/220)
- Goodjob startup script for FreeBSD [\#214](https://github.com/bensheldon/good_job/issues/214)
- Only start async mode executors when server is running [\#194](https://github.com/bensheldon/good_job/issues/194)

**Merged pull requests:**

- Move executable flags from constants to accessors on GoodJob::CLI [\#234](https://github.com/bensheldon/good_job/pull/234) ([bensheldon](https://github.com/bensheldon))
- Add custom Scheduler::TimerSet [\#232](https://github.com/bensheldon/good_job/pull/232) ([bensheldon](https://github.com/bensheldon))
- Fix assorted constant references in YARD documentation [\#231](https://github.com/bensheldon/good_job/pull/231) ([bensheldon](https://github.com/bensheldon))
- Update GH Test Matrix with latest JRuby 9.2.17.0 [\#228](https://github.com/bensheldon/good_job/pull/228) ([tedhexaflow](https://github.com/tedhexaflow))
- Update gem dependencies [\#227](https://github.com/bensheldon/good_job/pull/227) ([bensheldon](https://github.com/bensheldon))
- Remove leftover text from Readme [\#226](https://github.com/bensheldon/good_job/pull/226) ([weh](https://github.com/weh))
- Fix appraisal and bundler version CI conflicts [\#224](https://github.com/bensheldon/good_job/pull/224) ([bensheldon](https://github.com/bensheldon))
- Update GH Test Matrix with latest JRuby [\#223](https://github.com/bensheldon/good_job/pull/223) ([tedhexaflow](https://github.com/tedhexaflow))

## [v1.8.0](https://github.com/bensheldon/good_job/tree/v1.8.0) (2021-03-04)

[Full Changelog](https://github.com/bensheldon/good_job/compare/v1.7.1...v1.8.0)

**Implemented enhancements:**

- Wait then stop on shutdown [\#126](https://github.com/bensheldon/good_job/issues/126)
- Add shutdown-timeout option to configure the wait for jobs to gracefully finish before stopping them [\#213](https://github.com/bensheldon/good_job/pull/213) ([bensheldon](https://github.com/bensheldon))

**Fixed bugs:**

- Ensure Job\#serialized\_params are immutable [\#218](https://github.com/bensheldon/good_job/pull/218) ([bensheldon](https://github.com/bensheldon))

**Closed issues:**

- Run GoodJob on puma boot [\#91](https://github.com/bensheldon/good_job/issues/91)
- ActiveRecord::ConnectionNotEstablished when using async mode [\#89](https://github.com/bensheldon/good_job/issues/89)

**Merged pull requests:**

- Update bundler and Appraisals so Rails HEAD is locked to Ruby version \>= 2.7 [\#219](https://github.com/bensheldon/good_job/pull/219) ([bensheldon](https://github.com/bensheldon))

## [v1.7.1](https://github.com/bensheldon/good_job/tree/v1.7.1) (2021-01-27)

[Full Changelog](https://github.com/bensheldon/good_job/compare/v1.7.0...v1.7.1)

**Fixed bugs:**

- Scheduler should always push a new task on completion of previous task, regardless of available thread calculation [\#209](https://github.com/bensheldon/good_job/pull/209) ([bensheldon](https://github.com/bensheldon))

**Closed issues:**

- Unexpected behavior with max\_threads = 1 [\#208](https://github.com/bensheldon/good_job/issues/208)

**Merged pull requests:**

- Fix equality typo in development.rb of test\_app [\#207](https://github.com/bensheldon/good_job/pull/207) ([reczy](https://github.com/reczy))

## [v1.7.0](https://github.com/bensheldon/good_job/tree/v1.7.0) (2021-01-25)

[Full Changelog](https://github.com/bensheldon/good_job/compare/v1.6.0...v1.7.0)

**Implemented enhancements:**

- Cache scheduled jobs in memory so they can be executed without polling [\#205](https://github.com/bensheldon/good_job/pull/205) ([bensheldon](https://github.com/bensheldon))

## [v1.6.0](https://github.com/bensheldon/good_job/tree/v1.6.0) (2021-01-22)

[Full Changelog](https://github.com/bensheldon/good_job/compare/v1.5.0...v1.6.0)

**Implemented enhancements:**

- Running as a daemon [\#88](https://github.com/bensheldon/good_job/issues/88)
- Add daemonize option to CLI [\#202](https://github.com/bensheldon/good_job/pull/202) ([bensheldon](https://github.com/bensheldon))

**Closed issues:**

- Rails 6.1 & async - `queue_parser': undefined method `first' for "\*":String \(NoMethodError\) [\#195](https://github.com/bensheldon/good_job/issues/195)

**Merged pull requests:**

- Add scripts directory for benchmarking and dev tasks [\#204](https://github.com/bensheldon/good_job/pull/204) ([bensheldon](https://github.com/bensheldon))
- Fix YARD attr\_ declarations for documentation [\#203](https://github.com/bensheldon/good_job/pull/203) ([bensheldon](https://github.com/bensheldon))
- Remove Appraisal gemfile locks [\#201](https://github.com/bensheldon/good_job/pull/201) ([bensheldon](https://github.com/bensheldon))

## [v1.5.0](https://github.com/bensheldon/good_job/tree/v1.5.0) (2021-01-18)

[Full Changelog](https://github.com/bensheldon/good_job/compare/v1.4.1...v1.5.0)

**Implemented enhancements:**

- Create Web UI Dashboard [\#50](https://github.com/bensheldon/good_job/issues/50)
- Configure GoodJob via `Rails.application.config` instead of recommending `GoodJob::Adapter.new` [\#199](https://github.com/bensheldon/good_job/pull/199) ([bensheldon](https://github.com/bensheldon))

**Closed issues:**

- JRuby Support [\#160](https://github.com/bensheldon/good_job/issues/160)

**Merged pull requests:**

- Update bundler version to 2.2.5 [\#200](https://github.com/bensheldon/good_job/pull/200) ([bensheldon](https://github.com/bensheldon))
- Update GH Test Matrix with minimum & latest JRuby version [\#197](https://github.com/bensheldon/good_job/pull/197) ([tedhexaflow](https://github.com/tedhexaflow))
- Fix JRuby version number [\#193](https://github.com/bensheldon/good_job/pull/193) ([tedhexaflow](https://github.com/tedhexaflow))

## [v1.4.1](https://github.com/bensheldon/good_job/tree/v1.4.1) (2021-01-09)

[Full Changelog](https://github.com/bensheldon/good_job/compare/v1.4.0...v1.4.1)

**Fixed bugs:**

- Do not add lib/generators to Zeitwerk autoloader [\#192](https://github.com/bensheldon/good_job/pull/192) ([bensheldon](https://github.com/bensheldon))

**Closed issues:**

- Issues with Heroku and Good Job [\#184](https://github.com/bensheldon/good_job/issues/184)

**Merged pull requests:**

- Add missing YARD docs and Dashboard screenshot [\#191](https://github.com/bensheldon/good_job/pull/191) ([bensheldon](https://github.com/bensheldon))

## [v1.4.0](https://github.com/bensheldon/good_job/tree/v1.4.0) (2020-12-31)

[Full Changelog](https://github.com/bensheldon/good_job/compare/v1.3.6...v1.4.0)

**Implemented enhancements:**

- Add JRuby support [\#167](https://github.com/bensheldon/good_job/pull/167) ([bensheldon](https://github.com/bensheldon))

## [v1.3.6](https://github.com/bensheldon/good_job/tree/v1.3.6) (2020-12-30)

[Full Changelog](https://github.com/bensheldon/good_job/compare/v1.3.5...v1.3.6)

**Implemented enhancements:**

- Call GoodJob.on\_thread\_error when Notifier thread raises exception [\#185](https://github.com/bensheldon/good_job/pull/185) ([bensheldon](https://github.com/bensheldon))
- Improve dashboard UI, fix button state, add unfiltering [\#181](https://github.com/bensheldon/good_job/pull/181) ([bensheldon](https://github.com/bensheldon))

**Fixed bugs:**

- Replace ActiveRecord execute usage and avoid potential memory leakage [\#187](https://github.com/bensheldon/good_job/issues/187)
- Does good\_job hold on to advisory locks for finished jobs? [\#177](https://github.com/bensheldon/good_job/issues/177)

**Merged pull requests:**

- Run tests with Rails default configuration to enable Zeitwerk [\#190](https://github.com/bensheldon/good_job/pull/190) ([bensheldon](https://github.com/bensheldon))
- Update all Lockable queries to use exec\_query instead of execute; clear async\_exec results [\#189](https://github.com/bensheldon/good_job/pull/189) ([bensheldon](https://github.com/bensheldon))
- Have Lockable\#advisory\_locked? directly query pg\_locks table [\#188](https://github.com/bensheldon/good_job/pull/188) ([bensheldon](https://github.com/bensheldon))
- Update development gems, including Rails v6.1 and Rails HEAD [\#186](https://github.com/bensheldon/good_job/pull/186) ([bensheldon](https://github.com/bensheldon))
- Update Appraisals for Rails 6.1 [\#183](https://github.com/bensheldon/good_job/pull/183) ([bensheldon](https://github.com/bensheldon))
- Add Ruby 3 to CI test matrix [\#182](https://github.com/bensheldon/good_job/pull/182) ([bensheldon](https://github.com/bensheldon))

## [v1.3.5](https://github.com/bensheldon/good_job/tree/v1.3.5) (2020-12-17)

[Full Changelog](https://github.com/bensheldon/good_job/compare/v1.3.4...v1.3.5)

**Fixed bugs:**

-  Ensure advisory lock CTE is MATERIALIZED on Postgres v12+ [\#179](https://github.com/bensheldon/good_job/pull/179) ([bensheldon](https://github.com/bensheldon))
- Ensure that deleted jobs are unlocked [\#178](https://github.com/bensheldon/good_job/pull/178) ([bensheldon](https://github.com/bensheldon))

**Closed issues:**

- not running jobs [\#168](https://github.com/bensheldon/good_job/issues/168)
- how to run good\_job on a separate machine  [\#162](https://github.com/bensheldon/good_job/issues/162)

**Merged pull requests:**

- Add Appraisal for Rails 6.1-rc2 [\#175](https://github.com/bensheldon/good_job/pull/175) ([bensheldon](https://github.com/bensheldon))

## [v1.3.4](https://github.com/bensheldon/good_job/tree/v1.3.4) (2020-12-02)

[Full Changelog](https://github.com/bensheldon/good_job/compare/v1.3.3...v1.3.4)

**Fixed bugs:**

- Fix job ordering for Rails 6.1 [\#174](https://github.com/bensheldon/good_job/pull/174) ([morgoth](https://github.com/morgoth))

## [v1.3.3](https://github.com/bensheldon/good_job/tree/v1.3.3) (2020-12-01)

[Full Changelog](https://github.com/bensheldon/good_job/compare/v1.3.2...v1.3.3)

**Implemented enhancements:**

- UI: Admin UI with filters and space efficient layout [\#173](https://github.com/bensheldon/good_job/pull/173) ([zealot128](https://github.com/zealot128))

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
- Rename reperform\_jobs\_on\_standard\_error to retry\_on\_unhandled\_error [\#154](https://github.com/bensheldon/good_job/pull/154) ([morgoth](https://github.com/morgoth))

## [v1.2.6](https://github.com/bensheldon/good_job/tree/v1.2.6) (2020-09-29)

[Full Changelog](https://github.com/bensheldon/good_job/compare/v1.2.5...v1.2.6)

**Implemented enhancements:**

- Preserve only failed jobs [\#136](https://github.com/bensheldon/good_job/issues/136)
- Add `GoodJob.preserve_job_records = :on_unhandled_error` option to only preserve jobs that errored [\#145](https://github.com/bensheldon/good_job/pull/145) ([morgoth](https://github.com/morgoth))

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
- Use `connection.quote_table_name` and add spacing for SQL concatenation [\#124](https://github.com/bensheldon/good_job/pull/124) ([bensheldon](https://github.com/bensheldon))

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

- Add environment variable to mirror `cleanup_preserved_jobs --before-seconds-ago=SECONDS` [\#110](https://github.com/bensheldon/good_job/issues/110)
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
- Name the thread pools [\#96](https://github.com/bensheldon/good_job/pull/96) ([sj26](https://github.com/sj26))

**Fixed bugs:**

- Freezes puma on code change [\#95](https://github.com/bensheldon/good_job/issues/95)
- Ruby 2.7 keyword arguments warning [\#93](https://github.com/bensheldon/good_job/issues/93)
- Return to using executor.wrap around Scheduler execution task [\#99](https://github.com/bensheldon/good_job/pull/99) ([bensheldon](https://github.com/bensheldon))

**Closed issues:**

- Add test for `rails g good_job:install` [\#57](https://github.com/bensheldon/good_job/issues/57)

**Merged pull requests:**

- Use more ActiveRecord in Lockable and not connection.execute [\#102](https://github.com/bensheldon/good_job/pull/102) ([bensheldon](https://github.com/bensheldon))
- Run CI tests on Ruby 2.5, 2.6, and 2.7 [\#101](https://github.com/bensheldon/good_job/pull/101) ([arku](https://github.com/arku))
- Fix Ruby 2.7 keyword arguments warning [\#98](https://github.com/bensheldon/good_job/pull/98) ([arku](https://github.com/arku))
- Remove executor/reloader for less interlocking [\#97](https://github.com/bensheldon/good_job/pull/97) ([sj26](https://github.com/sj26))
- Add test for `rails g good_job:install` [\#94](https://github.com/bensheldon/good_job/pull/94) ([arku](https://github.com/arku))

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
- Allow configuration of Rails queue adapter with `:good_job` [\#28](https://github.com/bensheldon/good_job/pull/28) ([bensheldon](https://github.com/bensheldon))

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
