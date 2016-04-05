# PhotoGalleryPlugin
A Foswiki gallery plugin for JPEG photos from digital cameras.

This plugin renders galleries from photos attached to topics. It renders a grid
of square thumbnails. Clicking on a thumbnail zooms the image to the original
attached photo. Currently PhotoSwipe (http://photoswipe.com) by Dmitry
Semenov is used to display the photos. It allows zooming and browsing the image
gallery with the keyboard, the mouse and finger swipes on touch devices. This
plugin adds a slideshow functionality not currently present in the original
PhotoSwipe gallery. The thumbnails expose a tools menu by hovering over
their top right corner. Available tools include losslessly rotating the photo
using [[https://www.kraxel.org/blog/linux/fbida/][exiftran]], editing the
attachment comment, correcting the attachment timestamp to the photo exposure
date, moving the attachment to another topic, and deleting the attachment.
 
This plugin works only with JPEG images and it works best
with photos from digital cameras that have EXIF data
embedded.
