# Contributing to GoodJob

<!-- Please keep this section in sync with README.md#contribute -->

All contributions, from feedback to code and beyond, are welcomed and appreciated 🙏

- Review the [Prioritized Project Backlog](https://github.com/bensheldon/good_job/projects/1).
- Open a new Issue or contribute to an [existing Issue](https://github.com/bensheldon/good_job/issues). Questions or suggestions are fantastic.
- Participate according to our [Code of Conduct](/CODE_OF_CONDUCT.md).
- Financially support the project via [Sponsorship](https://github.com/sponsors/bensheldon).

For gem development and debugging information, please review the [README's Gem Development section](/README.md#gem-development).

## Development Guidelines

- **Gem database migrations must be non-breaking if not applied.** Any new column added via a GoodJob update migration must function as a progressive enhancement: GoodJob must work correctly without it, and applying the migration only unlocks additional functionality. This keeps update migrations optional until the next major GoodJob release, so that applying them is never a breaking change.
  - Update the singular install migration template, then add a new numbered update migration. Migrations should be a no-op if the install migration already applied the change (`up` can be a no-op), but the update migration must be rollbackable (`down` must always be applicable).
  - In model or behavioral code, guard anything that requires the new column so that if the migration hasn't run, the code does not raise. Use `has_attribute?`, `column_names.include?`, or similar guards.
  - Update `GoodJob.migrated?` to check for the latest migration change. It only needs to check the last change because migrations are expected to run in order.
  - Add an entry to `spec/integration/breaking_migrations_spec.rb` to smoke-test that the new column is handled gracefully when absent.
  - Some Active Record features are difficult to make safe, e.g. `enum`, which raises at schema load time when the backing column does not exist.

## Other Errata

- **Active Record `attribute` cannot be used.** Calling `attribute` (the AR attributes API) necessitates a database connection when Tapioca runs its DSL compilers, which breaks Tapioca's type generation. Use explicit accessor methods instead.
