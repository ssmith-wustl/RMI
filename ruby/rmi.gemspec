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
        lib/rmi/client/forked-pipes.rb
        lib/rmi/client/tcp.rb
        lib/rmi/encoder/perl5e1.rb
        lib/rmi/node.rb
        lib/rmi/proxyobject.rb
        lib/rmi/requestresponder/perl5r1.rb
        lib/rmi/serializer/s1.rb
        lib/rmi/serializer/s2.rb
        lib/rmi/server.rb
        lib/rmi/server/forked-pipes.rb
        lib/rmi/server/tcp.rb
        test/test-00-echo.rb
        test/01_basic.t
        test/02_unblessed_refs.t
        test/03_exceptions.t
        test/04_use_remote.t
        test/05_use_lib_remote.t
        test/06_client_server_pairs.t
        test/07_as_documented.t
        test/08_wantarray.t
        test/09_bind_variables.t
        test/10_opts.t
        test/11_dbi_special.t
        test/12_remote_node.t
        test/13_refcount.t
        test/14_copy_results.t
    ]
    s.test_files = s.files.select {|path| path =~ /^test\/test-.*.rb/}
end

