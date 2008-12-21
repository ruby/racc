namespace :test do
  task :multi do
    sh 'multiruby -S rake clean test'
  end
end

Rake::TestTask.new do |t|
  %w[ ext lib ].each do |dir|
    t.libs << dir
  end

  t.test_files = FileList['test/test_*.rb']
  t.verbose = true
end

Rake::Task[:test].prerequisites << :build
