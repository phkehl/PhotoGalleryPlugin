/* PhotoGalleryPlugin javascript code */

jQuery(function($)
{
    "use strict";

    var doDEBUG = false;


    /* ***** init each gallery once ************************************************************** */

    $('div.photoGallery:not(.photoGalleryInited').livequery(function()
    {
        var t0 = +(new Date);
        $(this).addClass('photoGalleryInited');

        var pgGlobalsDiv = $('#photoGalleryGlobals');
        doDEBUG = pgGlobalsDiv.data('debug');
        pgSetup(
        {
            t0:           t0,
            pgDiv:        $(this),
            pgGlobalsDiv: pgGlobalsDiv,
            pgUid:        $(this).data('uid'),
            att_web:      $(this).data('web'),
            att_topic:    $(this).data('topic')
        });
    });


    /* ***** setup a single PHOTOGALLERY ********************************************************* */

    function pgSetup(helper)
    {
        DEBUG('init ' + helper.pgUid, helper);

        // find all photos and make list of items with all info for the
        // pswp thingy, arm tooltips
        helper.items  = [];
        helper.pgDiv.find('div.frame').each(function ()
        {
            var frame = $(this);
            var a = frame.find('a.img');
            var caption = frame.find('span.caption');
            var zoomcap = frame.find('div.zoomcap');
            var thumb = frame.find('img.thumb');
            helper.items.push(
            {
                frame: frame,              // div.frame
                thumb: thumb,              // img.tumb within div.frame
                name:  frame.data('name'), // attachment name
                src:   a.attr('href'),     // image href
                w:     a.data('w'),        // image width
                h:     a.data('h'),        // image height
                msrc:  thumb.attr('src'),  // tumbnail href
                title: (zoomcap.length ? zoomcap.html() : caption.html())  // caption
            });
            frame.find('div.label').attr('title', caption.text());
        });

        // pswp options (http://photoswipe.com/documentation/options.html)
        helper.options =
        {
            // barsSize: { top:44, bottom: 'auto' }, // from photoswipe-ui-default.js
            galleryUID:              helper.pgUid,
            spacing:                 0,
            shareEl:                 false,
            showHideOpacity:         true,
            closeElClasses:          [],
            clickToCloseNonZoomable: false,
            maxSpreadZoom:           4,
            loop:                    false,
            timeToIdle:              parseInt(helper.pgDiv.data('uidelay')),
            timeToIdleOutside:       parseInt(helper.pgDiv.data('uidelay')),
            loadingIndicatorDelay:   10,
            // zoom in/out animation
            getThumbBoundsFn: function (ix)
            {
                var thumb = $(helper.items[ix].thumb);
                var offset = thumb.offset();
                if (offset)
                {
                    return { x: offset.left, y: offset.top, w: thumb.width(), h: thumb.height() };
                }
            }
        };

        // handle slideshow play/stop button
        helper.slideshowButton = helper.pgDiv.find('.pswp__button--slideshow');
        helper.slideshowButton.addClass('stopped');
        var slideshowIv;
        helper.slideshowButton.on('click', function (e)
        {
            // start playing
            if ($(this).hasClass('stopped'))
            {
                slideshowIv = setInterval(function()
                {
                    if (helper.pswp)
                    {
                        helper.pswp.next();
                    }
                }, parseInt(helper.pgDiv.data('ssdelay')));
            }
            // stop playing
            else
            {
                if (slideshowIv)
                {
                    clearInterval(slideshowIv);
                    slideshowIv = null;
                }
            }
            $(this).toggleClass('stopped playing');
        });

        // add click handler to every frame that launches the pswp at the given index
        helper.options.pswp = undefined;
        helper.pgDiv.find('a.img').on('click', function (e)
        {
            helper.options.index = $(this).data('ix');
            if (helper.pswp)
            {
                helper.pswp.close();
            }
            helper.pswp = new PhotoSwipe(
                helper.pgDiv.find('div.pswp')[0], PhotoSwipeUI_Default,
                helper.items, helper.options);
            helper.pswp.init();
            helper.pswp.listen('destroy', function ()
            {
                helper.pswp = null;
                if (slideshowIv)
                {
                    clearInterval(slideshowIv);
                    slideshowIv = null;
                    helper.slideshowButton.toggleClass('stopped playing');
                }
                if (location.hash)
                {
                    location.hash = location.hash.replace(/&gid=(\d+)&pid=(\d+)/, '');
                }
            });
            return false;
        });

        // add window resize event that centres the gallery
        var nFrames = helper.items.length;
        var frameWidth = helper.items[0].frame.outerWidth() + 5 + 5;
        var debounceTimer;
        $(window).on('resize', function (e)
        {
            if (debounceTimer)
            {
                clearTimeout(debounceTimer);
            }
            debounceTimer = setTimeout(function ()
            {
                var availableSpace = helper.pgDiv.innerWidth();
                var nPossible = Math.floor(availableSpace / frameWidth);
                var w = (nPossible > 0 ? (nPossible > nFrames ? nFrames : nPossible) : 1) * frameWidth;
                helper.pgDiv.find('div.gallery').width(w);
                //DEBUG('availableSpace=' + availableSpace + ' nPossible=' + nPossible + ' w=' + w);
                // FIXME: optimise for least number of columns and rows (fewest empty spots)
            }, 25);
        });
        $(window).trigger('resize'); // trigger initial centring

        // handle hash: open pswp at index if "&gid=...&pid=..." hash is present
        var hash = location.hash.match(/&gid=(\d+)&pid=(\d+)/);
        if (hash && (hash.length == 3))
        {
            $('div.photoGallery[data-uid=' + hash[1] + '] a[data-ix=' + hash[2] + ']')
                .trigger('click');
        }

        // arm admin menu
        helper.adminMenu = helper.pgDiv.find('ul.pg-admin-menu');
        var adminMenuEnterTo;
        helper.pgDiv.find('a.admin').each(function ()
        {
            $(this).on('mouseenter', function (e)
            {
                if (adminMenuEnterTo)
                {
                    clearTimeout(adminMenuEnterTo);
                }
                var icon = $(this);
                adminMenuEnterTo = setTimeout(function ()
                {
                    var ix = icon.data('ix');
                    helper.adminMenu.find('li.timestamp').toggle(eval(icon.data('tsaction')));
                    helper.adminMenu.fadeIn().position({ my: 'right top', at: 'right top', of: icon });
                    helper.adminMenu.find('li').data('ix', ix);;
                }, 300);
            });
            $(this).on('mouseleave', function (e)
            {
                if (adminMenuEnterTo)
                {
                    clearTimeout(adminMenuEnterTo);
                }
            });
        });
        var adminMenuLeaveTo;
        helper.adminMenu.on('mouseleave', function (e)
        {
            if (adminMenuLeaveTo)
            {
                clearTimeout(adminMenuLeaveTo);
            }
            adminMenuLeaveTo = setTimeout(function ()
            {
                helper.adminMenu.stop().fadeOut('slow');
            }, 500);
        });
        helper.adminMenu.on('mouseenter', function (e)
        {
            if (adminMenuLeaveTo)
            {
                clearTimeout(adminMenuLeaveTo);
            }
            helper.adminMenu.stop().fadeIn();
        });

        function adminMenuShow(helper, ix)
        {
            DEBUG('tsaction', $(this).data('tsaction'));
            helper.adminMenu.find('li.timestamp').toggle($(this).data('tsaction'));
            var ix = $(this).data('ix');
            helper.adminMenu.show()
                .position({ my: 'right top', at: 'right top', of: $(this) });
            helper.adminMenu.find('li').data('ix', ix);;
        }

        // arm admin menu buttons
        helper.adminBlocker = helper.pgDiv.find('div.pg-admin-blocker');
        helper.editDialog = helper.pgDiv.find('div.photogallery-edit-dialog');
        helper.moveDialog = helper.pgDiv.find('div.photogallery-move-dialog');
        var actions =
        {
            //cancel:    function () {},
            rotatel:   adminActionRotate,
            rotater:   adminActionRotate,
            remove:    adminActionDelete,
            edit:      adminActionEdit,
            timestamp: adminActionTimestamp,
            move:      adminActionMove
        };
        helper.adminMenu.find('li.action').on('click', function (e)
        {
            var ix = $(this).data('ix');
            var action = $(this).data('action');
            helper.adminMenu.fadeOut();
            if (!actions[action])
            {
                pgNotify('error', "Action '" + action + "' unavailable!");
            }
            else
            {
                actions[action].call(helper.adminMenu, action, ix, helper);
            }
        });

        if (doDEBUG)
        {
            var dt = ( +(new Date) - helper.t0 ) * 1e-3;
            var sp = helper.items.length / dt;
            DEBUG('done ' + helper.pgUid + ': ' +
                helper.items.length + ' in ' + dt.toFixed(3) + 's, ' + sp.toFixed(0) + '/s' );
        }
    }


    /* ***** admin action: rotate left and right ************************************************* */

    function adminActionRotate(action, ix, helper)
    {
        var frame = helper.items[ix].frame;
        var thumb = helper.items[ix].thumb;
        var name  = helper.items[ix].name;
        this.hide();
        var blocker = helper.adminBlocker.clone().appendTo(helper.pgDiv);
        blocker.fadeIn().position({ my: 'center', at: 'center', of: frame });
        pgRestAdminHelper(helper, blocker, { action: action, att_name: name }, function (data)
        {
            thumb.fadeOut('slow', function ()
            {
                //var thumbUrl = thumb.attr('src').replace(/;refresh=[^;]*/, '').replace(/;_t=\d*/, '')
                //   + ';refresh=on;_t=' + (+new Date);
                DEBUG('data', data);
                // current width and height
                var iw = helper.items[ix].w;
                var ih = helper.items[ix].h;
                var tw = thumb.attr('width');
                var th = thumb.attr('height');
                var dw = thumb.width();
                var dh = thumb.height();

                // refresh thumbnail (swapping width and height)
                var thumbUrl = thumb.attr('src').replace(/;refresh=[^;]*/, '')
                    .replace(/width=\d+/, 'width=' + th).replace(/height=\d+/, 'height=' + tw)
                    .replace(/uid=\d+/, 'uid=' + (data.pguid || 0));
                thumb.on('load', function ()
                {
                    $(this).fadeIn();
                    blocker.fadeOut(undefined, function () { $(this).remove(); });
                });
                thumb.attr('src', thumbUrl);

                // swap width and height
                helper.items[ix].w = ih;
                helper.items[ix].h = iw
                thumb.attr('width', th);
                thumb.attr('height', tw);
                thumb.width(dh);
                thumb.height(dw);

                // refresh original image
                var src = foswiki.getPubUrlPath(helper.att_web, helper.att_topic, name);
                //helper.pgDiv.find('img.pswp__img').each(function (ix, el)
                //{
                //    if ($(el).attr('src') == src)
                //    {
                //        $(el).attr('src', src + '?' + (+new Date));
                //    }
                //});
                helper.items[ix].src = src + '?' + (+new Date);
                //helper.pswp.invalidateCurrItems();
                //helper.pswp.updateSize(true);
            });

        });
    }


    /* ***** admin action: edit attachment comment *********************************************** */

    function adminActionEdit(action, ix, helper)
    {
        if (helper.items[ix].editDialog)
        {
            helper.items[ix].editDialog.dialog('open');
            return;
        }
        var editDialog = helper.editDialog.clone();
        var input = editDialog.find('input');
        helper.items[ix].editDialog = editDialog;
        editDialog.find('a.action-cancel').on('click', function (e)
        {
            e.preventDefault();
            editDialog.dialog('close');
        });
        editDialog.find('a.action-clear').on('click', function (e)
        {
            e.preventDefault();
            input.val('');
        });
        var name = helper.items[ix].name;
        input.prop('disabled', true);
        editDialog.dialog(
        {
            title: (editDialog.data('title') + ': ' + name), height: 'auto', width: 'auto',
            minHeight: 1, resizable: false,
            position: { my: 'center top', at: 'center bottom', of: helper.items[ix].frame },
            close: function (e, ui) { editDialog.remove(); delete helper.items[ix].editDialog; },
            focus: function (e, ui) { adminDialogFocusChange($(this), helper, ix); },
        });
        editDialog.block({ message: editDialog.data('message-loading'), css: { padding: '0.25em 0.5em', width: 'auto' } });
        pgRestAdminHelper(helper, undefined, { action: 'getcomment', att_name: name }, function (data)
        {
            input.val(data.comment).data('orig', data.comment);;
            editDialog.unblock();
            input.prop('disabled', false);
        }, function ()
        {
            editDialog.unblock();
        });
        editDialog.find('a.action-save').on('click', function (e)
        {
            e.preventDefault();
            var orig = input.data('orig');
            var comment = input.val();
            var blocker = helper.adminBlocker.clone().appendTo(helper.pgDiv);
            blocker.fadeIn().position({ my: 'center', at: 'center', of: helper.items[ix].frame });
            editDialog.dialog('close');
            pgRestAdminHelper(helper, blocker,
                              { action: 'update', comment: comment, att_name: name },
                // success
                function (data)
                {
                    var label = helper.items[ix].frame.find('div.label');
                    var caption = helper.items[ix].frame.find('span.caption');
                    if (label !== undefined)
                    {
                        label.attr('title', label.attr('title').replace(orig, comment + ' '));
                    }
                    if (caption !== undefined)
                    {
                        caption.html(caption.html().replace(orig, comment));
                    }
                    blocker.fadeOut(undefined, function () { $(this).remove(); });
                });
        });
    }


    /* ***** admin action: update attachment timestamp ******************************************* */

    function adminActionTimestamp(action, ix, helper)
    {
        var frame = helper.items[ix].frame;
        var name  = helper.items[ix].name;
        this.hide();
        var blocker = helper.adminBlocker.clone().appendTo(helper.pgDiv);
        blocker.fadeIn().position({ my: 'center', at: 'center', of: frame });
        pgRestAdminHelper(helper, blocker,
                          { action: action, att_name: name },
            // success
            function (data)
            {
                frame.find('a.admin').data('tsaction', false);
                blocker.fadeOut(undefined, function () { $(this).remove(); });
            });
    }


    /* ***** admin action: delete attachment (photo) ********************************************* */

    function adminActionDelete(action, ix, helper)
    {
        helper.items[ix].thumb.clone().dialog(
        {
            title: 'Delete this photo?', dialogClass: 'photogallery-confirm-dialog',
            resizable: false, height: 'auto', width: 'auto', modal: true,
            buttons:
            [
                { text: 'No', icons: { primary: 'ui-icon-close' },
                  click: function () { $(this).dialog('close'); } },
                { text: 'Yes', icons: { primary: 'ui-icon-trash' },
                  click: function () { $(this).dialog('close'); _adminActionDelete(action, ix, helper, 'TRASH'); } }
            ]
        });
    }

    function _adminActionDelete(action, ix, helper, target)
    {
        var blocker = helper.adminBlocker.clone().appendTo(helper.pgDiv);
        blocker.fadeIn().position({ my: 'center', at: 'center', of: helper.items[ix].frame });
        pgRestAdminHelper(helper, blocker,
                          { action: 'move', att_name: helper.items[ix].name, target: target },
            // success
            function (data)
            {
                blocker.fadeOut(undefined, function () { $(this).remove(); });
                helper.items[ix].thumb.fadeOut(undefined, function ()
                {
                    helper.items[ix].frame.find('img, .img, .caption, .label, .admin').remove();
                    helper.items[ix].frame.find('div.crop').html(data.link);
                    helper.items[ix] = {};
                });
            });
        if (helper.items[ix].editDialog)
        {
            helper.items[ix].editDialog.dialog('close');
        }
        if (helper.items[ix].moveDialog)
        {
            helper.items[ix].moveDialog.dialog('close');
        }
    }


    /* ***** admin action: move attachment ******************************************************* */

    function adminActionMove(action, ix, helper)
    {
        if (helper.items[ix].moveDialog)
        {
            helper.items[ix].moveDialog.dialog('open');
            return;
        }
        var moveDialog = helper.moveDialog.clone();
        var input = moveDialog.find('input');
        helper.items[ix].moveDialog = moveDialog;
        moveDialog.find('a.action-cancel').on('click', function (e)
        {
            e.preventDefault();
            moveDialog.dialog('close');
        });
        moveDialog.find('a.action-clear').on('click', function (e)
        {
            e.preventDefault();
            input.val('');
        });
        var name = helper.items[ix].name;
        moveDialog.dialog(
        {
            title: (moveDialog.data('title') + ': ' + name), height: 'auto', width: 'auto',
            minHeight: 1, resizable: false,
            position: { my: 'center top', at: 'center bottom', of: helper.items[ix].frame },
            close: function (e, ui) { moveDialog.remove(); delete helper.items[ix].moveDialog; },
            focus: function (e, ui) { adminDialogFocusChange($(this), helper, ix); },
        });

        var jqXHR;
        if (!helper.cache)
        {
            helper.cache = {};
        }
        input.autocomplete(
        {
            delay: 350, minLength: 1, appendTo: moveDialog,
            position: { my: 'left bottom', at: 'left top' },
            source: function (request, response)
            {
                if (jqXHR)
                {
                    jqXHR.abort();
                }
                var term = request.term;
                if (helper.cache[term])
                {
                    response(helper.cache[term]);
                }
                else
                {
                    jqXHR = pgRestAdminHelper(helper, undefined, { action: 'listtopics', term: term }, function (data)
                    {
                        helper.cache[term] = data.list;
                        jqXHR = undefined;
                        response(data.list);
                    }, function ()
                    {
                        helper.cache[term] = [];
                        response();
                    });
                }
            }
        });

        DEBUG(moveDialog.find('a.action-move'));
        moveDialog.find('a.action-move').on('click', function (e)
        {
            e.preventDefault();
            var target = input.val();
            if (target)
            {
                moveDialog.block({ message: moveDialog.data('message-moving'), css: { padding: '0.25em 0.5em' } });

                var blocker = helper.adminBlocker.clone().appendTo(helper.pgDiv);
                blocker.fadeIn().position({ my: 'center', at: 'center', of: helper.items[ix].frame });
                pgRestAdminHelper(helper, blocker,
                                  { action: 'move', att_name: helper.items[ix].name, target: target },
                    // success
                    function (data)
                    {
                        blocker.fadeOut(undefined, function () { $(this).remove(); });
                        helper.items[ix].thumb.fadeOut(undefined, function ()
                        {
                            helper.items[ix].frame.find('img, .img, .caption, .label, .admin').remove();
                            helper.items[ix].frame.find('div.crop').html(data.link);
                            helper.items[ix] = {};
                            moveDialog.unblock();
                            moveDialog.dialog('close');
                        });
                    },
                    // failure
                    function ()
                    {
                        moveDialog.unblock();
                    });
            }
        });
    }


    /* ***** admin action helper function ******************************************************** */

    function pgRestAdminHelper(helper, blocker, data, success, error)
    {
        // calculate validation_key & fire REST request for the action
        // http://foswiki.org/Development/HowToIntegrateWithRequestValidation
        var nonce = helper.pgGlobalsDiv.data('nonce');
        var validation_key = StrikeOne.calculateNewKey(nonce);

        var data = $.extend(
        {
            validation_key: validation_key, att_web: helper.att_web, att_topic: helper.att_topic
        }, data);

        return $.ajax(
        {
            data: data,
            method: 'POST', timeout: 20000,
            url: foswiki.getScriptUrlPath('rest') + '/PhotoGalleryPlugin/admin',
            complete: function (jqXHR, textStatus)
            {
                var nonce = jqXHR.getResponseHeader('X-Foswiki-Validation');
                if (nonce)
                {
                    DEBUG('new nonce ' + nonce);
                    helper.pgGlobalsDiv.data('nonce', nonce);
                }
            },
            success: function (data, textStatus, jqXHR)
            {
                if (data.success)
                {
                    if (data.success > 0)
                    {
                        pgNotify('success', data.message);
                    }
                    success(data);
                }
                else
                {
                    pgNotify('error', data.message);
                    if (blocker) { blocker.fadeOut(undefined, function () { $(this).remove(); }); }
                }
            },
            error: function (jqXHR, textStatus, errorThrown)
            {
                if (textStatus != 'abort')
                {
                    var err = (jqXHR.responseJSON && jqXHR.responseJSON.message) ? jqXHR.responseJSON.message :
                        (textStatus + ' / ' + errorThrown);
                    pgNotify('error', err);
                    if (blocker) { blocker.fadeOut(undefined, function () { $(this).remove(); }); }
                }
                if (error)
                {
                    error();
                }
            }
        });
    }


    /* ***** utility functions ******************************************************************* */

    function pgNotify(type, text)
    {
        $.pnotify(
        {
            type: type, text: text,
            //title: (type == 'success' ? ':-)' : ':-('),
            width: '50em', delay: (type == 'success' ? 3500 : 8000),
            /*nonblock: true, nonblock_opacity: 0.75*/
        });
    }

    function adminDialogFocusChange(dialog, helper, ix)
    {
        // FIXME: would have to handle close event, too
        //if (helper.focusFrame)
        //{
        //    helper.focusFrame.removeClass('photogallery-admin-focus');
        //}
        //helper.focusFrame = helper.items[ix].frame.addClass('photogallery-admin-focus');
        if (helper.focusTitle)
        {
            helper.focusTitle.removeClass('photogallery-admin-focus');
        }
        helper.focusTitle = dialog.parent().find('.ui-dialog-title').addClass('photogallery-admin-focus');
    }

    // console debug, three forms:
    // - DEBUG('string');
    // - DEBUG(object);
    // - DEBUG('string', obect);
    function DEBUG(strOrObj, obj)
    {
        if (doDEBUG && window.console)
        {
            if (obj)
            {
                console.log('pg: ' + strOrObj + ': %g', obj);
            }
            else if (typeof strOrObj === 'object')
            {
                console.log('pg: %g', strOrObj);
            }
            else
            {
                console.log('pg: ' + strOrObj);
            }
        }
    }

});

// eof
