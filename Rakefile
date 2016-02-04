require 'rake/testtask'
require 'yard'

Rake::TestTask.new do |t|
  t.libs += %w(lib test)
  t.test_files = FileList['test/**/*_test.rb']
  t.verbose = true
end

YARD::Rake::YardocTask.new do |t|
  t.files = ['lib/**/*.rb']
  t.options = ['--markup=markdown']
end

task default: [:test, :yard]
