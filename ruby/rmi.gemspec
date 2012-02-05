Gem::Specification.new do |s|
    s.name        = 'rmi'
    s.version     = '0.11'
    s.date        = '2012-02-05'
    s.summary     = "cross-process/language transparent proxying"
    s.description = "cross-process/language transparent proxying"
    s.authors     = ["Scott Smith"]
    s.email       = 'sakoht@githubm.com'
    s.files       = ["lib/rmi.rb"]
    s.homepage    = 'http://www.flinkt.org/'
    s.files = %w[
        Changes
        INSTALL
        LICENSE
        MANIFEST
        README
        rmi.gemspec

        lib/RMI.rb
        lib/RMI/Node.rb
        lib/RMI/ProxyObject.rb
        lib/RMI/ProxyReference.rb
        
        lib/RMI/RequestResponder/Perl5r1.rb
        lib/RMI/Encoder/Perl5e1.rb
        lib/RMI/Serializer/S1.rb
        
        lib/RMI/Client.rb
        lib/RMI/Client/ForkedPipes.rb
        lib/RMI/Client/Tcp.rb
        lib/RMI/Serializer/S2.rb
        
        lib/RMI/Server.rb
        lib/RMI/Server/ForkedPipes.rb
        lib/RMI/Server/Tcp.rb
        
        t/00_echo.t
        t/01_basic.t
        t/02_unblessed_refs.t
        t/03_exceptions.t
        t/04_use_remote.t
        t/05_use_lib_remote.t
        t/06_client_server_pairs.t
        t/07_as_documented.t
        t/08_wantarray.t
        t/09_bind_variables.t
        t/10_opts.t
        t/11_dbi_special.t
        t/12_remote_node.t
        t/13_refcount.t
        t/14_copy_results.t
    ],
    s.test_files = s.files.select {|path| path =~ /^t\/.*.rb/}
end

<<EOS
use warnings FATAL => 'all';
use strict;
use inc::Module::Install;

name    'RMI';
license 'perl';
all_from 'lib/RMI.pm';

# prereqs
requires 'Carp';
requires 'IO::Socket';
requires 'version';

# things the tests need
build_requires 'Test::More' => '0.86';
build_requires 'App::Prove';

#tests('t/*.t t/*/*.t');

WriteAll();
EOS

