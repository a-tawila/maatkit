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
require "$trunk/mk-archiver/mk-archiver";

my $dp  = new DSNParser(opts=>$dsn_opts);
my $sb  = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $dbh = $sb->get_dbh_for('master');

if ( !$dbh ) {
   plan skip_all => 'Cannot connect to sandbox master';
}
else {
   plan tests => 2;
}

my $output;
my $rows;
my $cnf = "/tmp/12345/my.sandbox.cnf";
my $cmd = "$trunk/mk-archiver/mk-archiver";

$sb->create_dbs($dbh, ['test']);

# #############################################################################
# Issue 524: mk-archiver --no-delete --dry-run prints out DELETE statement
# #############################################################################
$sb->load_file('master', 'mk-archiver/t/samples/issue_131.sql');
$sb->load_file('master', 'mk-archiver/t/samples/issue_1166.sql');

$output = output(
   sub { mk_archiver::main(qw(--where 1=1 --dry-run --source),
      "F=$cnf,D=test,t=issue_131_src", qw(--dest t=issue_131_dst)) }
);
like(
   $output,
   qr/DELETE FROM `test`\.`issue_131_src` WHERE \(`id` = \?\)$/m,
   "No LIMIT 1 with unique index"
);

# With non-unique index LIMIT 1 should appear.

$output = output(
   sub { mk_archiver::main(qw(--where 1=1 --dry-run --source),
      "F=$cnf,D=test,t=issue_1166", "--purge") }
);
like(
   $output,
   qr/DELETE FROM `test`\.`issue_1166` WHERE \(`id` = \?\) LIMIT 1$/m,
   "LIMIT 1 with non-unique index"
);

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($dbh);
exit;
