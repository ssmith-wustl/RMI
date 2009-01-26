package RMI::Server::ForkedPipes;

use strict;
use warnings;
use version;
our $VERSION = qv('0.1');

use base 'RMI::Server';

RMI::Node::_mk_ro_accessors(__PACKAGE__,'peer_pid');

=pod

=head1 NAME

RMI::Server::ForkedPipes - internal server for RMI::Client::ForkedPipes 

=head1 SYNOPSIS

This is used internally by RMI::Client::ForkedPipes.  The only difference
between this server and a generic RMI::Server is the peer_pid property
is set, to make other IPC easier.

$client->peer_pid eq $client->remote_eval('$$');

$server->peer_pid eq $server->remtoe_eval('$$');

=head1 DESCRIPTION

This subclass of RMI::Server is used by RMI::Client::ForkedPipes when it
forks a private server for itself.

=head1 SEE ALSO

B<RMI>, B<RMI::Client::ForkedPipes>, B<RMI::Server>

=cut
