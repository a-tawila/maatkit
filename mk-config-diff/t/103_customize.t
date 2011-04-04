#!/usr/bin/env perl

BEGIN {
   die "The MAATKIT_WORKING_COPY environment variable is not set.  See http://code.google.com/p/maatkit/wiki/Testing"
      unless $ENV{MAATKIT_WORKING_COPY} && -d $ENV{MAATKIT_WORKING_COPY};
   unshift @INC, "$ENV{MAATKIT_WORKING_COPY}/common";
};

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use Test::More tests => 2;

use MaatkitTest;
require "$trunk/mk-config-diff/mk-config-diff";

my $cnf = '/tmp/12345/my.sandbox.cnf';
my $output;
my $retval;

# ############################################################################
# --ignore-variables
# ############################################################################

$output = output(
   sub { $retval = mk_config_diff::main(
      '/tmp/12345/my.sandbox.cnf',
      '/tmp/12346/my.sandbox.cnf',
   ) },
   stderr => 1,
);

like(
   $output,
   qr{port\s+12345\s+12346},
   "port is different"
);

$output = output(
   sub { $retval = mk_config_diff::main(
      '/tmp/12345/my.sandbox.cnf',
      '/tmp/12346/my.sandbox.cnf',
      '--ignore-variables', 'port',
   ) },
   stderr => 1,
);

like(
   $output,
   qr{port\s+12345\s+12346},
   "port is ignored"
);

# #############################################################################
# Done.
# #############################################################################
exit;
