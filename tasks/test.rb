namespace :test do
  task :multi do
    sh 'multiruby -S rake clean test'
  end
end

Rake::TestTask.new :prototest do |t|
  %w[ ext lib ].each do |dir|
    t.libs << dir
  end

  t.test_files = FileList['test/test_*.rb']
  t.verbose = true
end

task :test => :build do
  Rake::Task[:prototest].invoke
end

task "test:pure" => PTEXT do
  ENV['PURERUBY'] = "1"
  Rake::Task[:prototest].invoke
end


