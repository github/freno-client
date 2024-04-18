# frozen_string_literal: true

require "bundler/gem_tasks"
require "minitest/test_task"
require "rubocop/rake_task"

Minitest::TestTask.create(:test)
RuboCop::RakeTask.new(:rubocop)

task default: %i[test rubocop]
