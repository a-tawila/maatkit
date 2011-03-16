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
   plan tests => 3;
}

my $output;
my $rows;
my $cnf = "/tmp/12345/my.sandbox.cnf";

$sb->create_dbs($dbh, ['test']);

# #############################################################################
# Issue 1166: Don't LIMIT 1 for unique indexes 
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
   "No LIMIT 1 with unique index (issue 1166)"
);

# With non-unique index LIMIT 1 should appear.

$output = output(
   sub { mk_archiver::main(qw(--where 1=1 --dry-run --source),
      "F=$cnf,D=test,t=issue_1166", "--purge") }
);
like(
   $output,
   qr/DELETE FROM `test`\.`issue_1166` WHERE \(`id` = \?\) LIMIT 1$/m,
   "LIMIT 1 with non-unique index (issue 1166)"
);


# #############################################################################
# This issue is related:
# Issue 1170: Allow bulk delete without LIMIT
# #############################################################################
$sb->load_file('master', 'mk-archiver/t/samples/issue_131.sql');

$output = output(
   sub { mk_archiver::main(qw(--where 1=1 --dry-run --source),
      "F=$cnf,D=test,t=issue_131_src", qw(--bulk-delete --purge),
      qw(--no-bulk-delete-limit --limit 3)) }
);
like(
   $output,
   qr/DELETE FROM `test`\.`issue_131_src` WHERE \(\(\(`id` >= \?\)\)\) AND \(\(\(`id` <= \?\)\)\) AND \(1=1\)$/m,
   "No LIMIT with bulk delete (issue 1170)"
);

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($dbh);
exit;
