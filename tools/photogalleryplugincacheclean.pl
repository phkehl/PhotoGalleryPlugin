#!/usr/bin/perl
####################################################################################################
#
# PhotoGalleryPlugin for Foswiki Bulk Attach Script
#
# Copyright (c) 2016 Philippe Kehl <phkehl at gmail dot com>
#
####################################################################################################
#
# This program is free software; you can redistribute it and/or modify it under the terms of the GNU
# General Public License as published by the Free Software Foundation; either version 2 of the
# License, or (at your option) any later version. For more details read LICENSE in the root of this
# distribution.
#
# This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without
# even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
#
# As per the GPL, removal of this notice is prohibited.
#
####################################################################################################

=pod

=encoding utf8

=head1 PhotoGalleryPlugin Cache Cleanup Script

=head2 Description

This scripts cleans up the PhotoGalleryPlugin's cache (in C<working/work_areas/PhotoGalleryPlugin>)
by expiring old data. Data can become obsolete by upgrades of the plugin (since the cache file
format depends on the plugin version), when attachments or topics are moved, renamed or deleted.

=head2 Usage

    photogalleryplugincleanup.pl [-q] [-v] [-m #days]

Where:

=over

=item * C<-v>: increases verbosity (adds debugging output on what exactly is done)

=item * C<-q>: decreases verbosity (suppresses summary output)

=item * C<-m #days>: sets the exipiration age threshold to C<#days> days (default 90).

=back

Note that the user executing the script must have write (delete) permissions to the
C<working/work_areas/PhotoGalleryPlugin> directory. The script will (try to) assert the correct
user.

=head2 Examples

Expire old cache files:

    photogalleryplugincleanup.pl

A possibly suitable system crontab entry:

    0 4 * * * www-data /path/to/foswiki/tools/photogalleryplugincleanup.pl -q

=cut

use strict;
use warnings;

# find setlib.cfg in ../bin
use FindBin;
use lib "$FindBin::Bin/../bin";

BEGIN
{
    $Foswiki::cfg{Engine} = 'Foswiki::Engine::CLI';
    require 'setlib.cfg';
}

use Time::HiRes      qw(time usleep sleep);
use Pod::Usage       qw();
use Data::Dumper     qw();
$Data::Dumper::Terse = 1;
$Data::Dumper::Sortkeys = 1;
use Foswiki          qw();


################################################################################
# parse command line

my %control =
(
    me        => $0,
    verbosity => 0,
    maxage    => 90,
);

do
{
    $control{me} =~ s{^.*/}{};
    my $comment = '';
    my $errors = 0;

    while (my $arg = shift(@ARGV))
    {
        TRACE("arg=$arg");
        if ($arg eq '-h')
        {
            Pod::Usage::pod2usage( { -exitval => 0, -verbose => 2, output => \*STDERR } );
        }
        elsif ($arg eq '-v') { $control{verbosity}    += 1; }
        elsif ($arg eq '-q') { $control{verbosity}    -= 1; }
        elsif ($arg eq '-m') { $control{maxage}        = int(shift(@ARGV)); }
        else
        {
            ERROR("Illegal argument '$arg'!");
            $errors++;
        }
    }

    DEBUG("verbosity=$control{verbosity} maxage=$control{maxage}")
      if ($control{verbosity});

    if ( $errors || ($control{maxage} < 1) )
    {
        PRINT("Try '$0 -h'.");
        exit(1);
    }

};


###############################################################################
# check plugin cache dir

my $workingDir = $Foswiki::cfg{WorkingDir};
unless ($workingDir)
{
    ERROR("Cannot determine Foswiki WorkingDir config!");
    exit(1);
}

DEBUG("workingDir=$workingDir");
PRINT("* All done.");


################################################################################
# funky functions

sub DEBUG
{
    return unless ($control{verbosity} > 0);
    _PRINT(\*STDERR, 'D', @_);
}
sub TRACE
{
    return unless ($control{verbosity} > 1);
    _PRINT(\*STDERR, 'T', @_);
}
sub ERROR
{
    _PRINT(\*STDERR, 'E', @_);
}
sub PRINT
{
    return if ($control{verbosity} < 0);
    _PRINT(\*STDOUT, 'P', @_);
}

sub _PRINT
{
    my ($h, $l, $f, @a) = @_;
    my %p = ( 'E' => 'ERROR', 'D' => 'DEBUG', 'T' => 'TRACE' );
    my $pp = $p{$l} ? "$control{me}($p{$l}): " : '';
    if (ref($f) || (index($f, '%') < 0))
    {
        unshift(@a, $f);
        $f = '%s';
    }
    @a = map { !defined $_ ? 'undef' : (ref($_) ? Data::Dumper::Dumper($_) : $_) } @a;
    print($h sprintf("$pp$f\n", @a));
}


1;
__END__
