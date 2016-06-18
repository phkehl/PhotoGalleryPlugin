/* PhotoGalleryPlugin DropzoneJS Foswiki integration javascript code */

jQuery(function($)
{
    "use strict";

    // add "debug=1" to the query string to enable debugging
    var DEBUG = location && location.href && (location.href.indexOf('debug=1') >= 0) ? true : false;

    $(document).ready(function()
    {
        /* ***** prepare ************************************************************************* */

        // sanity check that we're on the right page
        var uplFileSel   = $('input[name=filepath]');
        var uplForm      = $('form');
        var dzCont       = $('div.dropZoneContainer');
        var uploadAction = uplForm.attr('action');
        if ( (uplFileSel.length !== 1) || (dzCont.length !== 1) ||
             (uplForm.length !== 1) || !uploadAction ||
             (typeof Dropzone === 'undefined') )
        {
            return;
        }

        // more HTML elements that we'll need
        var dzFiles            = $('div.dropZoneFiles');
        var dzFilesResize      = $('div.dropZoneFilesResize');
        var submitButton       = uplForm.find('input[type=submit]');
        var filecommentInput   = uplForm.find('input[name=filecomment]');
        var validationkeyInput = uplForm.find('input[name=validation_key]');
        var propsCheckboxes    = uplForm.find('input[type=checkbox]');
        var origActionButtons  = uplForm.find('.patternActionButtons');
        var addButton          = dzCont.find('.dropZoneActionAdd');
        var clearButton        = dzCont.find('.dropZoneActionClear');
        var uploadButton       = dzCont.find('.dropZoneActionUpload');
        var cancelButton       = dzCont.find('.dropZoneActionCancel');
        var progBar            = dzCont.find('.dropZoneUploadProgress');
        var progLabel          = dzCont.find('.dropZoneUploadProgressLabel');
        var dictFileTooBig     = dzCont.find('.dropZoneDictFileTooBig').html();
        var dictRemoveFile     = dzCont.find('.dropZoneDictRemoveFile').html();

        // the current CSRF key, will be updated after every upload
        // (see https://foswiki.org/Development/HowToIntegrateWithRequestValidation)
        var nonce = validationkeyInput.val();

        dzDebug('dropzonejsskin', { uplFileSel: uplFileSel, uplForm: uplForm,
            dzCont: dzCont, uploadAction: uploadAction, dzFiles: dzFiles,
            dzFilesResize: dzFilesResize, filecommentInput: filecommentInput,
            validationkeyInput: validationkeyInput, propsCheckboxes: propsCheckboxes,
            origActionButtons: origActionButtons, nonce: nonce,
            addButton: addButton, clearButton: clearButton,
            uploadButton: uploadButton, cancelButton: cancelButton,
            progBar: progBar, progLabel: progLabel});


        /* ***** initialise the DropzoneJS thingy ************************************************ */

        // put dropzone div in place of the upload file selector
        dzCont.insertAfter(uplFileSel);
        uplFileSel.hide();
        origActionButtons.hide();

        // DropzoneJS options
        Dropzone.autoDiscover = false
        var maxFileSize = parseInt(dzCont.data('filesizelimit')) * 1024;
        Dropzone.options.dropzoneUpload = false; // what is this for?
        var dzOpts =
        {
            url:                    uploadAction,
            filesizeBase:           1024,
            maxFilesize:            (maxFileSize / 1024 / 1024).toFixed(2),
            uploadMultiple:         false,
            autoProcessQueue:       false,
            addRemoveLinks:         true,
            parallelUploads:        1,
            createImageThumbnails:  false,
            maxFiles:               100,
            clickable:              $('<div/>').appendTo(dzCont).get(0), // dummy
            paramName:              'filepath',
            dictRemoveFile:         ' ',
            dictFileTooBig:         dictFileTooBig,
            // fall-back to original upload form if the browser isn't supported
            //forceFallback: true, // for testing
            previewTemplate:        '' +
                '<div class="dz-preview dz-file-preview">' +
                '<div class="dz-filename"><span data-dz-name></span></div>' +
                '<div class="dz-size"><span data-dz-size></span></div>' +
                '<div class="dz-progress"><span class="dz-upload" data-dz-uploadprogress></span></div>' +
                '<div class="dz-success-mark">&nbsp;</div>' +
                '</div>',
            // restore original upload form if DropzoneJS is not supported by the browser
            fallback: function () { uplFileSel.show(); origActionButtons.show(); dzCont.remove(); }
        };
        dzDebug('dzOpts', dzOpts);

        // initialise the DropzoneJS...
        var dzInst = new Dropzone(dzFiles.get(0), dzOpts);
        if (!dzInst)
        {
            return;
        }
        // ...and style and show it
        dzFiles.addClass('dropzone');
        dzCont.show();
        dzDebug('instance', dzInst);
        var msg = dzCont.find('.dropZoneDictDefaultMessage');
        msg.html( msg.html().replace('{{maxfilesize}}', dzInst.filesize(maxFileSize) ) );

        // make the dropzone resizable in height (but not width)
        dzFilesResize.resizable({ handles: 's' });


        /* ***** arm the DropzoneJS interactions ************************************************* */

        // on error, add a tooltip to the file entry with the error message
        dzInst.on('error', function (file, msg, xhr)
        {
            dzDebug('error file: ' + msg, [ file, xhr ]);
            addTooltip(file.previewElement, msg, 'error');
        });

        // display a message while DropzoneJS is processing dropped/added files
        dzInst.on('drop', function (e)
        {
            dzFiles.block({ message: 'Processing files&hellip;' });
        });

        // arm buttons tooltips
        [ addButton, clearButton, uploadButton, cancelButton ].forEach(function (el)
        {
            addTooltip(el, el.attr('title'), 'help');
        });

        // open file selection dialog (see also dzOpts.clickable)
        addButton.on('click', function (e)
        {
            e.preventDefault();
            if ($(this).hasClass('dropZoneActionDisabled'))
            {
                dzDebug('hasclass', $(this));
                return;
            }
            dzInst.hiddenFileInput.click();
        });

        // clear queue
        clearButton.on('click', function (e)
        {
            e.preventDefault();
            if ($(this).hasClass('dropZoneActionDisabled'))
            {
                return;
            }
            dzInst.removeAllFiles();
            uploadButton.addClass('dropZoneActionDisabled');
        });

        // start upload
        uploadButton.on('click', function (e)
        {
            e.preventDefault();
            if ($(this).hasClass('dropZoneActionDisabled'))
            {
                return;
            }
            dzDebug('upload', { e: e });
            dzInst.processQueue();
            dzInst.options.autoProcessQueue = true;
            progBar.progressbar('value', undefined);
            progBar.progressbar('enable');
            uploadButton.hide();
            cancelButton.show();
            addButton.addClass('dropZoneActionDisabled');
            clearButton.addClass('dropZoneActionDisabled');
        });
        uploadButton.addClass('dropZoneActionDisabled');

        // cancel pending uploads
        cancelButton.on('click', function (e)
        {
            e.preventDefault();
            if ($(this).hasClass('dropZoneActionDisabled'))
            {
                return;
            }
            dzInst.options.autoProcessQueue = false;
            $(this).addClass('dropZoneActionDisabled');
        }).hide();

        // uploading finished
        dzInst.on('queuecomplete', function ()
        {
            dzInst.options.autoProcessQueue = false;
            progBar.progressbar('disable');
            uploadButton.show();
            cancelButton.hide();
            addButton.removeClass('dropZoneActionDisabled');
            clearButton.removeClass('dropZoneActionDisabled');
            uploadButton.addClass('dropZoneActionDisabled');
        });

        dzInst.on('removedfile', function (file)
        {
            //dzDebug('removedfile', [ this, file ]);
            if (!this.files.length)
            {
                uploadButton.addClass('dropZoneActionDisabled');
            }
        });

        // overall upload progress bar
        progBar.progressbar({ disabled: true, max: 100.0 });
        progBar.progressbar('disable');
        dzInst.on('totaluploadprogress', function (uploadProgress, totalBytes, totalBytesSent)
        {
            //dzDebug('uploadprogress', [ this, uploadProgress, totalBytes, totalBytesSent ]);
            // need to recalculate these because DropzoneJS calculates rubbish
            uploadProgress = totalBytes = totalBytesSent = 0;
            this.files.forEach(function (f)
            {
                if (f.upload)
                {
                    totalBytes += f.upload.total || 0;
                    totalBytesSent += f.upload.bytesSent || 0;
                }
            });
            uploadProgress = totalBytes ? (totalBytesSent / totalBytes * 1e2) : 0;
            progBar.progressbar('value', uploadProgress);
            progLabel.html('Uploaded: ' + this.filesize(totalBytesSent) + ' / ' + this.filesize(totalBytes)
                           + (uploadProgress ? ' (' + uploadProgress.toFixed(0) + '%)': ''));
        });
        dzInst.updateTotalUploadProgress();

        // when a file is dropped or added...
        dzInst.on('addedfile', function (file)
        {
            dzDebug('addedfile file', { file: file } );

            // ...add a tooltip to the remove icon
            addTooltip(file._removeLink, dictRemoveFile, 'help');
            $(file._removeLink).on('click', function ()
            {
                $(this).tooltip('destroy').parent().tooltip('destroy');
            });

            // ...store form parameters
            var tooltip = '';
            file._dzParam = {};
            file._dzParam.filecomment = filecommentInput.val();
            tooltip += '<em>comment:</em> ' + (file._dzParam.filecomment || 'no comment set');
            propsCheckboxes.each(function ()
            {
                if ($(this).attr('checked'))
                {
                    var name = $(this).attr('name');
                    file._dzParam[name] = 'on';
                    tooltip += '<br/><em>' + name + ':</em> on';
                }
            });

            // ...add an info tooltip with the form parameters
            addTooltip(file.previewElement, tooltip, 'info');

            // ...update progress bar info
            this.updateTotalUploadProgress();

            uploadButton.removeClass('dropZoneActionDisabled');

            // (mostly) done processing files
            dzFiles.unblock();
        });

        // add form parameters to the POST request (the upload)
        dzInst.on('sending', function (file, xhr, form)
        {
            dzDebug('sending file', { file: file, xhr: xhr, form: form, nonce: nonce });
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

            dzFiles.scrollTo($(file.previewElement), 500, { axis: 'y', offset: -40 });
        });

        // update nonce if we got a new one in Foswiki's response
        dzInst.on('complete', function (file)
        {
            dzDebug('complete file', { file: file});
            if (file && file.xhr)
            {
                var newNonce = file.xhr.getResponseHeader('X-Foswiki-Validation');
                dzDebug('success file', { file: file, newNonce: newNonce });
                if (newNonce)
                {
                    nonce = '?' + newNonce;
                }
            }

            // file done after cancelling
            if (!dzInst.options.autoProcessQueue)
            {
                progBar.progressbar('disable');
                uploadButton.show();
                cancelButton.removeClass('dropZoneActionDisabled').hide();
                addButton.removeClass('dropZoneActionDisabled');
                clearButton.removeClass('dropZoneActionDisabled');
            }
        });

        // allow one more file on success
        //dzInst.on('success', function (file)
        //{
        //    dzInst.options.maxFiles++;
        //});

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

    // add a (HTML) tooltip to the element
    function addTooltip(el, tooltip, type)
    {
        $(el).data(
        {
            position: 'bottom', delay: 150, arrow: true, duration: 200, items: el,
            content: tooltip, tooltipClass: ((type || 'default') + ' dropZoneTooltip')
        }).addClass('jqUITooltip');
    }
});

// eof

