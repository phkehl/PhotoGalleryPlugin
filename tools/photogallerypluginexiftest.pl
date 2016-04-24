#!/usr/bin/perl
#
# Fixes missing EXIF CreateDate by guessing time from the filename.
# Background: Somehow I lost the EXIF data on some files but luckily the filename contained date and time.
#

use strict;
use warnings;

use POSIX;
use Image::ExifTool;
use Data::Dumper;
$Data::Dumper::Terse = 1;
$Data::Dumper::Sortkeys = 1;

my $file = shift(@ARGV);
my @exifAttrs = qw(CreateDate DateTimeOriginal FileModifyDate
                   Make Model ExposureTime UserComment
                   ISO FocalLength ApertureValue ImageWidth ImageHeight
                   GPSLatitude GPSLongitude GPSAltitude);
my %exifOpts = ( DateFormat => '%s', CoordFormat => '%.9f');

my $fh;
open($fh, '<', $file);
seek($fh, 0, SEEK_SET);
my $exif = Image::ExifTool::ImageInfo($fh, \@exifAttrs, \%exifOpts);
close($fh);

print(Dumper($exif));

