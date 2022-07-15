####################################################################################################
#
# PhotoGalleryPlugin for Foswiki
#
# Copyright (c) 2016-2018 Philippe Kehl <phkehl at gmail dot com>
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

package Foswiki::Plugins::PhotoGalleryPlugin;

use strict;
use warnings;

=begin TML

---+ package Foswiki::Plugins::PhotoGalleryPlugin

---++ Description

This module implements the System.PhotoGalleryPlugin. See System.VarPHOTOGALLERY for the user
API. See source code for developer details.

---++ Issues, Todos, Ideas

   * Handle (validation, Foswiki:Development/HowToIntegrateWithRequestValidation) session
     timeout. Re-authenticate? Display useful warning.
   * More Make/Model EXIF cleanup (NIKON CORPORATION / NIKON D4, ...) (maybe Google has a list of common names?)
   * Add more EXIF tags. Need sample images.
   * Nicer "processing animation" (pub/System/ConfigurePlugin/loader-bars.gif maybe?)
   * Document and assert exact HTML5 browser requirement.
   * Create inline JSON data for PSWP items instead of creating them in the browser.
     How much does it really save? Does it work with the livequery stuff?
   * Work around the timezone mess. Foswiki::Time::formatTime() isn't going to help. DateTime will work
     (but add a dependency). Time::Piece perhaps? http://stackoverflow.com/questions/19526930/how-can-i-convert-a-date-time-and-time-zone-correctly
   * Add configurable link to coordinates and perhaps also an icon on the thumbnail.
     (default, e.g.: https://tools.wmflabs.org/geohack/geohack.php?params=48.143889_N_17.109722_E)
   * Create a MapsPlugin or so to display GPX tracks, photos, ...
   * Show gear (tools menu) in fullscreen.
   * Allow sorting by regex named group.
   * Implement rotate actions for PNG, GIF, SVG.
   * Multiple zoom levels (mouse zoom?) in photoswipe. Is it possible?
   * Better SVG size calculation.
   * Allow images from multiple topics.
   * use contenteditable=true instead of input fields
   * ...

=cut

####################################################################################################

use Foswiki::Func;
use Foswiki::Plugins;
use Foswiki::Sandbox;
use Foswiki::Time;

use POSIX;
use JSON;
use Error ':try';
use Image::ExifTool;
use File::Copy;
use File::Touch;
use Digest::MD5;
use Storable;
use Image::Epeg;
use List::Util;


####################################################################################################

our $VERSION           = '1.17-dev';
our $RELEASE           = '9 Jan 2021';
our $SHORTDESCRIPTION  = 'A gallery plugin for JPEG photos from digital cameras (and PNG, GIF and SVG graphics)';
our $NO_PREFS_IN_TOPIC = 1;
our $CREATED_AUTHOR    = 'Philippe Kehl';
our $CREATED_YEAR      = '2018';

####################################################################################################

our $DEBUG = ($VERSION =~ m/-dev/ ? 1 : 0);

# per-request (page rendered) data,
# used to handle multiple galleries in the same topic, and other features
# SMELL: Isn't there a Foswiki facility for storing per-request data?
our $RV;


####################################################################################################

sub initPlugin
{
    my ( $topic, $web, $user, $installWeb ) = @_;

    # reset per-request variables
    $RV = { };

    # we need version 2.1 or later of the plugins API
    if ( $Foswiki::Plugins::VERSION < 2.1)
    {
        _warning('Too old Plugins.pm version (need 2.1 or later)!');
        return 0;
    }

    # debugging helpers
    if ($DEBUG)
    {
        eval "require Time::HiRes; require Data::Dumper";
        if ($@)
        {
            $DEBUG = 0;
            _warning('Cannot load debug helpers.');
        }
        else
        {
            $RV->{t0} = Time::HiRes::time();
        }
    }

    # register the "%PHOTOGALLERY%" macro handler
    Foswiki::Func::registerTagHandler('PHOTOGALLERY', \&doPHOTOGALLERY);

    # register the "admin" REST handler (verb)
    Foswiki::Func::registerRESTHandler('admin', \&doRestAdmin,
          authenticate => 1, validate => 1, http_allow => 'POST',
          description => 'System.PhotoGalleryPlugin REST handler for admin actions');

    # register the "thumb" REST handler (verb)
    Foswiki::Func::registerRESTHandler('thumb', \&doRestThumb,
          authenticate => 0, validate => 0, http_allow => 'GET,POST',
          description => 'System.PhotoGalleryPlugin REST handler for thumbnail generation');

    #_debug('init');
    return 1;
}

sub finishPlugin
{
    $RV = {};

    return;
}


####################################################################################################

sub doPHOTOGALLERY
{
    my ($session, $params, $topic, $web, $topicObject) = @_;

    _initPluginStuff();

    # we render TML (and HTML)
    my $tml = '';


    ##### get and check parameters #################################################################

    $params->{web}       ||= $web;
    $params->{topic}     ||= $topic;
    ($params->{web}, $params->{topic})
                           = Foswiki::Func::normalizeWebTopicName($params->{web}, $params->{topic});
    $params->{images}    ||= $params->{_DEFAULT} || '/.+\.jpe?g$/';
    $params->{size}        = _checkRange($params->{size},
                             $Foswiki::cfg{Plugins}{PhotoGalleryPlugin}{SizeDefault}, 50, 500);
    $params->{quality}     = _checkRange($params->{quality},
                             $Foswiki::cfg{Plugins}{PhotoGalleryPlugin}{QualityDefault}, 1, 100);
    $params->{uidelay}     = _checkRange($params->{uidelay}, 4.0, 0, 86400);
    $params->{ssdelay}     = _checkRange($params->{ssdelay}, 5.0, 1.0, 86400);
    $params->{sort}        = _checkOptions($params->{sort}, 'date', 'date', '-date', 'name', '-name', 'off');
    $params->{lazy}        = _checkBool($params->{lazy} // $Foswiki::cfg{Plugins}{PhotoGalleryPlugin}{LazyDefault});
    $params->{caption}   //= $Foswiki::cfg{Plugins}{PhotoGalleryPlugin}{CaptFmtDefault};
    $params->{thumbcap}  //= $params->{caption};
    $params->{zoomcap}   //= $params->{caption};
    $params->{remaining}   = _checkBool($params->{remaining} || 'off');
    $params->{quiet}       = _checkBool($params->{quiet}     || 'off');
    $params->{unique}      = _checkBool($params->{unique}    || 'on' );
    $params->{admin}       = _checkOptions($params->{admin},
                             $Foswiki::cfg{Plugins}{PhotoGalleryPlugin}{AdminDefault}, 'on', 'off', 'user');
    $params->{dayheading}  = _checkOffOrRange($params->{dayheading}, '', 0, 0, 24);
    $params->{headingfmt}||= $Foswiki::cfg{Plugins}{PhotoGalleryPlugin}{HeadingFmtDefault};
    $params->{width}       = _checkRange($params->{width}, 0, 0, 1000);
    $params->{float}       = _checkOptions($params->{float}, 'none', 'left', 'right');
    $params->{random}      = _checkRange($params->{random}, 0, 0, 1000);

    my $wikiName = Foswiki::Func::getWikiName();
    my $user = Foswiki::Func::getCanonicalUserID($wikiName);

    # unique id per %PHOTOGALLERY% per topic
    $RV->{uid}++;

    my $debugStr = "doPHOTOGALLERY($web.$topic/$RV->{uid})";
    _debug($debugStr, "$params->{web}.$params->{topic}", $params->{images}, "size=$params->{size}",
           "sort=$params->{sort}", "quiet=$params->{quiet}", "unique=$params->{unique}",
           "remaining=$params->{remaining}", "admin=$params->{admin}", "wikiName=$wikiName",
           "user=$user", "dayheading=$params->{dayheading}", "width=$params->{width}", "align=$params->{align}",
           "random=$params->{random}", "caption=$params->{caption}",
           "thumbcap=" . ($params->{thumbcap} eq $params->{caption} ? '<ditto>' : $params->{thumbcap}),
           "zoomcap=" . ($params->{zoomcap} eq $params->{caption} ? '<ditto>' : $params->{zoomcap}),
           "lazy=" . $params->{lazy});
    #_debug($params->stringify());

    # check if all required jquery plugins are available and active
    if (my $missing = join(', ', grep { !$Foswiki::cfg{JQueryPlugin}{Plugins}{$_}{Enabled} }
        qw(Debug UI UI::Tooltip UI::Button UI::Autocomplete BlockUI PNotify ScrollTo)))
    {
        return _wtf("Required %SYSTEMWEB%.JQueryPlugins are disabled: <literal>$missing</literal>!");
    }

    if (!Foswiki::Func::topicExists($params->{web}, $params->{topic}))
    {
        return _wtf("Topic $params->{web}.$params->{topic} does not exist!");
    }

    if (!Foswiki::Func::checkAccessPermission('VIEW',
             $wikiName, undef, $params->{topic}, $params->{web}))
    {
        return _wtf("No permissions to view $params->{web}.$params->{topic}!");
    }
    my $mayChange = Foswiki::Func::checkAccessPermission('CHANGE',
             $wikiName, undef, $params->{topic}, $params->{web}) ? 1 : 0;


    ##### select images from attachments ###########################################################

    # get list of all attachments
    my ($meta, $text) = Foswiki::Func::readTopic($params->{web}, $params->{topic});
    unless ($meta)
    {
        return _wtf("Cannot read meta data from topic '$params->{web}.$params->{topic}'!");
    }
    my @attachments = $meta->find("FILEATTACHMENT");

    # limit to supported image types (
    @attachments = grep { $_->{name} =~ m/\.(jpe?g|png|gif|svg)/i } @attachments;

    # filter list of attachments...
    my @selected = ();
    foreach my $selection (split(/\s*[,\s]+\s*/, $params->{images}))
    {
        # ...by "/regex/"
        if ($selection =~ m{^/(.+)/$})
        {
            my $regex = $1;

            # test regex, and abort if it didn't compile
            eval { "dummy" =~ m/$regex/i };
            if ($@)
            {
                my $err = "$@";
                # ...Unmatched ( in regex; marked by <-- HERE in m/.+\.( <-- HERE ...
                $err = ($err =~ m{<-- HERE in (.+) <-- HERE}) ? $1 : 'unknown problem';
                return _wtf('%SYSTEMWEB%.RegularExpression error in <code>\'' . _esc_attr($regex)
                  . '\'</code> (here: <code>' . _esc_attr(substr($err, 1, -1))
                  . '<b style="color: red;">' . _esc_attr(substr($err, -1)) . '</b>'
                  . '</code>)!');
            }
            else
            {
                push(@selected, grep { $_->{name} =~ m/$regex/i } @attachments);
            }
        }
        # ...by "name..name" (lexical) or "name--name" (date) range
        elsif ($selection =~ m{^(.+)(\.\.|--)(.+)$})
        {
            my ($n1, $s, $n2, $in) = ($1, $2, $3, 0);
            my @cand = ();
            if ($s eq '..')
            {
                @cand = sort { lc($a->{name}) cmp lc($b->{name}) } @attachments;
            }
            else
            {
                @cand = sort { $a->{date} <=> $b->{date} } @attachments;
            }
            push(@selected, grep
            {
                if    ($_->{name} eq $n1) { $in = 1; }
                elsif ($_->{name} eq $n2) { $in = 2; }
                elsif ($in == 2)          { $in = 0; }
                $in
            } @cand);
            #_debug("$debugStr attachments: [$n1] .. [$n2]" . join(' ', map { $_->{name} } @attachments));
        }
        # ... an attachment name
        else
        {
            push(@selected, grep { $_->{name} eq $selection } @attachments);
        }
    }
    @attachments = @selected;
    @selected = ();

    # remove duplicates?
    if ($params->{unique})
    {
        my %seen = ();
        my $nAtt = $#attachments + 1;
        @attachments = grep { my $s = $seen{$_}; $seen{$_}++; !$s } @attachments;

        _debug("$debugStr remove " . ($#attachments + 1 - $nAtt) . " duplicates");
    }

    # filter-out already shown images?
    if ($params->{remaining})
    {
        @attachments = grep { !$RV->{shown}->{$_->{name}} } @attachments;
    }

    # sort by date or name?
    if    ($params->{sort} eq 'date')
    {
        @attachments = sort { $a->{date} <=> $b->{date} } @attachments;
    }
    elsif ($params->{sort} eq '-date')
    {
        @attachments = reverse sort { $a->{date} <=> $b->{date} } @attachments;
    }
    elsif ($params->{sort} eq 'name')
    {
        @attachments = sort { lc($a->{name}) cmp lc($b->{name}) } @attachments;
    }
    elsif ($params->{sort} eq '-name')
    {
        @attachments = reverse sort { lc($a->{name}) cmp lc($b->{name}) } @attachments;
    }
    elsif ($params->{sort} eq 'random')
    {
        @attachments = List::Util::shuffle(@attachments);
    }

    # random pick?
    if ($params->{random})
    {
        my @shuffled = List::Util::shuffle(@attachments);
        my $maxIx = $params->{random} > ($#shuffled + 1) ? $#shuffled : $params->{random} - 1;
        _debug('rand=' . $params->{random} . ' maxIx=' . $maxIx);
        @attachments = @shuffled[0..$maxIx];
    }

    # any images left?
    if ($#attachments < 0)
    {
        if ($params->{quiet})
        {
            return '';
        }
        else
        {
            return _wtf("No " . ($params->{remaining} ? 'remaining ' : '')
                       . "attached images found in $params->{web}.$params->{topic} for '$params->{images}'!");
        }
    }
    #_debug($debugStr . ' ' . ($#attachments + 1) . ' attachments selected:', map { $_->{name} } @attachments);
    #_debug(@attachments);


    ##### get image information for the selected attachments #######################################

    my @images = ();
    for (my $ix = 0; $ix <= $#attachments; $ix++)
    {
        my $att = $attachments[$ix];
        # debug progress if there are many attachments to process
        if ( ($#attachments > 20) && ((($ix + 1) % 20) == 0) )
        {
            _debug(sprintf('%s getImageInfo %03i/%03i', $debugStr, $ix + 1, $#attachments + 1));
        }

        my $info = _getImageInfo($meta, $att);
        next unless ($info);

        # photo number and total number of photos, not cached
        $info->{n} = $ix + 1;
        $info->{N} = $#attachments + 1;

        # calculate thumbnail size
        my $img = {};
        my ($tr, $tw, $th) = _getThumbDims($info->{ImageWidth}, $info->{ImageHeight}, $params->{size});
        $img->{name}      = $att->{name};
        $img->{imgUrl}    = Foswiki::Func::getPubUrlPath($params->{web}, $params->{topic}, $att->{name});
        $img->{imgWidth}  = $info->{ImageWidth};
        $img->{imgHeight} = $info->{ImageHeight};
        $img->{zoomcap}   = _makeCaption($params->{zoomcap},  $info, $att);
        $img->{thumbcap}  = _makeCaption($params->{thumbcap}, $info, $att);

        # Thumbnail URL is to the REST service to generate the thumbnail on demand
        if ($params->{lazy})
        {
            $img->{thumbUrl} = Foswiki::Func::getScriptUrlPath('PhotoGalleryPlugin', 'thumb', 'rest',
               topic => "$params->{web}.$params->{topic}", name => $att->{name}, quality => $params->{quality},
               uid => ($att->{pguid} || 0), ver => $att->{version}, width => $tw, height => $th);
        }
        # Generate thumbnail now and place it in the pub directory
        else
        {
            $img->{thumbUrl} = genPubThumb($meta, $att->{name}, $params->{quality}, $tw, $th,
                ($att->{pguid} || 0), $att->{version});
        }

        $img->{thumbWidth}  = $tw;
        $img->{thumbHeight} = $th;
        $img->{attTs}     = $att->{date} || 0;
        $img->{exifTs}    = $info->{CreateDate} || 0;
        $img->{wikiName}  = $info->{WikiName} || '';

        # calculate the day this photo belongs to
        $img->{day} = 0;
        my $timestamp = $info->{CreateDate} || $att->{date} || 0;
        if ( ($params->{dayheading} ne '') && ($timestamp > 86400) )
        {
            my ($hour, $minute);
            if ($Foswiki::cfg{DisplayTimeValues} eq 'servertime')
            {
                ($hour, $minute) = (localtime($timestamp))[2,1];
            }
            else
            {
                ($hour, $minute) = (gmtime($timestamp))[2,1];
            }
            my $hourMinute = $hour + ($minute / 60);
            $img->{day} = $hourMinute < $params->{dayheading} ? $timestamp - 86400 : $timestamp;
            $img->{day} = (int($img->{day} / 86400) * 86400) + 43200;
        }

        # add to list of images to render into the gallery, remember which images we've seen
        push(@images, $img);
        $RV->{shown}->{$att->{name}}++;
    }

    #_debug("using", \@images);
    if ($#images < 0)
    {
        return _wtf("No usable images found in $params->{web}.$params->{topic} for '$params->{images}'!");
    }


    # stuff output only once per request / topic
    unless ($RV->{jsCss})
    {
        # JQueryPlugins CSS and JS (N.B. keep in sync with check-for-enabled list above)
        $tml .= '%JQREQUIRE{"ui::tooltip,ui::tooltip,scrollto"}%';
        my @cssDeps = qw(JQUERYPLUGIN::UI::TOOLTIP);
        my @jsDeps  = qw(JQUERYPLUGIN::FOSWIKI::PREFERENCES);
        if ($params->{admin})
        {
            $tml .= '%JQREQUIRE{ "blockui,pnotify,ui::autocomplete,button" }%';
            push(@jsDeps,  qw(JQUERYPLUGIN::BLOCKUI JQUERYPLUGIN::PNOTIFY
                              JQUERYPLUGIN::UI::AUTOCOMPLETE JQUERYPLUGIN::BUTTON
                              JavascriptFiles/strikeone JavascriptFiles/foswikiPref));
            push(@cssDeps, qw(JQUERYPLUGIN::THEME JQUERYPLUGIN::BLOCKUI JQUERYPLUGIN::PNOTIFY
                              JQUERYPLUGIN::BUTTON) )
        }

        # our own CSS and JS
        my $ext = $DEBUG ? '' : '.compressed';
        Foswiki::Func::addToZone('head', 'PHOTOSWIPE',
            '<link rel="stylesheet" href="%PUBURLPATH%/%SYSTEMWEB%/PhotoGalleryPlugin/photoswipe' . $ext .'.css" type="text/css" media="all" />' .
            '<link rel="stylesheet" href="%PUBURLPATH%/%SYSTEMWEB%/PhotoGalleryPlugin/default-skin' . $ext .'.css" type="text/css" media="all" />');
        Foswiki::Func::addToZone('head', 'PHOTOGALLERYPLUGIN',
            '<link rel="stylesheet" href="%PUBURLPATH%/%SYSTEMWEB%/PhotoGalleryPlugin/photogalleryplugin' . $ext .'.css" type="text/css" media="all" />',
            join(',', @cssDeps, 'PHOTOSWIPE'));
        Foswiki::Func::addToZone('script', 'PHOTOSWIPE',
            '<script type="text/javascript" src="%PUBURLPATH%/%SYSTEMWEB%/PhotoGalleryPlugin/photoswipe' . $ext .'.js"></script>' .
            '<script type="text/javascript" src="%PUBURLPATH%/%SYSTEMWEB%/PhotoGalleryPlugin/photoswipe-ui-default' . $ext .'.js"/></script>');
        Foswiki::Func::addToZone('script', 'PHOTOGALLERYPLUGIN',
            '<script type="text/javascript" src="%PUBURLPATH%/%SYSTEMWEB%/PhotoGalleryPlugin/photogalleryplugin' . $ext .'.js"></script>',
            join(',', @jsDeps, 'PHOTOSWIPE'));

        # global plugin parameters we need in photogalleryplugin.js, and the validation nonce
        $tml .= '<dirtyarea><div id="photoGalleryGlobals" data-nonce="?%NONCE%" data-debug="'
          . ($DEBUG ? 'true' : 'false') . '"></div></dirtyarea>';

        # don't do that again
        $RV->{jsCss} = 1;
    }

    # work out where to handle the align/width params
    my $wrapperStyle = '';
    my $wrapperClass = '';
    my $galleryStyle = '';
    # centred (non floating) gallery of specific width
    if ($params->{width} && ($params->{float} eq 'none'))
    {
        $galleryStyle = 'width: ' . ($params->{width} * (5 + 1 + 5 + $params->{size} + 5 + 1 + 5)) . 'px;';
    }
    # floating (left or right) gallery of specific width
    elsif ($params->{width})
    {
        $wrapperStyle = 'width: ' . ($params->{width} * (5 + 1 + 5 + $params->{size} + 5 + 1 + 5)) . 'px;';
        $wrapperClass = "pg-float-$params->{float}";
    }
    # automatic width (and implicit centering)
    else
    {
        $wrapperClass = "pg-auto-width";
    }

    # wrapper <div>
    $tml .= sprintf('<div id="photoGallery%i" data-uid="%s" data-web="%s" data-topic="%s" data-uidelay="%i" data-ssdelay="%i" '
                    . 'class="photoGallery '. $wrapperClass .'" style="' . $wrapperStyle . '">',
                    $RV->{uid}, $RV->{uid}, $params->{web}, $params->{topic}, int($params->{uidelay} * 1e3), int($params->{ssdelay} * 1e3));
    # render gallery HTML
    my $prevDayheading = 0;
    $tml .= '<div class="gallery jqUITooltip" data-delay="0" data-position="bottom" data-arrow="true" data-duration="0" '
      . 'style="' . $galleryStyle . '">';
    for (my $ix = 0; $ix <= $#images; $ix++)
    {
        my $img = $images[$ix];
        #_debug("img=%s", $img);

        # add headings if enabled
        if ( ($params->{dayheading} ne '') && ($img->{day} > $prevDayheading) )
        {
            $prevDayheading = $img->{day};
            my $h = Foswiki::Time::formatTime($img->{day}, $params->{headingfmt});
            $h = Foswiki::expandStandardEscapes($h);
            $tml .= $h;
        }

        #$tml .= '<div class="frame" style="width: ' . $img->{thumbWidth}. 'px; height: ' . $img->{thumbHeight} . 'px;">';
        $tml .= '<div class="frame" data-name="<literal>' . $img->{name} . '</literal>">';
        $tml .=   '<div class="crop" style="width: ' . $params->{size}. 'px; height: ' . $params->{size} . 'px;">';
        $tml .=     '<a class="img" data-ix="' . $ix . '" data-w="' . $img->{imgWidth} . '" data-h="' . $img->{imgHeight} . '" href="' . $img->{imgUrl} . '">';
        $tml .=       '<img class="thumb" src="' . $img->{thumbUrl} . '" width="' . $img->{thumbWidth} . '" height="' . $img->{thumbHeight} . '" '
                     . 'style="min-width: ' . $params->{size}. 'px; min-height: ' . $params->{size} . 'px;"/>';
        $tml .=     '</a>';
        $tml .=   '</div>'; # crop
        if ( ( _checkBool($params->{admin}) && $mayChange                      ) ||
             ( ($params->{admin} eq 'user') && ($wikiName eq $img->{wikiName}) ) )
        {
            $tml .=   '<a class="admin" data-ix="' . $ix . '"'
              . ' data-tsaction="' . ($img->{exifTs} && ($img->{exifTs} != $img->{attTs}) ? 'true' : 'false') . '"'
              . ' data-rotaction="' . ($img->{name} =~ m{\.jpe?g}i ? 'true' : 'false') . '"'
              . '>%ICON{gear}%</a>' if ($params->{admin});
        }
        # thumbnail captions, and the captions shown in PhotoSwipe
        # (We put these here into the HTML so that Foswiki can expand possible macros (e.g. the WikiNames).
        #  The captions for PhotoSwipe are loaded into the PhotoSwipe items array run-time in JS.)
        if ($img->{thumbcap})
        {
            $tml .=   '<div class="label" style="width: ' . ($params->{size} - 8 - 4 - 4) . 'px;" >';
            $tml .=     '<span class="caption">' . $img->{thumbcap} . '</span>';
            $tml .=   '</div>';
        }
        if ($img->{zoomcap} ne $img->{thumbcap})
        {
            $tml .= '<div class="zoomcap">' . $img->{zoomcap} . '</div>';
        }
        $tml .= '</div>'; # frame
    }
    $tml .= '</div>';

    # build items array for PhotoSwipe, and add JSON to the output
    #my @pswpItems = ();
    #for (my $ix = 0; $ix <= $#images; $ix++)
    #{
    #    my $img = $images[$ix];
    #    push(@pswpItems,
    #       {
    #           w    => $img->{imgWidth},
    #           h    => $img->{imgHeight},
    #           src  => $img->{imgUrl},
    #           msrc => $img->{thumbUrl},
    #       });
    #}
    #$tml .= '<literal><script class="pswpItemsArray" type="text/javascript">';
    #$tml .= 'console.log(document.currentScript); document.currentScript.dataset.items = ' # Nope! :-(
    #      . JSON::to_json(\@pswpItems, { pretty => ($DEBUG ? 1 : 0), utf8 => 1 }) . ';';
    #$tml .= '</script></literal>';

    # admin actions thingies
    if ($params->{admin})
    {
        # action menu
        $tml .= '<ul class="pg-admin-menu jqUITooltip" data-delay="100">';
        $tml .=   '<li class="title">%MAKETEXT{"Actions"}%</li>';
        if ($Foswiki::cfg{Plugins}{PhotoGalleryPlugin}{ExifTranPath})
        {
            $tml .= '<li class="action rotatel" data-action="rotatel" title="%MAKETEXT{"rotate attachment image 90 degress counter clockwise"}%">'
                    . '<img src="%PUBURLPATH%/%SYSTEMWEB%/FamFamFamSilkIcons/arrow_rotate_anticlockwise.png" width="16" height="16"/> %MAKETEXT{"rotate left"}%</li>';
            $tml .= '<li class="action rotater" data-action="rotater" title="%MAKETEXT{"rotate attachment image 90 degrees clockwise"}%">'
                    . '<img src="%PUBURLPATH%/%SYSTEMWEB%/FamFamFamSilkIcons/arrow_rotate_clockwise.png" width="16" height="16"/> %MAKETEXT{"rotate right"}%</li>';
        }
        $tml .=   '<li class="action edit" data-action="edit" title="%MAKETEXT{"edit attachment comment"}%">'
                  . '<img src="%PUBURLPATH%/%SYSTEMWEB%/FamFamFamSilkIcons/pencil.png" width="16" height="16"/> %MAKETEXT{"edit"}%</li>';
        $tml .=   '<li class="action timestamp" data-action="timestamp" title="%MAKETEXT{"update attachment timestamp from photo exposure time (EXIF <nop>CreateDate field)"}%">'
                  . '<img src="%PUBURLPATH%/%SYSTEMWEB%/FamFamFamSilkIcons/clock.png" width="16" height="16"/> %MAKETEXT{"timestamp"}%</li>';
        $tml .=   '<li class="action move" data-action="move" title="%MAKETEXT{"move attachment image to another topic"}%">'
                  . '<img src="%PUBURLPATH%/%SYSTEMWEB%/FamFamFamSilkIcons/arrow_right.png" width="16" height="16"/> %MAKETEXT{"move"}%</li>';
        $tml .=   '<li class="action remove" data-action="remove" title="%MAKETEXT{"delete attachment image (move to <nop>' . $Foswiki::cfg{TrashWebName} . '.TrashAttachment topic)"}%">'
                  . '<img src="%PUBURLPATH%/%SYSTEMWEB%/FamFamFamSilkIcons/bin.png" width="16" height="16"/> %MAKETEXT{"delete"}%</li>';
        $tml .= '</ul>';
        # blocker element to show while actions are being processed
        $tml .= '<div class="pg-admin-blocker" style="width: ' . ($params->{size} + 10) . 'px; height: ' . ($params->{size} + 10) . 'px;">';
        $tml .=   '<div class="tint"></div>';
        $tml .=   '<div class="spinner" style="background-image: url(\'%PUBURLPATH%/%SYSTEMWEB%/DocumentGraphics/processing-32-bg.gif\');"></div>';
        $tml .= '</div>';
        # comment edit dialog
        $tml .= '<div class="photogallery-edit-dialog" data-title="%MAKETEXT{"Edit"}%" data-message-loading="%MAKETEXT{"loading attachment comment..."}%">';
        $tml .=   '<input type="text" class="foswikiInputField foswikiDefaultText comment" placeholder="%MAKETEXT{"attachment comment"}%" size="50"/><br/>';
        $tml .=   '%BUTTON{ "%MAKETEXT{"clear"}%"  class="action-clear"  icon="bin" }%';
        $tml .=   '%BUTTON{ "%MAKETEXT{"save"}%"   class="action-save"   icon="tick" }%';
        $tml .=   '%BUTTON{ "%MAKETEXT{"cancel"}%" class="action-cancel" icon="cross" }%';
        $tml .= '</div>';
        # attachment move dialog
        $tml .= '<div class="photogallery-move-dialog" data-title="%MAKETEXT{"Move"}%" data-message-moving="%MAKETEXT{"moving attachment..."}%">';
        $tml .=   '<input type="text" class="foswikiInputField foswikiDefaultText target" placeholder="%MAKETEXT{"target topic"}%" size="50"/><br/>';
        $tml .=   '%BUTTON{ "%MAKETEXT{"clear"}%"  class="action-clear"  icon="bin" }%';
        $tml .=   '%BUTTON{ "%MAKETEXT{"move"}%"   class="action-move"   icon="arrow_right" }%';
        $tml .=   '%BUTTON{ "%MAKETEXT{"cancel"}%" class="action-cancel" icon="cross" }%';
        $tml .= '</div>';
    }

    # output Photogallery HTML
    $tml .= '<div class="pswp" tabindex="-1" role="dialog" aria-hidden="true">';
    $tml .=     '<div class="pswp__bg"></div>';
    $tml .=     '<div class="pswp__scroll-wrap">';
    $tml .=         '<div class="pswp__container">';
    $tml .=             '<div class="pswp__item"></div>';
    $tml .=             '<div class="pswp__item"></div>';
    $tml .=             '<div class="pswp__item"></div>';
    $tml .=         '</div>';
    $tml .=         '<div class="pswp__ui pswp__ui--hidden">';
    $tml .=             '<div class="pswp__top-bar">';
    $tml .=                 '<div class="pswp__counter"></div>';
    $tml .=                 '<button class="pswp__button pswp__button--close" title="%MAKETEXT{"Close (Esc)"}%"></button>';
    #$tml .=                 '<button class="pswp__button pswp__button--share" title="%MAKETEXT{"Share"}%"></button>';
    $tml .=                 '<button class="pswp__button pswp__button--slideshow" title="%MAKETEXT{"Toggle slideshow"}%"></button>';
    $tml .=                 '<button class="pswp__button pswp__button--fs" title="%MAKETEXT{"Toggle fullscreen"}%"></button>';
    $tml .=                 '<button class="pswp__button pswp__button--zoom" title="%MAKETEXT{"Zoom in/out"}%"></button>';
    $tml .=                 '<div class="pswp__preloader">';
    $tml .=                     '<div class="pswp__preloader__icn">';
    $tml .=                         '<div class="pswp__preloader__cut">';
    $tml .=                             '<div class="pswp__preloader__donut"></div>';
    $tml .=                         '</div>';
    $tml .=                     '</div>';
    $tml .=                 '</div>';
    $tml .=             '</div>';
    $tml .=             '<div class="pswp__share-modal pswp__share-modal--hidden pswp__single-tap">';
    $tml .=                 '<div class="pswp__share-tooltip"></div>';
    $tml .=             '</div>';
    $tml .=             '<button class="pswp__button pswp__button--arrow--left" title="%MAKETEXT{"Previous (arrow left key)"}%"></button>';
    $tml .=             '<button class="pswp__button pswp__button--arrow--right" title="%MAKETEXT{"Next (arrow right key)"}%"></button>';
    $tml .=             '<div class="pswp__caption">';
    $tml .=                 '<div class="pswp__caption__center"></div>';
    $tml .=             '</div>';
    $tml .=         '</div>';
    $tml .=     '</div>';
    $tml .= '</div>';

    # wrapper </div>
    $tml .= '</div>';

    _debug("$debugStr gallery rendered");
    return $tml;
}


####################################################################################################

sub beforeUploadHandler
{
    my ($att, $meta) = @_;

    _initPluginStuff();

    #_debug("beforeUploadHandler($att->{name})");
    #_debug("beforeUploadHandler attrs", $att);
    #          'comment' => '',
    #          'name' => 'IMG_1262.jpg',
    #          'stream' => \*{'Foswiki::Meta::$opts{...}'},
    #          'attachment' => 'IMG_1262.jpg',
    #          'user' => 'flip'

    my $q = Foswiki::Func::getRequestObject();
    my $exifrotateimage = $q->param('exifrotateimage') || '';

    if ( _checkBool($exifrotateimage) && ($att->{name} =~ m/\.(jpg|jpeg)/i))
    {
        my $info = Image::ExifTool::ImageInfo($att->{stream}, [ 'Orientation' ]);
        if ($info && $info->{Orientation})
        {
            seek($att->{stream}, 0, SEEK_SET);
            my $tFile = _getTempFileName();
            File::Copy::copy($att->{stream}, $tFile);
            my $exiftran = $Foswiki::cfg{Plugins}{PhotoGalleryPlugin}{ExifTranPath} || 'exiftran';
            _debug("beforeUploadHandler($att->{name}) $exiftran $tFile");
            # SMELL: Use (the rather weird) Foswiki::Sandbox->sysCommand() instead of system()?
            system("exiftran -a -i $tFile 2>/dev/null >/dev/null");
            my $res = $?;
            if ($res != 0)
            {
                _warning("beforeUploadHandler($att->{name}) exiftran failed, res=$res");
            }
            # SMELL: exiftran changes the filesize, but Foswiki::Meta::attach() doesn't recalculate
            # the (file)size attribute after calling the handler

            #Foswiki::Func::setSessionValue(__PACKAGE__ . '-tfile', $tFile);
            #$q->param(__PACKAGE__ . '-tfile', $tFile);
            $RV->{tempFile} = $tFile;
            open($att->{stream}, '+<', $tFile);
        }
    }

    return;
}

sub afterUploadHandler
{
    my ($att, $meta) = @_;

    _initPluginStuff();

    #_debug("afterUploadHandler($att->{name})");

    #_debug("afterUploadHandler", $att));
    #          'comment' => '',
    #          'date' => 1452249355,
    #          'name' => 'IMG_1262.jpg',
    #          'user' => 'flip',
    #          'attachment' => 'IMG_1262.jpg',
    #          'version' => 6,
    #          'attr' => '',
    #          'size' => 170329

    my $q = Foswiki::Func::getRequestObject();

    # cleanup temp file from beforeUploadHandler()
    #if (my $tFile = Foswiki::Func::getSessionValue(__PACKAGE__ . '-tfile'))
    #if (my $tFile = $q->param(__PACKAGE__ . '-tfile'))
    if (my $tFile = $RV->{tempFile})
    {
        #Foswiki::Func::clearSessionValue(__PACKAGE__ . '-tfile');
        #$q->delete(__PACKAGE__ . '-tfile');
        unlink($tFile) if (-f $tFile);
        delete $RV->{tempFile};
    }

    # get image info (on *all* uploads, as it doesn't cost much here)
    my $info;
    if ($att->{name} =~ m/\.(jpg|jpeg)/i)
    {
        $info = _getImageInfo($meta, $att);
    }

    # set attachment date to photo exposure time if requested and possible
    my $setexifdate = $q->param('setexifdate') || '';
    #_debug("setexifdate=$setexifdate");
    if ( _checkBool($setexifdate) && $info && $info->{CreateDate} &&
         (my $attachment = $meta->get("FILEATTACHMENT", $att->{name})) )
    {
        _debug("afterUploadHandler($att->{name}) filedate="
               . Foswiki::Time::formatTime($info->{CreateDate},
                 $Foswiki::cfg{Plugins}{PhotoGalleryPlugin}{DateFmtDefault}));
        $attachment->{date} = $info->{CreateDate};
        $meta->putKeyed('FILEATTACHMENT', $attachment);
        $meta->save();
    }

    return;
}

sub doRestAdmin
{
    my ($session, $subject, $verb, $response) = @_;

    _initPluginStuff();

    ##### check parameters #########################################################################

    # the request parameters
    my $query = $session->{request};
    my $action  = $query->param('action');
    my $web     = $query->param('att_web');
    my $topic   = $query->param('att_topic');
    my $name    = $query->param('att_name');
    my $comment = $query->param('comment');
    my $term    = $query->param('term');
    my $target  = $query->param('target');

    # normalise attachment web/topic
    if ($web || $topic)
    {
        ($web, $topic) = Foswiki::Func::normalizeWebTopicName($web, $topic);
    }

    # the request response
    my $respText = ($web || '???') . '/<wbr/>' . ($topic || '???') . '/<wbr/>' . ($name || '???');
    my $debugText = ($action || '???') . ':' . ($web || '???') . '/' . ($topic || '???') . '/' . ($name || '???');
    my $resp = { success => 0, message => '', action => $action, web => $web, topic => $topic, name => $name };

    # topic text and meta
    my ($text, $meta);

    # different actions need different parameters
    # (name = need attachment $name, change = need change permissions, meta = need $meta,
    #  term = need $term, target = need $target)
    my %actions =
    (
        rotatel    => { name => 1, change => 1, meta => 1               },
        rotater    => { name => 1, change => 1, meta => 1               },
        getcomment => { name => 1,              meta => 1               },
        update     => { name => 1, change => 1, meta => 1, comment => 1 },
        timestamp  => { name => 1, change => 1, meta => 1               },
        listtopics => {                                    term    => 1 },
        move       => { name => 1, change => 1,            target  => 1 },
    );

    # we always need these parameters, and a valid action
    if ( !$action || !$web || !$topic || !$actions{$action} ||
         ($actions{$action}->{name}    && !$name)   ||
         ($actions{$action}->{term}    && !$term)   ||
         ($actions{$action}->{target}  && !$target) ||
         ($actions{$action}->{comment} && !defined $comment) )
    {
        $resp->{message} = 'Bad or missing parameters!';
        return _doRestAdminResponse($debugText, $response, $resp);
    }

    # assert topic permissions
    if (!Foswiki::Func::checkAccessPermission($actions{$action}->{change} ? 'CHANGE' : 'VIEW',
             Foswiki::Func::getWikiName(), undef, $topic, $web))
    {
        $resp->{message} = "Access to $respText denied!";
        return _doRestAdminResponse($debugText, $response, $resp);
    }

    # need $meta?
    if ($actions{$action}->{meta})
    {
        ($meta, $text) = Foswiki::Func::readTopic($web, $topic);
        if (!$meta)
        {
            $resp->{message} = "Failed reading $respText!";
            return _doRestAdminResponse($debugText, $response, $resp);
        }
    }

    # need $name (existing attachment)
    if ($actions{$action}->{name} && !Foswiki::Func::attachmentExists($web, $topic, $name))
    {
        $resp->{message} = "No such attachment: $respText!";
        return _doRestAdminResponse($debugText, $response, $resp);
    }


    ##### handle actions ###########################################################################

    # rotate attachment left or right
    if ( ($action eq 'rotatel') || ($action eq 'rotater') )
    {
        my $exiftran = $Foswiki::cfg{Plugins}{PhotoGalleryPlugin}{ExifTranPath};
        if (!$exiftran)
        {
            $resp->{message} = "Missing {Plugins}{PhotoGalleryPlugin}{ExifTranPath} configuration!";
            return _doRestAdminResponse($debugText, $response, $resp);
        }

        # open attachment for reading, temp file for writing and copy image
        my $aFh = $meta->openAttachment($name, '<');
        my $tFile = _getTempFileName();
        my $tFh;
        open($tFh, '>', $tFile);
        binmode($tFh);
        File::Copy::copy($aFh, $tFh);
        close($tFh);
        close($aFh);

        # execute exiftran on temporary file
        my %args = ( rotatel => '-2', rotater => '-9' );
        # SMELL: Use (the rather weird) Foswiki::Sandbox->sysCommand() instead of system()?
        _debug("$debugText $exiftran $args{$action} $tFile");
        my $res = system("$exiftran $args{$action} -i $tFile 2>/dev/null >/dev/null");
        if ($res != 0)
        {
            $resp->{message} = "Failed running $exiftran (res=$res)!";
            return _doRestAdminResponse($debugText, $response, $resp);
        }

        # copy it back
        $aFh = $meta->openAttachment($name, '>');
        open($tFh, '<', $tFile);
        binmode($tFh);
        File::Copy::copy($tFh, $aFh);

        # update size meta data
        my $att = $meta->get("FILEATTACHMENT", $name);
        if ($att)
        {
            # bump uid so that the thumbnail URL will be new the next time and the thumbnail gets regenerated
            # will also trigger an image info cache update (ImageWidth and ImageHeight swap)
            $att->{pguid}++;
            $resp->{pguid} = $att->{pguid};

            # size may change slightly
            $att->{size} = -s $tFile;

            # store attachment meta data (this will invalidate the page cache, too, it appears)
            $meta->putKeyed('FILEATTACHMENT', $att);
            $meta->save();
        }

        # clean up
        unlink($tFile);

        $resp->{message} = "Rotated $respText.";
        $resp->{success} = 1;
    }

    # move (or delete) attachment
    elsif ($action eq 'move')
    {
        # SMELL: Handle more errors?
        my ($toWeb, $toTopic);
        if ($target eq 'TRASH')
        {
            $toWeb   = $Foswiki::cfg{TrashWebName};
            $toTopic = 'TrashAttachment';
        }
        else
        {
            ($toWeb, $toTopic) = Foswiki::Func::normalizeWebTopicName('', $target);
        }

        # won't move to myself
        if (($web eq $toWeb) && ($topic eq $toTopic))
        {
            $resp->{message} = "Won't move $respText to itself!";
            return _doRestAdminResponse($debugText, $response, $resp);
        }

        # assert that the target topic exist
        if (!Foswiki::Func::topicExists($toWeb, $toTopic))
        {
            $resp->{message} = "Cannot move $respText to inexistent $toWeb/<wbr/>$toTopic!";
            return _doRestAdminResponse($debugText, $response, $resp);
        }
        # check CHANGE permissions on target topic
        if (!Foswiki::Func::checkAccessPermission('CHANGE',
                 Foswiki::Func::getWikiName(), undef, $toTopic, $toWeb))
        {
            $resp->{message} = "Not allowed to move $respText to $toWeb/<wbr/>$toTopic!";
            return _doRestAdminResponse($debugText, $response, $resp);
        }

        # that should work now..
        my $from = Foswiki::Meta->load($Foswiki::Plugins::SESSION, $web, $topic);
        my $to   = Foswiki::Meta->load($Foswiki::Plugins::SESSION, $toWeb, $toTopic);
        my $toName = $name;
        my $n = 1;
        while ($to->hasAttachment($toName))
        {
            $toName = $name;
            $toName =~ s{(\.[^.]+)$}{_$n$1};
            $n++;
        }

        my $error;
        try { $from->moveAttachment($name, $to, new_name => $toName); }
        catch Error::Simple with
        {
            my $e = (shift)->stringify();
            $e =~ s{\n.*$}{}ms; # remove stack trace
            _warning($e);
            $error = 1;
        };

        if ($error)
        {
            $resp->{message} = "Failed moving $respText to $toWeb/<wbr/>$toTopic!";
        }
        else
        {
            # the TopicInteractionPlugin single-attachment page is useless
            my $skin = Foswiki::Func::getPreferencesValue('SKIN');
            $skin =~ s/topicinteraction,?//;
            my $link = Foswiki::Func::getScriptUrlPath($toWeb, $toTopic, 'attach', filename => $toName, skin => $skin);
            $resp->{message} = "Moved $respText to $toWeb/<wbr/>$toTopic/<wbr/>$toName.";
            $resp->{link} = "Moved to <a href=\"$link\">$toWeb/<wbr/>$toTopic/<wbr/>$toName</a>.";
            $resp->{success} = 1;
        }
    }

    # get comment
    elsif ($action eq 'getcomment')
    {
        #my (undef, undef, undef, $comment) = Foswiki::Func::getRevisionInfo($web, $topic, undef, $name);
        if (my $attachment = $meta->get("FILEATTACHMENT", $name))
        #if (my ($attachment) = grep { $_->{name} eq $name } $meta->find("FILEATTACHMENT"))
        {
            $resp->{comment} = $attachment->{comment};
            $resp->{message} = $attachment->{comment} ?
              "Comment of $respText loaded." : "$respText has no comment yet.";
            $resp->{success} = 1;
        }
    }

    # update attachment (set comment)
    elsif ( ($action eq 'update') && defined $comment)
    {
        if (my $attachment = $meta->get("FILEATTACHMENT", $name))
        {
            $attachment->{comment} = $comment;
            $meta->putKeyed('FILEATTACHMENT', $attachment);
            $meta->save();
            $resp->{message} = "Comment of $respText updated.";
            $resp->{success} = 1;
        }
    }

    # update attachment timestamp from EXIF data
    elsif ($action eq 'timestamp')
    {
        my $att = $meta->get("FILEATTACHMENT", $name);
        if ( $att && (my $info = _getImageInfo($meta, $att)) )
        {
            if ($info && $info->{CreateDate})
            {
                $att->{date} = $info->{CreateDate};
                $meta->putKeyed('FILEATTACHMENT', $att);
                $meta->save();
                $resp->{message} = "$respText date set to "
                  . Foswiki::Time::formatTime(
                        $info->{CreateDate}, $Foswiki::cfg{Plugins}{PhotoGalleryPlugin}{DateFmtDefault});
                $resp->{success} = 1;
            }
            else
            {
                $resp->{message} = "$respText has no EXIF CreatedDate!";
            }
        }
    }

    # list topics
    elsif ($action eq 'listtopics')
    {
        # $term is the user input, $web is the topic the gallery is in
        my $sterm = $term;
        my $sweb  = $web;
        if ($term =~ m/^([^.]+)\.(.+)$/)
        {
            $sweb  = $1;
            $sterm = $2;
        }
        elsif ($term =~ m/^\.(.+)$/)
        {
            $sweb = 'All';
            $sterm = $1;
        }
        $sterm = lc($sterm);
        my $it = Foswiki::Func::query($sterm, undef,
            { type => 'word', scope => 'topic', web => $sweb, casesensitive => 0 });
        my @list = ();
        while ($it->hasNext())
        {
            push(@list, $it->next())
        }
        $resp->{list} = \@list;
        $resp->{success} = -1;
        $resp->{message} = ($#list + 1) . " topics found that match '$term'.";
    }

    # send response
    if (!$resp->{success} && !$resp->{message})
    {
        $resp->{message} = 'Unhandled error!';
    }
    return _doRestAdminResponse($debugText, $response, $resp);
}

sub _doRestAdminResponse
{
    my ($debugText, $response, $resp) = @_;
    my $json = JSON::to_json($resp, { pretty => ($DEBUG ? 1 : 0), utf8 => 1 });
    _debug("admin $debugText " . ($resp->{success} ? ':-)' : $resp->{message}));
    $response->header('-Content-Type'   => 'text/json',
                      '-Status'         => ($resp->{success} ? 200 : 400),
                      '-Content-Length' => length($json),
                      '-Cache-Control'  => 'no-cache',
                      '-Expires'        => '0');
    $response->body($json);
    # no further processing by Foswiki::writeCompletePage()
    return undef;
}

sub genPubThumb
{
    my ($meta, $name, $quality, $width, $height, $uid, $ver) = @_;

    # generate and cache thumbnail unless it exists already
    my $cacheFile = _makeThumb($meta, $name, $quality, $width, $height, $uid, $ver);

    # copy thumbnail to pub directory
    my $pubFileName = ($cacheFile =~ m{([^/]+)$})[0] . '.jpg';
    my $web = $meta->web();
    my $topic = $meta->topic();
    my $pubThumbFile = $Foswiki::cfg{PubDir} . "/$web/$topic/$pubFileName";
    if (! -f $pubThumbFile)
    {
        if (!File::Copy::copy($cacheFile, $pubThumbFile))
        {
            _warning("Could not copy $cacheFile to $pubThumbFile");
        }
    }

    return Foswiki::Func::getPubUrlPath( $web, $topic, $pubFileName );
}

sub doRestThumb
{
    my ($session, $subject, $verb, $response) = @_;

    _initPluginStuff();

    my $query = $session->{request};
    my $topic   = $query->param('topic');
    my $name    = $query->param('name');
    my $quality = _checkRange($query->param('quality'),
                  $Foswiki::cfg{Plugins}{PhotoGalleryPlugin}{QualityDefault}, 1, 100);
    my $width   = $query->param('width');
    my $height  = $query->param('height');
    my $ver     = $query->param('ver') || 0;
    my $uid     = $query->param('uid') || 0;
    (my $web, $topic) = Foswiki::Func::normalizeWebTopicName('', $topic);

    # need all parameters
    if (!$web || !$topic || !$name || !$quality || !$width || !$height || ($name !~ m/\.(jpe?g|png|gif|svg)$/i))
    {
        $response->header(-Status => 400); # bad request
        return undef;
    }

    # does the topic exist?
    if (!Foswiki::Func::topicExists($web, $topic))
    {
        $response->header(-Status => 404); # not found
        return;
    }

    # may read?
    #if (!Foswiki::Func::checkAccessPermission('VIEW',
    #         Foswiki::Func::getWikiName(), undef, $topic, $web))
    #{
    #    $response->header(-Status => 403); # forbidden
    #    return undef;
    #}

    # read meta (and check if the topic actually exists)
    my ($meta, $text) = Foswiki::Func::readTopic($web, $topic);
    if (!$meta)
    {
        $response->header(-Status => 400); # bad request
        return undef;
    }

    # may we read the attachment (the topic)?
    if (!$meta->testAttachment($name, 'r'))
    {
        $response->header(-Status => 403); # forbidden
        return undef;
    }

    # generate and cache thumbnail unless it exists already
    my $cacheFile = _makeThumb($meta, $name, $quality, $width, $height, $uid, $ver);

    # read and serve cached thumbnail
    if (-f $cacheFile)
    {
        my $data = Foswiki::Func::readFile($cacheFile);
        my $dlen = length($data);

        # update cache file timestamp (so that a cronjob can expire old files)
        File::Touch::touch($cacheFile);

        _debug("thumb $web.$topic/$name $quality ${width}x${height} -> $dlen");

        $response->header('-Content-Type'   => 'image/jpeg',
                          '-Content-Length' => $dlen,
                          '-Cache-Control'  => 'max-age=86400',
                          '-Expires'        => '+24h');
        $response->body($data);
        return undef;
    }

    # wtf?!
    $response->header(-Status => 404); # not found
    return undef;
}

sub _makeThumb
{
    my ($meta, $name, $quality, $width, $height, $uid, $ver) = @_;

    my $cacheFile = _getCacheFileName('thumb', $meta->web(), $meta->topic(), $name, $quality, $width, $height, $uid, $ver);

    # cache thumbnail unless it exists already
    if (! -f $cacheFile)
    {
        my $fh = $meta->openAttachment($name, '<');
        my $tFile = _getTempFileName();
        File::Copy::copy($fh, $tFile);

        if ($name =~ m{\.jpe?g$}i)
        {
            my $epeg = Image::Epeg->new($tFile);
            $epeg->resize($width, $height, Image::Epeg::IGNORE_ASPECT_RATIO);
            $epeg->set_quality($quality);
            $epeg->write_file($cacheFile);
            unlink($tFile);
        }
        else
        {
            my $m = _getMagick();
            if ($m)
            {
                eval
                {
                    $m->Read($tFile);
                    $m->Resize(width => $width, height => $height);
                    $m->Set(quality => $quality);
                    $m->Write('jpg:' . $cacheFile);
                }
            }
        }
    }

    return $cacheFile;
}

sub _getMagick
{
    if (exists $RV->{magic})
    {
        return $RV->{magic};
    }
    foreach my $impl (qw(Graphics::Magick Image::Magick))
    {
        my $h;
        eval "require $impl; \$h = ${impl}->new();";
        if ($@)
        {
            my $err = "$@"; $err =~ s{\r?\n.*}{}mgs;
            _debug("tried loading $impl, but it failed: $err");
        }
        if ($h)
        {
            _debug("using $impl");
            $RV->{magic} = $h;
            last;
        }
    }
    if (!$RV->{magic})
    {
        _warning('No magick found :-(');
        $RV->{magic} = undef;
    }
    else
    {
        # Clear image list (Apparently this is a thing... WTF?! See http://www.graphicsmagick.org/perl.html#overview)
        @{$RV->{magic}} = ();
    }
    return $RV->{magic};
}

####################################################################################################
# utility functions

# deferred plugin initialisation and other checks, called by all plugin handlers
# _initPluginStuff()
sub _initPluginStuff
{
    # debug profiling
    $RV->{t0} = Time::HiRes::time() if ($DEBUG);

    # initialise per-request variables once
    unless (defined $RV->{uid})
    {
        # unique id for each gallery, used in Photogallery to track multiple galleries
        $RV->{uid} = 0;

        # output JS and CSS only once per topic
        $RV->{jsCss} = 0;

        # index of already shown photos, for %PHOTOGALLERY{ remaining="on" }%
        $RV->{shown} = {};

        # cache directory for image info cache and cached thumbnails
        $RV->{cacheDir} = Foswiki::Func::getWorkArea('PhotoGalleryPlugin');
    }

    # check some plugin configuration defaults
    $Foswiki::cfg{Plugins}{PhotoGalleryPlugin}{DateFmtDefault} ||= '$http';
    $Foswiki::cfg{Plugins}{PhotoGalleryPlugin}{QualityDefault}
      = _checkRange($Foswiki::cfg{Plugins}{PhotoGalleryPlugin}{QualityDefault}, 85, 1, 100);
    $Foswiki::cfg{Plugins}{PhotoGalleryPlugin}{SizeDefault}
      = _checkRange($Foswiki::cfg{Plugins}{PhotoGalleryPlugin}{SizeDefault}, 150, 50, 500);

    return;
}

# writes debug string(s) to debug.log, automatically stringifies (hash, array, ...) references
# _debug($strOrObj, ...)
sub _debug
{
    return unless ($DEBUG);
    local $Data::Dumper::Sortkeys = 1;
    local $Data::Dumper::Terse = 1;
    my @strs = map { !defined $_ ? 'undef' : (ref($_) ? Data::Dumper::Dumper($_) : $_) } @_;
    Foswiki::Func::writeDebug(__PACKAGE__, sprintf('%6.3f', Time::HiRes::time() - $RV->{t0}), @strs);
}

# writes warning string(s) to error.log
# _warning($str, ...)
sub _warning
{
    Foswiki::Func::writeWarning(@_);
}

# writes a warning string to the error.log and returns an error to be included in the rendered page
# $tml = _wtf($str)
sub _wtf
{
    my $msg = shift;
    _warning($msg);
    return '<span style="background-color: #faa; padding: 0.15em 0.25em;"><b>[[%SYSTEMWEB%.PhotoGalleryPlugin][PhotoGalleryPlugin]] error:</b> ' . $msg . '</span>';
}

# escape HTML attribute string
sub _esc_attr
{
    my $str = shift;
    $str =~ s{<}{&lt;}g;
    $str =~ s{>}{&gt;}g;
    $str =~ s{"}{&quot;}g;
    return $str;
}


# check and assert range of a parameter
# $value = _checkValue($input, $default, $min, $max)
sub _checkRange
{
    my ($val, $def, $min, $max) = @_;
    if    (!defined $val || ($val eq '')
            || ($val !~ m{^[0-9.]+$}))     { return $def; }
    elsif ($val < $min)                    { return $min; }
    elsif ($val > $max)                    { return $max; }
    else                                   { return $val; }
    #return ($val < $min) || ($val > $max) ? $def : $val;
}

# check and assert option
# $value = _checkValue($input, $default, $option, ...)
sub _checkOptions
{
    my ($val, $def, @_opts) = @_;
    $val ||= '';
    my %opts = map { $_, 1 } @_opts;
    return $opts{$val} ? $val : $def;
}

# check on/off/yes/no/1/0 option
# 0 | 1 = _checkOnOff($input)
sub _checkBool
{
    my ($val) = @_;
    my %true = ( yes => 1, on => 1, 1 => 1 );
    return $true{lc($val)} ? 1 : 0;
}

# check "off" or range of a parameter
# $value | '' = _checkOffOrRange($input, $defaultOff, $defaultOn, $min, $max)
sub _checkOffOrRange
{
    my ($val, $defOff, $defOn, $min, $max) = @_;
    if    (!defined $val || ($val eq '') || ($val eq 'off') ) { return $defOff; }
    elsif ($val =~ m/^on$/i) { return $defOn; }
    else { return _checkRange($val, $defOn, $min, $max); }
}

# calculate thumbnail dimensions given the original with and height and the desired short edge size
# of the thumbnail, ratio > 1 --> landscape, ratio < 1 --> portrait
# ($width, $height, $ratio) = _getThumbDims($width, $height, $size)
sub _getThumbDims
{
    my ($w, $h, $s) = @_;
    my $tr = $w / $h;
    my $tw = $tr < 1 ? $s            : int($s * $tr);
    my $th = $tr < 1 ? int($s / $tr) : $s;
    return ($tr, $tw, $th);
}

# get a cache filename (absolute, full path) of a given type (any string) and any number of
# parameters to generate a unique id
# $file = _getCacheFileName($type, $str, ...)
sub _getCacheFileName
{
    my $type = shift;
    my $cacheFile = $RV->{cacheDir} . '/' . $type . '-' . Digest::MD5::md5_hex(@_);
    _debug("$type cache: @_ -> $cacheFile");
    return $cacheFile;
}

# get a temporary file name
sub _getTempFileName
{
    my $f = '';
    do { $f = _getCacheFileName('temp', 'random', int(rand(9999999999))); } until (!-f $f);
    return $f;
}

# returns hash with image information from EXIF data and attachment meta data
# the EXIF info will be cached
# returns undef if not at least ImageWidth and ImageHeight properties could be determined
# (typically because the attachment is missing or it's not an image)
# \%info | undef = _getImageInfo($meta, $att)
sub _getImageInfo
{
    my ($meta, $att) = @_;

    my ($web, $topic) = ($meta->web(), $meta->topic());

    # try cache first
    my $cacheVer = 'v3'; # bump this if something below changes
    my $cacheFile = _getCacheFileName('info', $cacheVer, $web, $topic, $att->{name}, $att->{size}, $att->{version}, $att->{pguid} || 0);
    my $info;
    try { $info = Storable::retrieve($cacheFile); }
    catch Error::Simple with { };
    if ($info)
    {
        #_debug("Getting image info from $web.$topic/$att->{name} (cached).");
        File::Touch::touch($cacheFile); # keep current
    }

    # otherwise get info from file
    if (!$info)
    {
        # try top open the file
        my $fh;
        try { $fh = $meta->openAttachment($att->{name}, '<'); }
        catch Error::Simple with
        {
            my $e = (shift)->stringify();
            $e =~ s{\n.*$}{}ms; # remove stack trace
            _warning("Cannot read $web.$topic/$att->{name}!", $e);
        };

        # get raw EXIF info
        my $_info;
        if ($fh)
        {
            #_debug("Getting image info from $web.$topic/$att->{name}.");
            seek($fh, 0, SEEK_SET);
            # http://www.sno.phy.queensu.ca/~phil/exiftool/TagNames/EXIF.html
            # bump $cacheVer above if this changes
            my @exifAttrs = qw(CreateDate Make Model FileModifyDate ExposureTime UserComment
                               ISO FocalLength ApertureValue ImageWidth ImageHeight
                               GPSLatitude GPSLongitude GPSAltitude);
            # TODO: GPSImgDirection DateTimeOriginal(=CreateDate?) Flash ExposureMode
            my %exifOpts = ( DateFormat => '%s', CoordFormat => '%.9f');
            if (my $exif = Image::ExifTool::ImageInfo($fh, \@exifAttrs, \%exifOpts))
            {
                $_info->{$_} = $exif->{$_} for grep { $exif->{$_} } keys %{$exif};
            }
        }

        # check if it is any good
        # (Image::ExifTool::ImageInfo() works for PNG and GIF images, too: we get ImageHeight and ImageWidth)
        if (!$_info || !$_info->{ImageWidth} || !$_info->{ImageHeight})
        {
            _warning("Failed getting image info from $web.$topic/$att->{name}%s!");
            return undef;
        }

        # SVG don't have a pixel size..
        if ($att->{name} =~ m{\.svg}i)
        {
            $_info->{VectorImageHeight} = $_info->{ImageHeight};  # e.g. '100mm'
            $_info->{VectorImageWidth} = $_info->{ImageWidth};

            my $iw = $_info->{ImageWidth};
            my $ih = $_info->{ImageHeight};
            $iw =~ s{[^0-9.]+$}{};
            $ih =~ s{[^0-9.]+$}{};

            # make it big enough for the screen
            $_info->{ImageHeight} = int( $_info->{ImageHeight} / $_info->{ImageWidth} * 10000 + 0.5 );
            $_info->{ImageWidth} = 10000;
        }

        # process EXIF info
        if ($_info)
        {
            $info = {};
            my $make = $_info->{Make} || '';
            my $model = $_info->{Model} || ''; $model =~ s/$make\s*//;
            if ($make || $model)
            {
                $info->{MakeModel} = $make ? "$make $model" : $model;
                # cleanup
                $info->{MakeModel} =~ s/NIKON CORPORATION NIKON/Nikon/;
            }
            $info->{ImageWidth}  = $_info->{ImageWidth};
            $info->{ImageHeight} = $_info->{ImageHeight};

            if ($_info->{VectorImageHeight})
            {
                $info->{VectorImageWidth}  = $_info->{VectorImageWidth};
                $info->{VectorImageHeight} = $_info->{VectorImageHeight};
                $info->{ImageSize} = $info->{VectorImageWidth} . ' x ' . $info->{VectorImageHeight};
            }
            else
            {
                $info->{ImageSize} = sprintf('%ix%i %.1fMP',
                    $info->{ImageWidth}, $info->{ImageHeight},
                    $info->{ImageWidth} * $info->{ImageHeight} * 1e-6);
            }
            if ($_info->{UserComments})
            {
                # clean up
                my $userComments = $_info->{UserComments} || '';
                $userComments =~ s{User comments}{}i;
                $info->{UserComments} = $userComments if ($userComments);
            }
            foreach (grep { $_info->{$_} } qw(CreateDate Make Model))
            {
                $info->{$_} = $_info->{$_};
            }
            if ($_info->{ExposureTime})
            {
                $info->{ExposureTime} = $_info->{ExposureTime} . 's';
            }
            if ($_info->{FocalLength})
            {
                $info->{FocalLength} = $_info->{FocalLength};
                $info->{FocalLength} =~ s/\s+//g;
            }
            if ($_info->{ApertureValue})
            {
                $info->{ApertureValue} = 'f/' . $_info->{ApertureValue};
            }
            if ($_info->{ISO})
            {
                $info->{ISO} = 'ISO-' . $_info->{ISO};
            }
            if ($_info->{GPSLatitude} && ($_info->{GPSLatitude} =~ m/^(.+)\s*([NS])$/))
            {
                $info->{Lat} = ($2 eq 'N' ? +1 : -1) * $1;
            }
            if ($_info->{GPSLongitude} && ($_info->{GPSLongitude} =~ m/^(.+)\s*([EW])$/))
            {
                $info->{Lon} = ($2 eq 'W' ? +1 : -1) * $1;
            }
            if ($_info->{GPSAltitude} && ($_info->{GPSAltitude} =~ m/^(.+)\s*m.*$/))
            {
                $info->{Alt} = 1 * sprintf('%.0f', $1); # ellipsoid or orthometric height?
            }
            if ($info->{Lat} && $info->{Lon})
            {
                $info->{Coords} = "$info->{Lat}/$info->{Lon}" . ($info->{Alt} ? "/$info->{Alt}" : '');
            }
        }

        # cache
        if ($info)
        {
            #_debug($cacheFile);
            try { Storable::store($info, $cacheFile); }
            catch Error::Simple with
            {
                my $e = (shift)->stringify();
                $e =~ s{\n.*$}{}ms; # remove stack trace
                _warning($e);
            };
        }

        # failed extracting EXIF data, not much we can do..
        else
        {
            $info = {};
        }
    }

    # add wiki name of image (attachment) owner
    $info->{WikiName} = Foswiki::Func::getWikiName($att->{user});

    return $info;
}

# make caption text given the format string, the image info and the attachment meta data
# $str = _makeCaption($format, \%info, \%attachment)
sub _makeCaption
{
    my ($format, $info, $att) = @_;
    my $caption = '';

    # normal variable expansion
    $format =~ s{\$percent}{%}g;
    $format =~ s{\$percnt}{%}g;
    $format =~ s{\$p}{%}g;
    $format =~ s{\$BR}{%BR%}g;

    # magic variable expansion
    while ($format =~ m/
                           \G
                           (.*?)                  # stuff before variable
                           (                      # the thing to interpolate:
                               (\(([^)\$]*?)\))?  #   prefix: (...)
                               \$([a-zA-Z]+)      #   the $variable
                               (\(([^)\$]*?)\))?  #   postfix: (...)
                               (\[([^]]*?)\])?    #   format: [...]
                           )
                       /xcg)
    {
        my ($before, $part, undef, $pre, $var, undef, $post, undef, $fmt)
          = ($1, $2, $3, $4, $5, $6, $7, $8, $9);
        #_debug("[$before] [$part] -->  [$pre] [$var] [$post] [$fmt]");
        $caption .= $before if ($before);

        my $value = $info->{$var} || $att->{$var};
        if ($value)
        {
            # date formatting
            if ($var =~ m/^(date|CreateDate)$/)
            {
                $fmt ||= $Foswiki::cfg{Plugins}{PhotoGalleryPlugin}{DateFmtDefault};
                $value = Foswiki::Time::formatTime($value, $fmt);
            }
            # size has scaling options
            elsif ($var eq 'size')
            {
                $fmt ||= 'MB';
                if    (uc($fmt) eq 'MB') { $value = sprintf('%.1f', $value / 1024 / 1024); }
                elsif (uc($fmt) eq 'KB') { $value = sprintf('%.0f', $value / 1024); }
            }
            # prefix %USERSWEB% to WikiNames so that it renders working links in other webs
            elsif ($var eq 'WikiName')
            {
                $value = '%USERSWEB%.' . $value;
            }
            #_debug("--> $value");
            $caption .= $pre    if ($pre);
            $caption .= $value;
            $caption .= $post   if ($post);
        }
    }
    if ($format =~ m/\G(.*)$/)
    {
        $caption .= $1;
    }

    # remove leading and trailing and empty lines
    $caption =~ s{(%BR%)+}{%BR%}g;
    $caption =~ s{^%BR%}{};
    $caption =~ s{%BR%$}{};

    return $caption;
}

####################################################################################################
1;
__END__
