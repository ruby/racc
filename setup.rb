
require 'amstd/inst'

class RACCinstaller < Installer

  def com_setup
  end

  def com_install
    lib_install( 'racc' ) do |rb_to, so_to|
      add_rubypath 'racc'
      install 'racc', BINDIR, 0755, true
      install_rb rb_to
      each_dir do |ext|
        make_install_so so_to
      end
    end

    install_library 'amstd'
  end

end

RACCinstaller.execute
