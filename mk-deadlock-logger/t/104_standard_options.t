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
require "$trunk/mk-deadlock-logger/mk-deadlock-logger";

my $dp   = new DSNParser(opts=>$dsn_opts);
my $sb   = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $dbh1 = $sb->get_dbh_for('master');

if ( !$dbh1 ) {
   plan skip_all => 'Cannot connect to sandbox master';
}
else {
   plan tests => 9;
}

my $output;
my $cnf = "/tmp/12345/my.sandbox.cnf";
my $cmd = "$trunk/mk-deadlock-logger/mk-deadlock-logger -F $cnf h=127.1";

$sb->wipe_clean($dbh1);
$sb->create_dbs($dbh1, ['test']);

# #############################################################################
# Issue 248: Add --user, --pass, --host, etc to all tools
# #############################################################################

# Test that source DSN inherits from --user, etc.
$output = `$trunk/mk-deadlock-logger/mk-deadlock-logger h=127.1,D=test,u=msandbox,p=msandbox --clear-deadlocks test.make_deadlock --port 12345 2>&1`;
unlike(
   $output,
   qr/failed/,
   'Source DSN inherits from standard connection options (issue 248)'
);

# #########################################################################
# Issue 391: Add --pid option to all scripts
# #########################################################################
`touch /tmp/mk-script.pid`;
$output = `$cmd --clear-deadlocks test.make_deadlock --port 12345 --pid /tmp/mk-script.pid 2>&1`;
like(
   $output,
   qr{PID file /tmp/mk-script.pid already exists},
   'Dies if PID file already exists (--pid without --daemonize) (issue 391)'
);
`rm -rf /tmp/mk-script.pid`;

# #############################################################################
# Check daemonization
# #############################################################################
my $deadlocks_tbl = load_file('mk-deadlock-logger/t/deadlocks_tbl.sql');
$dbh1->do('USE test');
$dbh1->do('DROP TABLE IF EXISTS deadlocks');
$dbh1->do("$deadlocks_tbl");

`$cmd --dest D=test,t=deadlocks --daemonize --run-time 1s --interval 1s --pid /tmp/mk-deadlock-logger.pid 1>/dev/null 2>/dev/null`;
$output = `ps -eaf | grep '$cmd \-\-dest '`;
like($output, qr/$cmd/, 'It lives daemonized');
ok(-f '/tmp/mk-deadlock-logger.pid', 'PID file created');

my ($pid) = $output =~ /\s+(\d+)\s+/;
$output = `cat /tmp/mk-deadlock-logger.pid`;
is($output, $pid, 'PID file has correct PID');

# Kill it
sleep 2;
ok(! -f '/tmp/mk-deadlock-logger.pid', 'PID file removed');

# Check that it won't run if the PID file already exists (issue 383).
diag(`touch /tmp/mk-deadlock-logger.pid`);
ok(
   -f '/tmp/mk-deadlock-logger.pid',
   'PID file already exists'
);

$output = `$cmd --dest D=test,t=deadlocks --daemonize --run-time 1s --interval 1s --pid /tmp/mk-deadlock-logger.pid 2>&1`;
like(
   $output,
   qr/PID file .+ already exists/,
   'Does not run if PID file already exists'
);

$output = `ps -eaf | grep 'mk-deadlock-logger \-\-dest '`;
unlike(
   $output,
   qr/$cmd/,
   'It does not lived daemonized'
);

diag(`rm -rf /tmp/mk-deadlock-logger.pid`);

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($dbh1);
exit;
