Gem::Specification.new do |s|
    s.name        = 'rmi'
    s.version     = '0.11'
    s.date        = '2012-02-05'
    s.summary     = "cross-process/language transparent proxying"
    s.description = "cross-process/language transparent proxying"
    s.authors     = ["Scott Smith"]
    s.email       = 'sakoht@githubm.com'
    s.homepage    = 'http://www.flinkt.org/'
    s.files = %w[
        rmi.gemspec
        Changes
        INSTALL
        LICENSE
        MANIFEST
        README
        lib/rmi.rb
        lib/rmi/client.rb
        lib/rmi/client/forkedpipes.rb
        lib/rmi/client/tcp.rb
        lib/rmi/encoder/perl5e1.rb
        lib/rmi/node.rb
        lib/rmi/proxyobject.rb
        lib/rmi/requestresponder/perl5r1.rb
        lib/rmi/serializer/s1.rb
        lib/rmi/serializer/s2.rb
        lib/rmi/server.rb
        lib/rmi/server/forkedpipes.rb
        lib/rmi/server/tcp.rb
        tests/00_echo.t
        tests/01_basic.t
        tests/02_unblessed_refs.t
        tests/03_exceptions.t
        tests/04_use_remote.t
        tests/05_use_lib_remote.t
        tests/06_client_server_pairs.t
        tests/07_as_documented.t
        tests/08_wantarray.t
        tests/09_bind_variables.t
        tests/10_opts.t
        tests/11_dbi_special.t
        tests/12_remote_node.t
        tests/13_refcount.t
        tests/14_copy_results.t
    ]
    s.test_files = s.files.select {|path| path =~ /^tests\/.*.rb/}
end

