# syntax=docker/dockerfile:1.7
# Redmine 7.0.2 as the plugin's tests need it: the test gems, a compiler for them and a test
# database. bin/test builds it and mounts the plugin at plugins/redmine_ulysses; nothing here is
# for production.
FROM redmine:7.0.2

ENV RAILS_ENV=test
RUN apt-get update \
 && apt-get install -y --no-install-recommends build-essential \
 && rm -rf /var/lib/apt/lists/*
# Redmine's Gemfile picks the database gems from database.yml, so it goes in before the install.
COPY test/database.yml config/database.yml
RUN bundle config unset without \
 && bundle install \
 && bin/rake db:create db:migrate
