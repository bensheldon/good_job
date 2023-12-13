#!/bin/bash

set -xuo pipefail
# Check for new migrations
versions=$(git diff --name-status remotes/origin/main demo/db/migrate/ | grep '^A' | cut -f2 | sed 's/[^0-9]//g' | sort -n --reverse)
set -Ee # Enable failed command checks after checking

if [ -z "$versions" ] ; then
  echo "No changes to migrations."
  exit 0
fi

# Replace schema.rb with one from main branch
rm demo/db/schema.rb
git checkout demo/db/schema.rb db/

# Create database with schema from main branch
bundle exec rake db:drop db:create
bundle exec rake db:schema:load

# Apply migrations and check that the generated schema.rb now matches the committed one
bundle exec rake db:migrate
if ! git diff --ignore-all-space --exit-code "HEAD" -- demo/db/schema.rb ; then
  echo "Generated schema.rb does not match committed schema.rb"
  exit 1
fi

# Run all migrations in reverse
for version in $versions
do
  if grep -E 'raise (ActiveRecord::)?IrreversibleMigration' < "db/migrate/$version"* ; then
    # One of the migrations explicitly uses IrreversibleMigration.
    # Skip check for valid reversing
    echo "Irreversible migration $version means we can't check for valid schema.rb; skipping"
    exit 0
  else
    bundle exec rake db:migrate:down "VERSION=${version}"
  fi
done

# Compare the resulting schema with
bundle exec rake db:schema:dump
if ! git diff --ignore-all-space --exit-code "$(git merge-base HEAD main)" -- demo/db/schema.rb ; then
  echo "Some migrations could not be reversed cleanly, but do not reference IrreversibleMigration"
  exit 1
fi
