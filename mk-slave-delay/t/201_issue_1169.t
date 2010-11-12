#!/usr/bin/env perl

BEGIN {
   die "The MAATKIT_WORKING_COPY environment variable is not set.  See http://code.google.
com/p/maatkit/wiki/Testing"
      unless $ENV{MAATKIT_WORKING_COPY} && -d $ENV{MAATKIT_WORKING_COPY};
   unshift @INC, "$ENV{MAATKIT_WORKING_COPY}/common";

};

use strict;
use warnings FATAL => 'all';
use English qw( -no_match_vars );
use Test::More;

use MaatkitTest; 
use Sandbox;
require "$trunk/mk-slave-delay/mk-slave-delay";

my $dp  = DSNParser->new(opts => $dsn_opts);
my $sb  = Sandbox->new(basedir => '/tmp', DSNParser => $dp);
my $dbh = $sb->get_dbh_for('slave1');

if ( !$dbh ) {
   plan skip_all => 'Cannot connect to MySQL slave.';
}
elsif ( !@{$dbh->selectcol_arrayref('SHOW DATABASES LIKE "sakila"')} ) {
   plan skip_all => 'sakila db not loaded';
}
else {
   plan tests => 3;
}

my @args = ('-F', '/tmp/12346/my.sandbox.cnf');
my $output;

# #############################################################################
# Issue 1169: mk-slave-delay should complain if the SQL thread isn't running
# #############################################################################

$dbh->do('stop slave sql_thread');
my $row = $dbh->selectrow_hashref('show slave status');
is(
   $row->{slave_sql_running},
   "No",
   "Stopped SQL thread"
);

$output = output(
   sub { mk_slave_delay::main(@args, qw(--interval 1 --run-time 1)) },
);
like(
   $output,
   qr/SQL thread is not running/,
   "Won't run unless SQL thread is running"
);

$dbh->do('start slave sql_thread');
$row = $dbh->selectrow_hashref('show slave status');
is(
   $row->{slave_sql_running},
   "Yes",
   "Started SQL thread"
);

# #############################################################################
# Done.
# #############################################################################
exit;
