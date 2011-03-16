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
   plan tests => 6;
}

my $output;
my $rows;
my $cnf = "/tmp/12345/my.sandbox.cnf";
my $cmd = "$trunk/mk-archiver/mk-archiver";

$sb->create_dbs($dbh, ['test']);
$sb->load_file('master', 'mk-archiver/t/samples/table1.sql');

# Test basic functionality with defaults
$output = output(
   sub { mk_archiver::main(qw(--where 1=1), "--source", "D=test,t=table_1,F=$cnf", qw(--purge)) },
);
is($output, '', 'Basic test run did not die');
$output = `mysql --defaults-file=$cnf -N -e "select count(*) from test.table_1"`;
is($output + 0, 0, 'Purged ok');

# Test basic functionality with --commit-each
$sb->load_file('master', 'mk-archiver/t/samples/table1.sql');
$output = output(
   sub { mk_archiver::main(qw(--where 1=1), "--source", "D=test,t=table_1,F=$cnf", qw(--commit-each --limit 1 --purge)) },
);
is($output, '', 'Commit-each did not die');
$output = `mysql --defaults-file=$cnf -N -e "select count(*) from test.table_1"`;
is($output + 0, 0, 'Purged ok with --commit-each');

# Archive only part of the table
$sb->load_file('master', 'mk-archiver/t/samples/table1.sql');
$output = output(
   sub { mk_archiver::main(qw(--where 1=1), "--source", "D=test,t=table_1,F=$cnf", qw(--where a<4 --purge)) },
);
is($output, '', 'No output for archiving only part of a table');
$output = `mysql --defaults-file=$cnf -N -e "select count(*) from test.table_1"`;
is($output + 0, 1, 'Purged some rows ok');

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($dbh);
exit;
