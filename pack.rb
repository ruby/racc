
require 'pack/my'
require '../strscan/pack'
require '../amstd/pack'


environ( 'racc' ) do

  set :dir, expand('~/r/racc')

  set :version, '1.0.0'

  set :bin, %w( racc )

  set :mainrb, %w(
    libracc.rb
    facade.rb
    raccs.rb
    register.rb
    rule.rb
    state.rb
    format.rb
  )

  set :src, %w(
    build
  )
  set :genrb, %w( raccp.rb )

  set :rb, (g :mainrb) + (g :genrb)

  set :tool, %w(
    pack.rb
    setup.rb
  )

  set :text, %w( FILES )

  set :sample, %w(
    calc.y
    calc2-ja.y
    compile.rb
  )


  def clean
    rm_f a(g :genrb), 'chk.rb'
  end

  def build
    upd a(g :src), 2, (g :version)
    chdir( g :dir ) do
      command './build &> er'
    end
  end


  def update
    untab a(g :tool), 2
    upd a(g(:mainrb) + g(:bin) + g(:src)), 2, (g :version)
    (e :raccrt).update
    untab all_sample, 2
  end

  def all_sample
    all_in a('sample'), /\.(y|rb)\z/
  end


  def set_files( packdir )
    set_files_main packdir
    set_files_doc packdir

    (e :raccrt).set_files packdir
    (e :amstd).set_files_main packdir
    (e :strscan).set_files_main packdir

    cp a('setup.rb'), packdir

    set_files_lgpl packdir

    cp a(g :src), isdir( packdir, 'src' )
    cp all_sample, isdir( packdir, 'sample' )
  end

  def set_files_main( packdir )
    cp a(g :bin), isdir( packdir, 'bin' )
    cp a(g :rb), isdir( packdir, 'racc' )
  end

  def raw
    super
    (e :raccrt).raw
  end

  def set_raw( packdir )
    set_files_main packdir
    set_files_doc packdir
    cp a('setup.rb'), packdir
  end


  environ( 'raccrt' ) do

    set :version, (e :racc).get(:version)

    set :dir, (e :racc).get(:dir)

    set :rb, %w( parser.rb scanner.rb )

    set :tool, %w(
      rtsetup.rb
      rtpack.rb
    )

    def update
      untab a(g :rb), 2
      untab a(g :tool), 2
      (e :cparse).update
    end

    def set_files( packdir )
      set_files_main packdir
      cp a(g :tool), packdir
    end

    def set_files_main( packdir )
      d = isdir( packdir + '/racc' )
      cp a(g :rb), d
      (e :cparse).set_files d
    end

    def set_raw( packdir )
      set_files_main packdir
      cp a('setup.rb'), packdir
    end

  end


  environ( 'cparse' ) do

    set :version, '0.4.2'

    set :dir, expand('~/r/racc/cp')

    set :c, %w( cparse.c )

    set :tool, %w( MANIFEST depend extconf.rb )


    def update
      upd a(g :c), 4, (e :version)
    end

    def set_files( packdir )
      set_files_main packdir
    end

    def set_files_main( packdir )
      d = isdir( packdir + '/cparse' )
      cp a(g :c), d
      cp a(g :tool), d
    end

  end

end
