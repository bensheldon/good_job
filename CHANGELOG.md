# Changelog

## [v0.8.2](https://github.com/bensheldon/good_job/tree/v0.8.2) (2020-07-18)

[Full Changelog](https://github.com/bensheldon/good_job/compare/v0.6.0...v0.8.2)

**Closed issues:**

- Always store a default priority \(0\) and scheduled\_at\(Time.current\) [\#30](https://github.com/bensheldon/good_job/issues/30)
- Add a job timeout configuration to time out jobs that have run too long [\#19](https://github.com/bensheldon/good_job/issues/19)

**Merged pull requests:**

- Run Github Action tests on PRs from forks [\#44](https://github.com/bensheldon/good_job/pull/44) ([bensheldon](https://github.com/bensheldon))
- Fix Rubygems homepage URL [\#43](https://github.com/bensheldon/good_job/pull/43) ([joshmn](https://github.com/joshmn))
- Move where\(scheduled\_at: Time.current\) into dynamic part of GoodJob::Job::Performer [\#42](https://github.com/bensheldon/good_job/pull/42) ([bensheldon](https://github.com/bensheldon))
- Replace Adapter inline boolean kwarg with execution\_mode instead [\#41](https://github.com/bensheldon/good_job/pull/41) ([bensheldon](https://github.com/bensheldon))
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
