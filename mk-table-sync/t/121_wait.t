#!/usr/bin/env perl

BEGIN {
   die "The MAATKIT_WORKING_COPY environment variable is not set.  See http://code.google.com/p/maatkit/wiki/Testing"
      unless $ENV{MAATKIT_WORKING_COPY} && -d $ENV{MAATKIT_WORKING_COPY};
   unshift @INC, "$ENV{MAATKIT_WORKING_COPY}/common";
};

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use Test::More;

use MaatkitTest;
use Sandbox;
require "$trunk/mk-table-sync/mk-table-sync";

my $dp = new DSNParser(opts=>$dsn_opts);
my $sb = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $master_dbh = $sb->get_dbh_for('master');
my $slave_dbh  = $sb->get_dbh_for('slave1');

if ( !$master_dbh ) {
   plan skip_all => 'Cannot connect to sandbox master';
}
elsif ( !$slave_dbh ) {
   plan skip_all => 'Cannot connect to sandbox slave';
}
else {
   plan tests => 4;
}

my $output;
my @args = ('--sync-to-master', 'h=127.1,P=12346,u=msandbox,p=msandbox', qw(--print -v));

$sb->load_file('master', 'mk-table-sync/t/samples/lag-slave.sql');
wait_until(
   sub {
      my $row;
      eval {
         $row = $slave_dbh->selectrow_hashref("select * from test.t2");
      };
      return 1 if $row && $row->{id};
   },
);

sub lag_slave {
   my $dbh = $sb->get_dbh_for('master');
   for (1..10) {
      $dbh->do("update test.t1 set i=sleep(3) limit 1");
   }
   $dbh->disconnect;
   return;
}

my $pid = fork();
if ( !$pid ) {
   # child
   lag_slave();
   exit;
}

# parent
sleep 4;  # give time slave to become lagged

my $lag = $slave_dbh->selectrow_hashref("show slave status");

if ( !$lag->{seconds_behind_master} ) {
   kill 15, $pid;
   waitpid ($pid, 0);
   die "Slave did not lag";
}

my $start = time;

$output = output(
   sub { mk_table_sync::main(@args, qw(-t test.t2)) },
);

my $t = time - $start;

like(
   $output,
   qr/Chunk\s+\S+\s+\S+\s+0\s+test\.t2/,
   "Synced table"
);

cmp_ok(
   $t,
   '>',
   1,
   "Sync waited $t seconds for master"
);

# Repeat the test with --wait 0 to test that the sync happens without delay.

$lag = $slave_dbh->selectrow_hashref("show slave status");

if ( !$lag->{seconds_behind_master} ) {
   kill 15, $pid;
   waitpid ($pid, 0);
   die "Slave is not lagged";
}

$start = time;

$output = output(
   sub { mk_table_sync::main(@args, qw(-t test.t2 --wait 0)) },
);

$t = time - $start;

like(
   $output,
   qr/Chunk\s+\S+\s+\S+\s+0\s+test\.t2/,
   "Synced table"
);

cmp_ok(
   $t,
   '<=',
   1,
   "Sync did not wait for master with --wait 0 ($t seconds)"
);

# #############################################################################
# Done.
# #############################################################################
kill 15, $pid;
waitpid ($pid, 0);
$sb->wipe_clean($master_dbh);
exit;
