
require 'pack/my'
require 'amstd/pack'


environ( 'racc' ) do

  set :version, '1.1.6'

  set :dir, expand('~/r/racc')

  set :view_name, 'Racc'
  set :category,  'parser generator'
  set :format,    'ruby script, ruby extention'
  set :require,   'ruby(>=1.4), C compiler'
  set :license,   'lgpl'
  set :type,      'ruby'
  set :package,   'racc'
  set :instpath,  'racc'


  set :bin, %w( racc )

  set :mainrb, %w(
    libracc.rb
    facade.rb
    raccs.rb
    register.rb
    state.rb
    format.rb
    info.rb
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

  set :text, %w(
    FILES
    BUGS.ja
    BUGS.en
  )

  set :sample, %w(
    calc.y
    calc2-ja.y
    compile.rb
  )


  set :extern_libs, %w( raccrt amstd )


  def build
    upd a(g :src), 2, (g :version)
    chdir( g :dir ) do
      command './build &> er'
    end
  end


  def update
    upd a((g :bin), (g :mainrb), (g :src)), 2, (g :version)
    detab a(g :tool), 2
    detab all_sample, 2
    (e :raccrt).update
  end

  def all_sample
    all_in a('sample'), /\.(y|rb)\z/
  end


  # def set_files( packdir )

  # def set_files_main( packdir )

  def set_files_etc( packdir )
    cp a(g :src), isdir( packdir, 'src' )
    cp all_sample, isdir( packdir, 'sample' )
  end

  def raw
    super
    (e :raccrt).raw
  end

  # def set_raw( packdir )

  def site
    super
    (e :raccrt).site
  end


  environ( 'raccrt' ) do

    set :version, (e :racc).g(:version)

    set :dir, (e :racc).g(:dir)

    set :type, 'ruby'
    set :package, 'raccrt'
    set :instpath, 'racc'


    set :rb, %w( parser.rb )

    set :tool, %w(
      rtpack.rb
    )


    set :intern_libs, %w( cparse )


    def update
      untab a(g :rb), 2
      untab a(g :tool), 2
      (e :cparse).update
    end

    # def set_files( packdir )

    # def set_files_main( packdir )

    def set_files_etc( packdir )
      cp a(g :tool), packdir
    end

    # def set_raw( packdir )

    def site
      cp_archive_site
    end

  end


  environ( 'cparse' ) do

    set :version, '1.1.5'

    set :dir, expand('~/r/racc/cp')

    set :type, 'ext'
    set :package, 'raccrt'
    set :instpath, 'racc'


    set :c, %w( cparse.c )
    set :etool, %w( MANIFEST depend extconf.rb )


    def update
      upd a(g :c), 4, (e :version)
    end

    def set_files( packdir )
      bug!
    end

    # def set_files_main( packdir )

  end

end
