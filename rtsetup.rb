#
# racc runtime library setup script
#

require 'amstd/inst'

class RACCRTinstaller < Installer

  def com_setup
    setup_library 'racc'
    setup_library 'amstd'
  end

  def com_install
    install_library 'amstd'
    install_library 'racc'
  end

end

RACCRTinstaller.execute
