# frozen_string_literal: true

# Add your own tasks in files placed in lib/tasks ending in .rake,
# for example lib/tasks/capistrano.rake, and they will automatically be available to Rake.

require_relative "config/application"

Rails.application.load_tasks

namespace :locales do
  desc "compile i18n before compile"
  task build: :environment do
    system("yarn i18n:export")
  end
end

namespace :assets do
  desc "remove assets before compile"
  task clear_all: :environment do
    puts ">>>>>>>>> clear all assets "
    system("rm -rf public/assets")
  end
end

namespace :javascript do
  desc "Build your JavaScript bundle"
  task :only_build do
    unless system "yarn build"
      raise "jsbundling-rails: Command build failed, ensure yarn is installed and `yarn build` runs without errors"
    end
  end
end

if Rake::Task.task_defined?("assets:precompile")
  Rake::Task["javascript:build"].clear
  Rake::Task["assets:precompile"].enhance(["javascript:only_build"])
end

# Run yarn i18n:export prior to assets precompilation, so i18n json are available for use.
# Rake::Task['assets:precompile'].enhance [ 'locales:build' ]
# Rake::Task["assets:precompile"].enhance ["assets:clear_all"]
