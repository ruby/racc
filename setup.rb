
require 'amstd/rbparams'
require 'amstd/inst'

class RACCinstaller < Installer

  def com_setup
    chdir( 'bin' ) do
      add_rubypath 'racc'
    end
    setup_library 'racc'
  end

  def com_install
    chdir( 'bin' ) do
      install 'racc', RubyParams::BINDIR, 0755
    end
    install_library 'amstd'
    install_library 'racc'
  end

end

RACCinstaller.execute
