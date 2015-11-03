require 'rake/rdoctask'

Rake::RDocTask.new(:docs) do |rd|
  rd.main = "README.en.rdoc"
  rd.rdoc_files.include(SPEC.files.find_all { |file_name|
    file_name =~ /^(bin|lib|ext)/ || file_name !~ /\//
  })

  title = "#{SPEC.name}-#{SPEC.version} Documentation"

  rd.options << "-t #{title}"
end
