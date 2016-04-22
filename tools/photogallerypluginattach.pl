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

=head1 PhotoGalleryPlugin Bulk Attachment Script

=head2 Description

This command line tool attaches photos to topics. It is a companion script to the
System.PhotoGalleryPlugin. It can attach an number of photos (or, in fact, any file) to topics. It
needs to run on the server where Foswiki is installed as the user Foswiki is running as (typically,
www-data or so.

=head2 Usage

    photogallerypluginattach.pl [-v] [-d] [-C] [-g] [-t|-T] [-r|-R] [-a|-A] [-u user]
        Web.Topic [-c comment] file ... [@file]

Where:

=over

=item * C<-v>: increases verbosity

=item * C<-d>: dry run: don't actually do anything but show what would (likely) be done

=item * C<-C>: creates the topic if it doesn't exist

=item * C<-g>: adds the %PHOTOGALLERY% macro to the end of the topic

=item * C<-t> (default) and C<-T>: set respectively don't set attachment date from EXIF exposure time
        (where available). This is global for all given files.

=item * C<-r> (default) and C<-R>: rotate respectively don't rotate images based on EXIF orientation
        info (where available). This is global for all given files.

=item * C<-a> (default) and C<-A>: don't attach respectively do attach existing attachments

=item * C<-u wikiname>: uses the given user (WikiName, the default is typically "WikiGuest" and won't work)

=item * C<Web.Topic> (or C<Web/Topic>): specifies the topic to attach to

=item * C<-c comment>: sets the attachment comment for all following C<file>s

=item * C<file>: is a file to attach

=item * C<@file>: interpolates each non-empty and non-comment line in the file as a command line
        argument (to overcome maximum command line lengths)

=back

=head2 Examples

Attach photos to I<MyPhotos> in the I<Main> web:

    photogallerypluginattach.pl Main.MyPhotos /path/to/IMG_*.JPG

Set same comment for all photos:

    photogallerypluginattach.pl Main.MyPhotos -c "happy holidays" /path/to/IMG_*.JPG

Set individual comments:

    photogallerypluginattach.pl Main.MyPhotos -c "sunset" IMG_0001.JPG -c "sunrise" IMG_0002.JPG"

Read (some) command line arguments from file:

    photogallerypluginattach.pl Main.MyPhotos @fotos.txt

Where C<fotos.txt> could look like this:

   # first photo
   -c "sunset" IMG_0001.JPG

   # second photo
   -c "sunrise" IMG_0002.JPG"


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
use Error            qw(:try);

use Foswiki          qw();
use Foswiki::Plugins qw();
use Foswiki::Time    qw();
use Foswiki::Func    qw();
use Foswiki::AccessControlException qw();
use Foswiki::Plugins::PhotoGalleryPlugin qw();

if ($Foswiki::Plugins::VERSION < 2.1)
{
    ERROR("Too old Plugins.pm version (need 2.1 or later, you have $Foswiki::Plugins::VERSION)!");
    exit(1);
}


################################################################################
# parse command line

my %control =
(
    verbosity     => 0,
    dryrun        => 0,
    createtopic   => 0,
    webtopic      => 0,
    wikiname      => $Foswiki::cfg{DefaultUserWikiName},
    user          => '',
    addgallery    => 0,
    timestamp     => 1,
    rotate        => 1,
    forceattach   => 0,
    webtopic      => '',
    files         => [],
    me            => $0,
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
        elsif ($arg eq '-d') { $control{dryrun}        = 1; }
        elsif ($arg eq '-C') { $control{createtopic}   = 1; }
        elsif ($arg eq '-g') { $control{addgallery}    = 1; }
        elsif ($arg eq '-r') { $control{rotate}        = 1; }
        elsif ($arg eq '-R') { $control{rotate}        = 0; }
        elsif ($arg eq '-t') { $control{timestamp}     = 1; }
        elsif ($arg eq '-T') { $control{timestamp}     = 0; }
        elsif ($arg eq '-a') { $control{forceattach}   = 0; }
        elsif ($arg eq '-A') { $control{forceattach}   = 1; }
        elsif ($arg eq '-u') { $control{wikiname}      = shift(@ARGV); }
        elsif ( ($arg =~ m/^($Foswiki::regex{webNameRegex})[\/.]($Foswiki::regex{topicNameRegex})$/)
                && !$control{webtopic} )
        {
            $control{webtopic} = $arg;
        }
        elsif ($arg eq '-c')
        {
            $comment = shift(@ARGV);
        }
        elsif (-f $arg)
        {
            push(@{$control{files}}, { file => $arg, comment => $comment });
        }
        elsif ( ($arg =~ m/^@(.+)$/) && -f $1 )
        {
            my @a = ();
            open(F, '<', $1) || die($!);
            while (my $line = <F>)
            {
                next if ($line =~ m/^(\s*#|\s*$)/);
                $line =~ s/^\s*//;
                $line =~ s/\s*$//;
                foreach (grep { $_ !~ m/^\s*$/ } split(/(".*?"|\S+)/, $line)) # yeah, really nice.. :-/
                {
                    push(@a, $_);
                }
            }
            close(F);
            unshift(@ARGV, @a);
        }
        else
        {
            ERROR("Illegal argument '$arg'!");
            $errors++;
        }
    }

    DEBUG("verbosity=$control{verbosity} dryrun=$control{dryrun} createtopic=$control{createtopic} "
          . "webtopic=$control{webtopic} addgallery=$control{addgallery} timestamp=$control{timestamp} "
          . "rotate=$control{rotate} forceattach=$control{forceattach} webtopic=$control{webtopic} "
          . "wikiname=$control{wikiname}")
      if ($control{verbosity});

    if ( $errors || ($#{$control{files}} < 0) || !$control{webtopic})
    {
        PRINT("Try '$0 -h'.");
        exit(1);
    }

    if ($control{verbosity} > 1)
    {
        $Foswiki::Plugins::PhotoGalleryPlugin::DEBUG = 1;
    }

};


###############################################################################
# load foswiki engine, check user and login

my $foswiki = Foswiki->new() || die();
my $wikiname = $control{wikiname};
my $user = Foswiki::Func::getCanonicalUserID($wikiname);
unless ($wikiname && $user)
{
    ERROR("Failed setting user (wikiname=%s, user=%s)!", $wikiname, $user);
    exit(1);
}
DEBUG("wikiname=$wikiname --> user=$user");

# login
# SMELL: Is this the correct usage of the API?
$foswiki = Foswiki->new($user) || die();
unless (Foswiki::Func::getWikiName() eq $wikiname)
{
    ERROR("Failed loggin in as $wikiname/$user!");
    exit(1);
}


###############################################################################
# check target topic, maybe create it

my ($web, $topic) = Foswiki::Func::normalizeWebTopicName(undef, $control{webtopic});
DEBUG("webtopic=%s --> web=%s topic=%s", $control{webtopic}, $web, $topic);

if (!Foswiki::Func::webExists($web) ||
    !Foswiki::Func::topicExists($web, $topic))
{
    if ($control{createtopic})
    {
        PRINT("* Creating empty topic $web.$topic.");
        try { Foswiki::Func::saveTopic($web, $topic, undef, '', {}) }
        catch Error with
        {
            ERROR($_[0]->stringify());
            exit(1);
        };
    }
    else
    {
        ERROR("Topic $web.$topic does not exist!");
        exit(1);
    }
}

if (!Foswiki::Func::checkAccessPermission('CHANGE', $wikiname, undef, $topic, $web))
{
    ERROR("$wikiname has no permissions to attach to $web.$topic!");
    exit(1);
}

PRINT("* Loading %s.%s.", $topic, $web);
my ($meta, $text) = Foswiki::Func::readTopic($web, $topic);
unless ($meta && defined $text)
{
    ERROR("Failed loading $web.$topic!");
    exit(1);
}
my %have = map { $_->{attachment}, $_ } $meta->find("FILEATTACHMENT");
DEBUG("$web.$topic has %i attachments.", scalar keys %have);


###############################################################################
# attach

# enable/disable PhotoGalleryPlugin upload handler stuff
my $q = Foswiki::Func::getRequestObject();
$q->param('exifrotateimage', $control{rotate} ? 'on' : 'off');
$q->param('setexifdate', $control{timestamp} ? 'on' : 'off');
my @attached = ();
foreach (@{$control{files}})
{
    my ($file, $comment) = ($_->{file}, $_->{comment});
    my $attachment = $file;
    $attachment =~ s{^.*/}{};

    if ($have{$attachment} && !$control{forceattach})
    {
        PRINT("Skipping '%s' ($web.$topic already has $attachment).", $file);
        next;
    }

    PRINT("* Attaching '%s' (%s).", $file, $attachment);
    Foswiki::Func::saveAttachment($web, $topic, $attachment,
        { file => $file, comment => $comment, filesize => (-s $file) });
    PRINT("  Done.");
    push(@attached, $attachment);
}

# add %PHOTOGALLERY% to topic?
if ( $control{addgallery} && ($#attached > -1) )
{
    PRINT('* Adding %s macro for %i photos.', '%PHOTOGALLERY%', $#attached + 1);
    ($meta, $text) = Foswiki::Func::readTopic($web, $topic);
    $text .= "\n\n";
    $text .= "---++ Gallery Created "
      . Foswiki::Time::formatTime(int(time()),
            $Foswiki::cfg{Plugins}{PhotoGalleryPlugin}{DateFmtDefault}) . "\n\n";
    $text .= '%PHOTOGALLERY{ "' . join(',', @attached) . '" }%' . "\n";
    $text .= "\n\n";
    Foswiki::Func::saveTopic($web, $topic, $meta, $text, { forcenewrevision => 1 });
}

PRINT("* All done.");


################################################################################
# funky functions

sub DEBUG
{
    return unless ($control{verbosity});
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
