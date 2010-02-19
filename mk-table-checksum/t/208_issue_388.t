#!/usr/bin/env perl

BEGIN {
   die "The MAATKIT_TRUNK environment variable is not set.  See http://code.google.com/p/maatkit/wiki/Testing"
      unless $ENV{MAATKIT_TRUNK} && -d $ENV{MAATKIT_TRUNK};
   unshift @INC, "$ENV{MAATKIT_TRUNK}/common";
};

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use Test::More;

use MaatkitTest;
use Sandbox;
require "$trunk/mk-table-checksum/mk-table-checksum";

my $dp  = new DSNParser();
my $sb  = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $dbh = $sb->get_dbh_for('master');

if ( !$dbh ) {
   plan skip_all => 'Cannot connect to sandbox master';
}
else {
   plan tests => 2;
}

my $output;
my $cnf = '/tmp/12345/my.sandbox.cnf';

# #############################################################################
# Issue 388: mk-table-checksum crashes when column with comma in the name
# is used in a key
# #############################################################################

$sb->create_dbs($dbh, [qw(test)]);
$sb->load_file('master', 'common/t/samples/tables/issue-388.sql', 'test');

$dbh->do('insert into test.foo values (null, "john, smith")');

$output = `$trunk/mk-table-checksum/mk-table-checksum -F $cnf h=127.1 -d test 2>&1`;

unlike(
   $output,
   qr/Use of uninitialized value/,
   'No error (issue 388)'
);

like(
   $output,
   qr/test\s+foo\s+0\s+127.1\s+MyISAM\s+NULL\s+1906802343/,
   'Checksums the table (issue 388)'
);

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($dbh);
exit;