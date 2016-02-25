# ---+ Extensions
# ---++ PhotoGalleryPlugin
# This is the configuration used by the <b>PhotoGalleryPlugin</b>.

# **PATH**
# Path to the <a href="https://www.kraxel.org/blog/linux/fbida/">exiftran</a> utility.
$Foswiki::cfg{Plugins}{PhotoGalleryPlugin}{ExifTranPath} = 'exiftran';

# **NUMBER**
# Default thumbnails quality (1..100). Smaller number means lower quality but
# also smaller files. Recommended settings are between 50 and 85.
$Foswiki::cfg{Plugins}{PhotoGalleryPlugin}{QualityDefault} = 85;

# **STRING**
# Default date/time format (<a href="view/">GMTIME</a> style).
$Foswiki::cfg{Plugins}{PhotoGalleryPlugin}{DateFmtDefault} = '$wday $day $month $year $hours:$minutes';

# **STRING**
# Default <code>caption</code> parameter for <a href="view/System/VarPHOTOGALLERY"><code>%PHOTOGALLERY%</code></a>.
$Foswiki::cfg{Plugins}{PhotoGalleryPlugin}{CaptFmtDefault} = '$comment($BR )($n/$N, $CreateDate(, )$ExposureTime(, )$FocalLength(, )$ApertureValue(, )$ISO(, )$Coords(, )$MakeModel(, )$WikiName, $name, $ImageSize, $size(MB)[MB])';

# **SELECT user,on,off**
# Default <code>admin</code> parameter for <a href="view/System/VarPHOTOGALLERY"><code>%PHOTOGALLERY%</code></a>.
$Foswiki::cfg{Plugins}{PhotoGalleryPlugin}{AdminDefault} = 'user';

# **NUMBER**
# Default <code>size</code> parameter (thumbnail size) for <a href="view/System/VarPHOTOGALLERY"><code>%PHOTOGALLERY%</code></a> (50..500).
$Foswiki::cfg{Plugins}{PhotoGalleryPlugin}{SizeDefault} = 150;


1;
