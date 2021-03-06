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
   plan tests => 2;
}

my $output;
my @args = ('--sync-to-master', 'h=127.1,P=12346,u=msandbox,p=msandbox',
            qw(-d issue_375 --replicate issue_375.checksums --print));
my $mk_table_checksum = "$trunk/mk-table-checksum/mk-table-checksum F=/tmp/12345/my.sandbox.cnf -d issue_375 --chunk-size 20 --chunk-size-limit 0";

# #############################################################################
# Issue 996: might not chunk inside of mk-table-checksum's boundaries
# #############################################################################

# Re-using this table for this issue.  It has 100 pk rows.
$sb->load_file('master', 'mk-table-sync/t/samples/issue_375.sql');
wait_until(
   sub {
      my $row;
      eval {
         $row = $slave_dbh->selectrow_hashref("select * from issue_375.t where id=35");
      };
      return 1 if $row && $row->{foo} eq 'ai';
   },
);

# Make the tables differ.  These diff rows are all in chunk 1.
$slave_dbh->do("update issue_375.t set foo='foo' where id in (21, 25, 35)");
wait_until(
   sub {
      my $row;
      eval {
         $row = $slave_dbh->selectrow_hashref("select * from issue_375.t where id=35");
      };
      return 1 if $row && $row->{foo} eq 'foo';
   },
   0.5, 10,
);

# mk-table-checksum the table with 5 chunks of 20 rows.
$output = `$mk_table_checksum --replicate issue_375.checksums --create-replicate-table`;
sleep 1;

$output = `$mk_table_checksum --replicate issue_375.checksums --replicate-check 1`;
like(
   $output,
   qr/issue_375\s+t\s+2\s+0\s+1\s+`id` >= '21' AND `id` < '41'/,
   "Chunk checksum diff"
);

# Run mk-table-sync with the replicate table.  Chunk size here is relative
# to the mk-table-checksum ranges.  So we sub-chunk the 20 row ranges into
# 4 5-row sub-chunks.
my $file = "/tmp/mts-output.txt";
output(
   sub { mk_table_sync::main(@args, qw(--chunk-size 5 -v -v)) },
   file => $file,
);

# The output shows that the 20-row range was chunked into 4 5-row sub-chunks.
$output = `cat $file | grep 'AS chunk_num' | cut -d' ' -f3,4`;
is(
   $output,
"/*issue_375.t:1/5*/ 0
/*issue_375.t:1/5*/ 0
/*issue_375.t:2/5*/ 1
/*issue_375.t:2/5*/ 1
/*issue_375.t:3/5*/ 2
/*issue_375.t:3/5*/ 2
/*issue_375.t:4/5*/ 3
/*issue_375.t:4/5*/ 3
/*issue_375.t:5/5*/ 4
/*issue_375.t:5/5*/ 4
",
   "Chunks within chunk"
);

diag(`rm -rf $file >/dev/null`);

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($master_dbh);
exit;
