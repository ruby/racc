
require 'amstd/inst'

class RACCRTinstaller < Installer

  def com_setup
    setup_library 'amstd'
    setup_library 'racc'
  end

  def com_install
    install_library 'amstd'
    install_library 'racc'
  end

end

RACCRTinstaller.execute
