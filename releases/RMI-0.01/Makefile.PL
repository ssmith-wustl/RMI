
use warnings FATAL => 'all';
use strict;
use inc::Module::Install;

name    'RMI';
license 'perl';
all_from 'lib/RMI.pm';

# prereqs
requires 'Carp';
requires 'IO::Socket';

# things the tests need
build_requires 'Test::More' => '0.62';

#tests('t/*.t t/*/*.t');

WriteAll();

