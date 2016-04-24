#!/usr/bin/perl
#
# Fixes missing EXIF CreateDate by guessing time from the filename.
# Background: Somehow I lost the EXIF data on some files but luckily the filename contained date and time.
#
# There is little to no error handling and it may seriously mess up your data!
#
# YMMV
#
# Usage: photogallerypluginfixexifexposuretime.pl WikiName Web.Topic

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

use POSIX;
use File::Temp      qw();
use Data::Dumper;
$Data::Dumper::Terse = 1;
$Data::Dumper::Sortkeys = 1;
use Image::ExifTool qw();
use Foswiki         qw();
use Foswiki::Func   qw();
use Foswiki::Meta   qw();

my ($wikiName, $webTopic) = @ARGV;

my $foswiki = Foswiki->new() || die();

my $user = Foswiki::Func::getCanonicalUserID($wikiName) || die();
my ($web, $topic);

if ( $webTopic && ($webTopic =~ m/^($Foswiki::regex{webNameRegex})[\/.]($Foswiki::regex{topicNameRegex})$/) )
{
    ($web, $topic) = Foswiki::Func::normalizeWebTopicName(undef, $webTopic);
}

die('Wrong parameters!') if (!$web || !$topic || !$user);

print("Processing $web.$topic as $wikiName/$user.\n");
$foswiki = Foswiki->new($user) || die();
(Foswiki::Func::getWikiName() eq $wikiName) || die("Illegal WikiName!");

Foswiki::Func::checkAccessPermission('CHANGE', $wikiName, undef, $topic, $web)
  || die('No CHANGE permission');

my ($meta, $text) = Foswiki::Func::readTopic($web, $topic);

my $q = Foswiki::Func::getRequestObject();
#$q->param('exifrotateimage', $control{rotate} ? 'on' : 'off');
$q->param('setexifdate', 'on');

foreach my $att ($meta->find("FILEATTACHMENT"))
{
    next unless ($att->{attachment} =~ m/jpe?g$/i);

    my $aFh = $meta->openAttachment($att->{attachment}, '<');
    my $exif = Image::ExifTool::ImageInfo($aFh, [ 'CreateDate' ], { DateFormat => '%s' });
    if (!$exif->{CreateDate})
    {
        printf("%-40s %-20s ", $att->{attachment}, 'missing CreateDate!');
        my $guessed = 0;
        if ($att->{attachment} =~ m/IMG_(20\d\d)(\d\d)(\d\d)_(\d\d)(\d\d)(\d\d)\.jpe?g/i)
        {
            my ($ye, $mo, $da, $ho, $mi, $se) = ($1, $2, $3, $4, $5, $6);
            $guessed = "$ye:$mo:$da $ho:$mi:$se";
        }
        if ($guessed)
        {
            print("$guessed (guessed)\n");
            seek($aFh, 0, SEEK_SET);
            my (undef, $tFile) = File::Temp::tempfile();
            File::Copy::copy($aFh, $tFile);
            #printf("  %s %s %s\n", $tFile, -s $tFile, $guessed);
            my $exifTool = Image::ExifTool->new();
            $exifTool->ImageInfo($tFile);
            $exifTool->SetNewValue(CreateDate => $guessed);
            $exifTool->WriteInfo($tFile);
            #printf("  %s %s\n", $tFile, -s $tFile);
            Foswiki::Func::saveAttachment($web, $topic, $att->{attachment},
                { comment => $att->{comment}, file => $tFile, filesize => (-s $tFile) });
            unlink($tFile);
        }
        else
        {
            print("?????\n");
        }

    }
    else
    {
        printf("%-40s %-20s %s\n", $att->{attachment}, 'OK', strftime('%c', gmtime($exif->{CreateDate})));
    }
}


__END__
