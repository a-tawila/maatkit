# This program is copyright 2010 Percona Inc.
# Feedback and improvements are welcome.
#
# THIS PROGRAM IS PROVIDED "AS IS" AND WITHOUT ANY EXPRESS OR IMPLIED
# WARRANTIES, INCLUDING, WITHOUT LIMITATION, THE IMPLIED WARRANTIES OF
# MERCHANTIBILITY AND FITNESS FOR A PARTICULAR PURPOSE.
#
# This program is free software; you can redistribute it and/or modify it under
# the terms of the GNU General Public License as published by the Free Software
# Foundation, version 2; OR the Perl Artistic License.  On UNIX and similar
# systems, you can issue `man perlgpl' or `man perlartistic' to read these
# licenses.
#
# You should have received a copy of the GNU General Public License along with
# this program; if not, write to the Free Software Foundation, Inc., 59 Temple
# Place, Suite 330, Boston, MA  02111-1307  USA.
# ###########################################################################
# MySQLConfigComparer package $Revision$
# ###########################################################################
package MySQLConfigComparer;

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use Data::Dumper;
$Data::Dumper::Indent    = 1;
$Data::Dumper::Sortkeys  = 1;
$Data::Dumper::Quotekeys = 0;

use constant MKDEBUG => $ENV{MKDEBUG} || 0;

# Alternate values because offline/config my-var=ON is shown
# online as my_var=TRUE.
my %alt_val_for = (
   ON    => 1,
   YES   => 1,
   TRUE  => 1,
   OFF   => 0,
   NO    => 0,
   FALSE => 0,
   ''    => 0,
);

# These vars don't interest us so we ignore them.
my %ignore_vars = (
   date_format     => 1,
   datetime_format => 1,
   time_format     => 1,
);

# Special equality tests for certain vars that have varying
# values that are actually equal, like ON==1, ''=OFF, etc.
my %eq_for = (
   ft_stopword_file          => sub { return _veq(@_, '(built-in)', 0); },

   basedir                   => sub { return _patheq(@_);               },
   language                  => sub { return _patheq(@_);               },

   log_bin                   => sub { return _eqifon(@_);               },
   log_slow_queries          => sub { return _eqifon(@_);               },

   general_log_file          => sub { return _eqifnoconf(@_);           },
   innodb_data_file_path     => sub { return _eqifnoconf(@_);           },
   innodb_log_group_home_dir => sub { return _eqifnoconf(@_);           },
   log_error                 => sub { return _eqifnoconf(@_);           },
   open_files_limit          => sub { return _eqifnoconf(@_);           },
   slow_query_log_file       => sub { return _eqifnoconf(@_);           },
   tmpdir                    => sub { return _eqifnoconf(@_);           },
   binlog_format             => sub { return _eqifnoconf(@_);           },

   long_query_time           => sub { return $_[0] == $_[1] ? 1 : 0;    },

   datadir                   => sub { return _eqdatadir(@_);            },
);

sub new {
   my ( $class, %args ) = @_;
   my $self = {
   };
   return bless $self, $class;
}

# Takes an arrayref of MySQLConfig objects and compares the first to the others.
# Returns an arrayref of hashrefs of variables that differ, like:
#   {
#      var  => max_connections,
#      vals => [ 100, 50 ],
#   },
# The value for each differing var is an arrayref of values corresponding
# to the given configs.  So $configs[N] = $differing_var->[N].  Only vars
# in the first config are compared, so if $configs[0] has var "foo" but
# $configs[1] does not, then the var is skipped.  Similarly, if $configs[1]
# has var "bar" but $configs[0] does not, then the var is not compared.
# Called missing() to discover which vars are missing in the configs.
sub diff {
   my ( $self, %args ) = @_;
   my @required_args = qw(configs);
   foreach my $arg( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ($config_objs) = @args{@required_args};

   my @diffs;
   return @diffs if @$config_objs < 2;  # nothing to compare
   MKDEBUG && _d('diff configs:', Dumper($config_objs));

   my $configs  = [ map { $_->get_config() } @$config_objs ];
   my $versions = [ map { $_->version() }    @$config_objs ];

   # Get list of vars that exist in all configs (intersection of their keys).
   my @vars = grep { !$ignore_vars{$_} } $self->key_intersect($configs);

   # Make a list of values from each config for all the common vars.  So,
   #   %vals = {
   #     var1 => [ config0-var1-val, config1-var1-val ],
   #     var2 => [ config0-var2-val, config1-var2-val ],
   #   }
   my %vals = map {
      my $var  = $_;
      my $vals = [
         map {
            my $config = $_;
            my $val    = defined $config->{$var} ? $config->{$var} : '';
            $val       = $alt_val_for{$val} if exists $alt_val_for{$val};
            $val;
         } @$configs 
      ];
      $var => $vals;
   } @vars;

   VAR:
   foreach my $var ( sort keys %vals ) {
      my $vals     = $vals{$var};
      my $last_val = scalar @$vals - 1;

      eval {
         # Compare config0 val to other configs' val.
         # Stop when a difference is found.
         VAL:
         for my $i ( 1..$last_val ) {
            # First try straight string equality comparison.  If the vals
            # are equal, stop.  If not, try a special eq_for comparison.
            if ( $vals->[0] ne $vals->[$i] ) {
               if (    !$eq_for{$var}
                    || !$eq_for{$var}->($vals->[0], $vals->[$i], $versions) ) {
                  push @diffs, {
                     var  => $var,
                     vals => [ map { $_->{$var} } @$configs ],  # original vals
                  };
                  last VAL;
               }
            }
         } # VAL
      };
      if ( $EVAL_ERROR ) {
         my $vals = join(', ', map { defined $_ ? $_ : 'undef' } @$vals);
         warn "Comparing $var values ($vals) caused an error: $EVAL_ERROR";
      }
   } # VAR

   return @diffs;
}

sub missing {
   my ( $self, %args ) = @_;
   my @required_args = qw(configs);
   foreach my $arg( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ($config_objs) = @args{@required_args};

   my @missing;
   return @missing if @$config_objs < 2;  # nothing to compare
   MKDEBUG && _d('missing configs:', Dumper(\@$config_objs));

   my @configs = map { $_->get_config() } @$config_objs;

   # Get all unique vars and how many times each exists.
   my %vars;
   map { $vars{$_}++ } map { keys %{$configs[$_]} } 0..$#configs;

   # If a var exists less than the number of configs then it is
   # missing from at least one of the configs.
   my $n_configs = scalar @configs;
   foreach my $var ( keys %vars ) {
      if ( $vars{$var} < $n_configs ) {
         push @missing, {
            var     => $var,
            missing => [ map { exists $_->{$var} ? 0 : 1 } @configs ],
         };
      }
   }

   return @missing;
}

# True if x is val1 or val2 and y is val1 or val2.
sub _veq { 
   my ( $x, $y, $versions, $val1, $val2 ) = @_;
   return 1 if ( ($x eq $val1 || $x eq $val2) && ($y eq $val1 || $y eq $val2) );
   return 0;
}

# True if paths are equal; adds trailing / to x or y if missing.
sub _patheq {
   my ( $x, $y ) = @_;
   $x .= '/' if $x !~ m/\/$/;
   $y .= '/' if $y !~ m/\/$/;
   return $x eq $y;
}

# True if x=1 (alt val for "ON") and y is true (any value), or vice-versa.
# This is for cases like log-bin=file (offline) == log_bin=ON (offline).
sub _eqifon { 
   my ( $x, $y ) = @_;
   return 1 if ( ($x && $x eq '1' ) && $y );
   return 1 if ( ($y && $y eq '1' ) && $x );
   return 0;
}

# True if offline value not set/configured (so online vals is
# some built-in default).
sub _eqifnoconf {
   my ( $online_val, $conf_val ) = @_;
   return $conf_val == 0 ? 1 : 0;
}

sub _eqdatadir {
   my ( $online_val, $conf_val, $versions ) = @_;
   if ( ($versions->[0] || '') gt '5.1.0' && (($conf_val || '') eq '.') ) {
      MKDEBUG && _d('MySQL 5.1 datadir conf val bug;',
         'online val:', $online_val, 'offline val:', $conf_val);
      return 1;
   }
   return ($online_val || '') eq ($conf_val || '') ? 1 : 0;
}

# Given an arrayref of hashes, returns an array of keys that
# are the intersection of all the hashes' keys.  Example:
#   my $foo = { foo=>1, nit=>1   };
#   my $bar = { bar=>2, bla=>'', };
#   my $zap = { zap=>3, foo=>2,  };
#   my @a   = ( $foo, $bar, $zap );
# key_intersect(\@a) return ['foo'].
sub key_intersect {
   my ( $self, $hashes ) = @_;
   my %keys  = map { $_ => 1 } keys %{$hashes->[0]};
   my $n_hashes = (scalar @$hashes) - 1;
   my @isect = grep { $keys{$_} } map { keys %{$hashes->[$_]} } 1..$n_hashes;
   return @isect;
}

sub _d {
   my ($package, undef, $line) = caller 0;
   @_ = map { (my $temp = $_) =~ s/\n/\n# /g; $temp; }
        map { defined $_ ? $_ : 'undef' }
        @_;
   print STDERR "# $package:$line $PID ", join(' ', @_), "\n";
}

1;

# ###########################################################################
# End MySQLConfigComparer package
# ###########################################################################
