#!/usr/bin/env perl

BEGIN {
   die "The MAATKIT_WORKING_COPY environment variable is not set.  See http://code.google.com/p/maatkit/wiki/Testing"
      unless $ENV{MAATKIT_WORKING_COPY} && -d $ENV{MAATKIT_WORKING_COPY};
   unshift @INC, "$ENV{MAATKIT_WORKING_COPY}/common";
};

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use Test::More tests => 13;

use MaatkitTest;
shift @INC;  # These two shifts are required for tools that use base and
shift @INC;  # derived classes.  See mk-query-digest/t/101_slowlog_analyses.t
require "$trunk/mk-query-advisor/mk-query-advisor";

my @args = qw(--print-all --report-format full --group-by none --query);
my $query;

# #############################################################################
# Literals.
# #############################################################################

ok(
   no_diff(sub { mk_query_advisor::main(@args,
         'SELECT ip FROM tbl WHERE ip="127.0.0.1"') },
      'mk-query-advisor/t/samples/lit-001.txt',
   ),
   'LIT.001 "IP"'
);

ok(
   no_diff(sub { mk_query_advisor::main(@args,
         'SELECT c FROM tbl WHERE c < 2010-02-15') },
      'mk-query-advisor/t/samples/lit-002-01.txt',
   ),
   'LIT.002 YYYY-MM-DD'
);

ok(
   no_diff(sub { mk_query_advisor::main(@args,
         'SELECT c FROM tbl WHERE c=20100215') },
      'mk-query-advisor/t/samples/lit-002-02.txt',
   ),
   'LIT.002 YYYYMMDD'
);

# #############################################################################
# Table list.
# #############################################################################

ok(
   no_diff(sub { mk_query_advisor::main(@args,
         'SELECT * FROM tbl WHERE id=1') },
      'mk-query-advisor/t/samples/tbl-001-01.txt',
   ),
   'TBL.001 *'
);

ok(
   no_diff(sub { mk_query_advisor::main(@args,
         'SELECT tbl.* FROM tbl WHERE id=2') },
      'mk-query-advisor/t/samples/tbl-001-02.txt',
   ),
   'TBL.001 tbl.*'
);

ok(
   no_diff(sub { mk_query_advisor::main(@args,
         'SELECT tbl.* foo, bar FROM tbl WHERE id=1') },
      'mk-query-advisor/t/samples/tbl-002-01.txt',
   ),
   'TBL.002 tbl.* foo'
);

ok(
   no_diff(sub { mk_query_advisor::main(@args,
         'SELECT tbl.* AS foo, bar FROM tbl WHERE id=2') },
      'mk-query-advisor/t/samples/tbl-002-02.txt',
   ),
   'TBL.002 tbl.* AS foo'
);

# #############################################################################
# Query.
# #############################################################################

ok(
   no_diff(sub { mk_query_advisor::main(@args,
         'insert into foo values ("bar")') },
      'mk-query-advisor/t/samples/qry-001-01.txt',
   ),
   'QRY.001 INSERT'
);

ok(
   no_diff(sub { mk_query_advisor::main(@args,
         'replace into foo values ("bar")') },
      'mk-query-advisor/t/samples/qry-001-02.txt',
   ),
   'QRY.001 REPLACE'
);

# #############################################################################
# Subqueries.
# #############################################################################

ok(
   no_diff(sub { mk_query_advisor::main(@args,
         'select t from w where i=1 or i in (select * from j)') },
      'mk-query-advisor/t/samples/sub-001-01.txt',
   ),
   'SUB.001'
);


# #############################################################################
# JOIN stuff.
# #############################################################################

$query = "SELECT * FROM   `wibble_chapter`
   INNER JOIN `wibble_series` AS `wibble_chapter__series`
   ON `wibble_chapter`.`series_id` = `wibble_chapter__series`.`id`,
   `wibble_series`,
   `auth_user`
   WHERE  ( `wibble_chapter`.`chapnum` = 63.0
      AND `wibble_chapter`.`status` = 1
      AND `wibble_chapter__series`.`title` = 'bibble' )
      AND `wibble_chapter`.`series_id` = `wibble_series`.`id`
      AND `wibble_series`.`poster_id` = `auth_user`.`id`
      ORDER  BY `wibble_chapter`.`create_time` DESC
      LIMIT  1";

ok(
   no_diff(sub { mk_query_advisor::main(@args, $query) },
      'mk-query-advisor/t/samples/joi-001-002-01.txt',
   ),
   'JOI.001 and JOI.002'
);



# #############################################################################
# CLA.* rules
# #############################################################################

ok(
   no_diff(sub { mk_query_advisor::main(@args,
         'select id from tbl1 join tbl2 using (a) group by tbl1.id, tbl2.id') },
      'mk-query-advisor/t/samples/cla-006-01.txt',
   ),
   'CLA.001 and CLA.006'
);

ok(
   no_diff(sub { mk_query_advisor::main(@args,
         'select c1, c2 from t where i=1 order by c1 desc, c2 asc') },
      'mk-query-advisor/t/samples/cla-007-01.txt',
   ),
   'CLA.007'
);

# #############################################################################
# Done.
# #############################################################################
exit;
