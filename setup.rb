
require 'amstd/rbparams'
require 'amstd/inst'

class RACCinstaller < Installer

  def com_setup
    into_dir( 'bin' ) do
      add_rubypath 'racc'
    end
    setup_library 'racc'
    into_dir( 'strscan' ) do
      extconf
      make
    end
  end

  def com_install
    into_dir( 'bin' ) do
      install_bin 'racc'
    end
    install_library 'amstd'
    install_library 'racc'
    into_dir( 'strscan' ) do
      make_install
    end
  end

end

RACCinstaller.execute
