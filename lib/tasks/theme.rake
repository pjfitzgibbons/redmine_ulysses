# frozen_string_literal: true

require_relative '../redmine_ulysses/theme'

namespace :redmine_ulysses do
  namespace :theme do
    desc 'Check a Ulysses theme file against the contract and for contrast. ' \
         'FILE defaults to public/ulysses/theme.css.'
    task :check, [:file] do |_task, args|
      file = args[:file] || File.join(Dir.pwd, 'public/ulysses/theme.css')
      abort "No theme file at #{file}" unless File.file?(file)

      errors = RedmineUlysses::Theme.check(File.read(file))
      if errors.empty?
        puts "#{file}: passes the Ulysses theme check"
      else
        abort(["#{file}: #{errors.size} problem(s)", *errors.map { |e| "  - #{e}" }].join("\n"))
      end
    end
  end
end
