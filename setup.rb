
require 'amstd/inst'

class RACCinstaller < Installer

  def com_setup
    setup_library 'racc'
  end

  def com_install
    chdir( 'bin' ) do
      add_rubypath 'racc'
      install 'racc', BINDIR, 0755, true
    end

    install_library 'amstd'
    install_library 'racc'
  end

end

RACCinstaller.execute
