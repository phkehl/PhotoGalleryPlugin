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

Common flags used by all or some operations:

    photogallerypluginattach.pl [-v] [-d] [-C] [-g] [-t|-T] [-r|-R] [-a|-A]
        Web.Topic [-c comment] file ... [@file]

Where:

=over

=item * C<-v> increases verbosity

=item * C<-d> dry run: don't actually do anything but show what would (likely) be done

=item * C<-C> creates the topic if it doesn't exist

=item * C<-g> adds the %PHOTOGALLERY% macro to the end of the topic

=item * C<-t> (default) and C<-T> set respectively don't set attachment date from EXIF exposure time
        (where available). This is global for all given files.

=item * C<-r> (default) and C<-R> rotate respectively don't rotate images based on EXIF orientation
        info (where available). This is global for all given files.

=item * C<-a> (default) and C<-A> don't attach respectively do attach existing attachments

=item * C<Web.Topic> (or C<Web/Topic>) specifies the topic to attach to

=item * C<-c comment> sets the attachment comment for all following C<file>s

=item * C<file> is the file to attach

=item * C<@file> interpolates each non-empty and non-comment line in the file as a command line
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
use lib "$FindBin::RealBin/../bin";

BEGIN
{
    $Foswiki::cfg{Engine} = 'Foswiki::Engine::CLI';
    require 'setlib.cfg';
}

use Time::HiRes qw(time usleep sleep);
use Pod::Usage;

use Foswiki;
use Foswiki::Plugins;

if ($Foswiki::Plugins::VERSION < 2.1)
{
    print(STDERR "Too old Plugins.pm version (need 2.1 or later, you have $Foswiki::Plugins::VERSION)!\n");
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
    addgallery    => 0,
    timetag       => 1,
    rotate        => 1,
    forceattach   => 0,
    webtopic      => '',
    files         => [],
);

do
{
    my $comment = '';
    my $errors = 0;

    while (my $arg = shift(@ARGV))
    {
        if ($arg eq '-h')
        {
            pod2usage( { -exitval => 0, -verbose => 2, output => \*STDERR } );
        }
        elsif ($arg eq '-v') { $control{verbosity}    += 1; }
        elsif ($arg eq '-d') { $control{dryrun}        = 1; }
        elsif ($arg eq '-C') { $control{createtopic}   = 1; }
        elsif ($arg eq '-g') { $control{addgallery}    = 1; }
        elsif ($arg eq '-r') { $control{rotate}        = 1; }
        elsif ($arg eq '-R') { $control{rotate}        = 0; }
        elsif ($arg eq '-t') { $control{timetag}       = 1; }
        elsif ($arg eq '-T') { $control{timetag}       = 0; }
        elsif ($arg eq '-a') { $control{forceattach}   = 1; }
        elsif ($arg eq '-A') { $control{forceattach}   = 0; }
        elsif ( ($arg =~ m/^(.+)[\/.](.+)$/) && !$control{webtopic} )
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
        # FIXME: implement @file.txt arguments interpolation
        else
        {
            print(STDERR "Illegal argument '$arg'!\n");
            $errors++;
        }
    }

    if ( $errors || ($#{$control{files}} < 0) || !$control{webtopic})
    {
        print(STDERR "Try '$0 -h'.\n");
        exit(1);
    }

};




__END__
use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/bin";

use Ffi::Debug ':all';
$Ffi::Debug::VERBOSITY += 1;
$Ffi::Debug::TIMESTAMP = 2;

use File::Temp;
use File::Copy;



###############################################################################
# get web.topic or web/topic

my ($webTopic, $web, $topic);
if ( ($webTopic = shift(@ARGV)) && ($webTopic =~ m@^([a-zA-Z]+)[/.]([a-zA-Z0-9]+)$@) )
{
    $web = $1; $topic = $2;
}
else
{
    die("Need a Web.Topic!");
}
DEBUG1("web=$web topic=$topic");


###############################################################################
# load foswiki engine

DEBUG1("new (engine=$Foswiki::cfg{Engine})");
my $foswiki = Foswiki->new('flip');

DEBUG1("webExists");
Foswiki::Func::webExists($web) || die("No such web: $web");
DEBUG1("topicExists");
Foswiki::Func::topicExists($web, $topic) || die("No such topic: $web.$topic");
my ($meta, $text) = Foswiki::Func::readTopic($web, $topic);
my %have = map { $_->{attachment}, 1 } $meta->find("FILEATTACHMENT");


# enable all PhotoSwipePlugin upload magic
my $q = Foswiki::Func::getRequestObject();
$q->param('exifrotateimage', 'on');
#$q->param('exifaddcomment', 'on');
$q->param('setexifdate', 'on');


###############################################################################
# attach files

my @attachments = ();

foreach my $file (@ARGV)
{
    if (! -f $file)
    {
        WARNING("Ignoring missing '$file'!");
        next;
    }

    if ($file =~ m@([^/]+)\.([^.]+)$@)
    {
        my ($base, $ext) = ($1, $2);

        # force lower-case file extension
        $ext = lc($ext) unless ($ext eq lc($ext));
        my $attachment = "$base.$ext";
        if ($have{$attachment})
        {
            PRINT("skipping, already have: $attachment ($file)");
            next;
        }

        PRINT("$attachment: $file");

        # copy to temp file
        (undef, my $tmpf) = File::Temp::tempfile( UNLINK => 1 );
        File::Copy::copy($file, $tmpf);
        my @s = stat($file);

        # attach
        Foswiki::Func::saveAttachment($web, $topic, $attachment,
            { file => $tmpf, filesize => -s $file,
              filedate => $s[10] || $s[9] || int(time()) }); # ctime, mtime, now, needs patch in Foswiki::Meta

        push(@attachments, $attachment);
    }
    else
    {
        WARNING("Ignoring fishy '$file'!");
    }
}

PRINT("attachments:", "@attachments");

#PRINT("movies:", map { '%FLVPLAYER{ "%ATTACHURL%/' . $_ . '" }%' } grep { $_ =~ m/\.flv$/ } @attachments);

#PRINT("./makealbum.pl $web/$topic @attachments");

1;
__END__
