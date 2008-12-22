class EmailTask
  def initialize language, readme, changelog
    @language   = language
    @readme     = readme
    @changelog  = changelog
    @languages = {
      :en => {
        :release  => 'release',
        :released => 'has been released',
      },
      :ja => {
        :release  => 'リリース',
        :released => 'はリリースしました',
      }
    }
    define_tasks
  end

  private
  def define_tasks
    namespace :email do
      task @language do
        subject = "#{SPEC.name} #{SPEC.version} #{@languages[@language][:release]}"
        title = "#{SPEC.name} #{SPEC.version} #{@languages[@language][:released]}!"
        readme = Hash[*(File.read(@readme).split(/^(=+ .*)$/)[1..-1])]
        description = readme[readme.keys.find { |x| x =~ /description/i }]
        description = description.split(/\n\n+/).find { |x|
          x.length > 0
        }.gsub(/^\s*/, '')
        urls = readme[readme.keys.find { |x| x =~ /#{SPEC.name}/i }]
        urls = urls.strip.gsub(/\*\s/, '').split(/\n/).map { |s| "* <#{s}>" }
        File.open("email.#{@language}.txt", "wb") { |file|
          file.puts(<<-eomail)
Subject: [ANN] #{subject}

#{title}

#{urls.join("\n")}

#{description}

Changes:

#{File.read(@changelog).split(/^(===.*)/)[1..2].join.strip.gsub(/=/, '#')}

#{urls.join("\n")}
eomail
        }
      end
    end
  end
end

EmailTask.new(:en, 'README.en.rdoc', 'doc/en/NEWS.en.rdoc')
EmailTask.new(:ja, 'README.ja.rdoc', 'doc/ja/NEWS.ja.rdoc')
