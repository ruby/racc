require 'rake/rdoctask'

Rake::RDocTask.new(:docs) do |rd|
  rd.main = "README.en"
  rd.rdoc_files.include(SPEC.files)

  title = "#{SPEC.name}-#{SPEC.version} Documentation"

  rd.options << "-t #{title}"
end
