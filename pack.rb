#
# racc/pack
#

require 'strscan/pack'
require 'amstd/pack'


environ( 'racc' ) do

  set :version, '1.3.8'

  set :dir, expand('~/r/racc')

  set :view_name, 'Racc'
  set :category,  'parser generator'
  set :format,    'ruby script, ruby extention'
  set :require,   'ruby(>=1.4), C compiler'
  set :license,   'LGPL'
  set :type,      'ruby'
  set :package,   'racc'
  set :instpath,  'racc'
  set :topfile,    nil

  set :raw, true


  set :bin, %w( racc )

  set :mainrb, %w(
    compiler.rb
    grammer.rb
    info.rb
    iset.rb
    output.rb
    parser.rb
    raccs.rb
    state.rb
    ucodep.rb
  )

  set :src, %w(
    build
  )
  set :genrb, %w( raccp.rb )

  set :rb, (g :mainrb) + (g :genrb)

  set :tool, %w(
    pack.rb
  )

  set :misc, %w(
    y2racc
    racc2y
  )

  set :text, %w(
    FILES
    BUGS.ja
    BUGS.en
  )

  set :extern_libs, %w( raccrt strscan amstd )


  def build
    upver a(g :src)
    chdir( g :dir ) do
      command './build &> er'
    end
  end


  def update
    upver a(g(:bin), g(:mainrb), g(:src))
    (e :raccrt).update
  end

  def all_sample
    Dir[ "#{a 'sample'}/*.y" ]
  end

  def set_files_etc( packdir )
    cp a(g :src), isdir( packdir, 'src' )
    cp all_sample, isdir( packdir, 'sample' )
    cp d(a('misc'), g(:misc)), isdir( packdir, 'misc' )
  end

  def raw
    super
    (e :raccrt).raw
  end

  def site
    super
    (e :raccrt).site
  end


  environ( 'raccrt' ) do

    set :dir, (e :racc).g(:dir)

    set :type,     'ruby'
    set :package,  'raccrt'
    set :instpath, 'racc'
    set :topfile,   nil

    set :rb, %w( parser.rb )

    set :intern_libs, %w( cparse )


    def update
      upver a(g :rb), (e :racc).g(:version)
      (e :cparse).update
    end

    def site
      cp_archive_site
    end

  end


  environ( 'cparse' ) do

    set :dir, expand('~/r/racc/cp')

    set :type,     'ext'
    set :package,  'raccrt'
    set :instpath, 'racc'
    set :topfile,   nil


    set :c, %w( cparse.c )
    set :etool, %w( MANIFEST extconf.rb )


    def update
      upver a(g :c), (e :racc).g(:version)
    end

    def set_files( packdir )
      bug!
    end

  end

end
