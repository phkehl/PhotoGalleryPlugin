/* PhotoGalleryPlugin DropzoneJS Foswiki integration javascript code */

jQuery(function($)
{
    "use strict";

    var DEBUG = true;

    $(document).ready(function()
    {
        // get normal upload form elements and data that we'll need, abort if incomplete
        var uplFileSel   = $('input[name=filepath]');
        var uplForm      = $('form');
        var dzCont       = $('div.dropZoneContainer');
        var dzFiles      = $('div.dropZoneFiles');
        var formAction   = uplForm.attr('action');
        var submitButton = uplForm.find('input[type=submit]');
        var filecommentInput   = uplForm.find('input[name=filecomment]');
        var validationkeyInput = uplForm.find('input[name=validation_key]');
        var propertiesCheckboxes = uplForm.find('input[type=checkbox]');
        if ( (uplFileSel.length !== 1) || (dzCont.length !== 1) ||
             (uplForm.length !== 1) || (submitButton.length !== 1) ||
             !formAction || (dzFiles.length !== 1) || (typeof Dropzone === 'undefined') ||
             (filecommentInput.length !== 1) || (validationkeyInput.length !== 1)
           )
        {
            return;
        }
        //dzDebug('uplFileSel', uplFileSel);
        //dzDebug('uplForm', uplForm);
        //dzDebug('submitButton', submitButton);
        //dzDebug('dzCont', dzCont);
        //dzDebug('dzFiles', dzFiles);
        //dzDebug('filecommentInput', filecommentInput);
        //dzDebug('validationkeyInput', validationkeyInput);
        //dzDebug('propertiesCheckboxes', propertiesCheckboxes);

        var tooltipDefaults =
        {
            arrow: 1, position: { my: 'center top+5', at: 'center bottom' },
            delay: 150, duration: 0, tooltipClass: 'help arrow'
        };
        var nonce = validationkeyInput.val();

        //var iconPath = foswiki.getPreference('PUBURLPATH') + '/' +
        //    foswiki.getPreference('SYSTEMWEB') + '/FamFamFamSilkIcons';

        // put dropzone div in place of the upload file selector
        dzCont.insertAfter(uplFileSel);
        uplFileSel.hide();

        // initialise DropzoneJS
        Dropzone.autoDiscover = false
        Dropzone.options.dropzoneUpload = false; // what is this for?
        var dzOpts =
        {
            url:                    formAction,
            filesizeBase:           1024,
            maxFilesize:            (dzCont.data('filesizelimit') / 1024).toFixed(2),
            uploadMultiple:         false,
            autoProcessQueue:       false,
            addRemoveLinks:         true,
            parallelUploads:        1,
            createImageThumbnails:  false,
            maxFiles:               100,
            uploadMultiple:         false,
            paramName:              'filepath',
            //dictDefaultMessage: 'drop here',
            //dictCancelUpload:   'cancel',
            //dictRemoveFile:     'remove',
            //dictRemoveFile: '<img title="remove file" src="' + iconPath + '/cancel.png"/>',
            dictRemoveFile: ' ',
            //forceFallback: true,
            previewTemplate:        '' +
                '<div class="dz-preview dz-file-preview">' +
                '<div class="dz-filename"><span data-dz-name></span></div>' +
                '<div class="dz-size"><span data-dz-size></span></div>' +
                '<div class="dz-progress"><span class="dz-upload" data-dz-uploadprogress></span></div>' +
                '<div class="dz-success-mark">&nbsp;</div>' +
                '</div>',
            fallback: function () { dzDebug('fallback'); uplFileSel.show(); dzCont.remove(); }
        };
        dzDebug('dzOpts', dzOpts);

        var dzInst = new Dropzone(dzFiles.get(0), dzOpts);
        if (!dzInst)
        {
            return;
        }
        dzFiles.addClass('dropzone');
        dzCont.show();
        dzDebug('instance', dzInst);

        dzInst.on('error', function (file, msg, xhr)
        {
            dzDebug('error file: ' + msg, [ file, xhr ]);
            $(file.previewElement).attr('title', msg)
                .tooltip($.extend({}, tooltipDefaults, { tooltipClass: 'error arrow' }));

        });

        dzInst.on('addedfile', function (file)
        {
            dzDebug('addedfile file', { file: file, nonce: nonce } );
            $(file._removeLink).attr('title', 'click to remove file from list')
                .tooltip($.extend({}, tooltipDefaults))
                .on('click', function () { $(this).tooltip('destroy'); });

            // store form parameters
            file._dzParam = {};
            file._dzParam.filecomment    = filecommentInput.val();
            propertiesCheckboxes.each(function ()
            {
                if ($(this).attr('checked'))
                {
                    file._dzParam[ $(this).attr('name') ] = 'on';
                }
            });

        });

        submitButton.on('click', function (e)
        {
            dzDebug('submit', { e: e });
            dzInst.processQueue();
            dzInst.options.autoProcessQueue = true;
            e.stopImmediatePropagation();
            e.preventDefault();
        });

        dzInst.on('queuecomplete', function ()
        {
            dzInst.options.autoProcessQueue = false;
        });

        dzInst.on('sending', function (file, xhr, form)
        {
            dzDebug('sending file', { file: file, xhr: xhr, form: form });
            file._dzParam.noredirect = 1;
            if (nonce.charAt(0) == '?')
            {
                file._dzParam.validation_key = StrikeOne.calculateNewKey(nonce);
            }
            else if (nonce)
            {
                file._dzParam.validation_key = nonce;
            }
            Object.keys(file._dzParam).forEach(function (k)
            {
                form.append(k, file._dzParam[k]);
            });
        });

        //dzInst.on('complete', function (file, msg, xhr)
        //{
        //    dzDebug('complete file', file); dzDebug('complete msg', msg); dzDebug('complete xhr', xhr);
        //});
        dzInst.on('success', function (file, xhr)
        {
            var newNonce = file.xhr.getResponseHeader('X-Foswiki-Validation');
            dzDebug('success file', { file: file, xhr: xhr, newNonce: newNonce });
            if (newNonce)
            {
                nonce = '?' + newNonce;
            }
            dzInst.options.maxFiles++;
        });


    });

    // console debug, three forms:
    // - dzDebug('string');
    // - dzDebug(object);
    // - dzDebug('string', obect);
    function dzDebug(strOrObj, obj)
    {
        if (DEBUG && window.console)
        {
            if (obj)
            {
                console.log('dz: ' + strOrObj + ': %g', obj);
            }
            else if (typeof strOrObj === 'object')
            {
                console.log('dz: %g', strOrObj);
            }
            else
            {
                console.log('dz: ' + strOrObj);
            }
        }
    }

});

// eof

