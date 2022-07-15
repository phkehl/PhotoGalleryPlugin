/* PhotoGalleryPlugin DropzoneJS Foswiki integration javascript code */

"use strict";

jQuery(function($)
{
    // add "debug=1" to the query string to enable debugging
    var doDEBUG = location && location.href && (location.href.indexOf('debug=1') >= 0) ? true : false;

    $(document).ready(function()
    {
        /* ***** prepare ************************************************************************* */

        // don't do anything for the "attachagain" action
        if (location && location.href && (location.href.indexOf('filename=') >= 0))
        {
            return;
        }

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
        var validationkeyInput = uplForm.find('input[name=validation_key]');
        var filePropsCheckboxes= uplForm.find('input[type=checkbox]');
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

        DEBUG('dropzonejsskin', { uplFileSel: uplFileSel, uplForm: uplForm,
            dzCont: dzCont, uploadAction: uploadAction, dzFiles: dzFiles,
            dzFilesResize: dzFilesResize, validationkeyInput: validationkeyInput,
            filePropsCheckboxes: filePropsCheckboxes,
            nonce: nonce, addButton: addButton, clearButton: clearButton,
            uploadButton: uploadButton, cancelButton: cancelButton,
            progBar: progBar, progLabel: progLabel });

        // maximum number of file we allow to upload in one go FIXME: is this reasonable number?
        var maxNumFiles = 100;

        // other global states
        var uploadStartedTs = 0; // upload started timestamp in [ms]


        /* ***** get file properties inputs ****************************************************** */

        var dzCheckboxesHtml = '';
        var dzCheckboxesHelp = '';
        filePropsCheckboxes.each(function ()
        {
            var cb = $(this);
            var id = cb.attr('id');
            var name = cb.attr('name');
            var tooltip = '';
            var filenamematch = '';
            if (id)
            {
                var label = uplForm.find('label[for=' + id + ']');
                if (label)
                {
                    tooltip += label.text(); // use original label as new checkbox tooltip
                    var info = label.next(); // and add info <span> next to the original label, too
                    if (info.is('span'))
                    {
                        tooltip += ' (' + info.text() + ')';
                    }
                }
                if (cb.data('filenamematch'))
                {
                    filenamematch = cb.data('filenamematch');
                }
            }
            dzCheckboxesHtml += '<label class="dropZoneAttrCb checkbox" title="' + escAttr(tooltip) + '">'
                + '<input type="checkbox" name="' + name + '" value="on"'
                + (cb.is(':checked') ? ' checked' : '') + ' data-filenamematch="' + filenamematch + '"/>'
                + '<span></span></label>';
            dzCheckboxesHelp += '<li>' + tooltip + '</li>';
        });
        $('#bulkuploadattrhelp').append(dzCheckboxesHelp);


        /* ***** initialise the DropzoneJS thingy ************************************************ */

        // put dropzone div in place of the upload file selector
        dzCont.insertAfter(uplForm);
        uplForm.hide();

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
            addRemoveLinks:         false, // we do it ourselves
            parallelUploads:        1,
            createImageThumbnails:  false,
            maxFiles:               maxNumFiles,
            clickable:              $('<div/>').appendTo(dzCont).get(0), // dummy
            paramName:              'filepath',
            dictRemoveFile:         ' ',
            dictFileTooBig:         dictFileTooBig,
            // fall-back to original upload form if the browser isn't supported
            //forceFallback: true, // for testing
            previewTemplate:        '' +
                '<div class="dz-preview dz-file-preview dropZoneSortable">' +
                  '<div class="dropZoneFileSortHandle"></div>' +
                  '<div class="dz-filename"><span class="dropZoneFileName" data-dz-name></span></div>' +
                  //'<div class="dz-filename"><input class="dropZoneFileName" data-dz-name/></div>' + // nope... :-(
                  '<div class="dz-size"><span data-dz-size></span></div>' +
                  '<div class="dz-progress"><span class="dz-upload" data-dz-uploadprogress></span></div>' +
                  '<div class="dz-success-mark">&nbsp;</div>' +
                  '<a class="dz-remove" data-dz-remove="" title="Remove from queue."></a>' +
                  '<div class="dropZoneForm">' +
                    dzCheckboxesHtml +
                    '<input class="comment" type="text" name="filecomment" placeholder="file comment"' +
                    ' style="width: calc(100% - ' + filePropsCheckboxes.length + ' * 1.5em - 0.75em);"/>' +
                  '</div>' +
                '</div>',
            // restore original upload form if DropzoneJS is not supported by the browser
            fallback: function () { uplForm.show(); dzCont.remove(); }
        };
        DEBUG('dzOpts', dzOpts);

        // initialise the DropzoneJS...
        var dzInst = new Dropzone(dzFiles.get(0), dzOpts);
        if (!dzInst)
        {
            return;
        }
        // ...and style and show it
        dzFiles.addClass('dropzone');
        dzCont.show();
        DEBUG('instance', dzInst);
        var msg = dzCont.find('.dropZoneDictDefaultMessage');
        msg.html( msg.html()
                  .replace('{{maxfilesize}}', dzInst.filesize(maxFileSize))
                  .replace('{{maxnumfiles}}', maxNumFiles) );

        // make the dropzone resizable in height (but not width)
        dzFilesResize.resizable({ handles: 's' });

        // make the dropzone files sortable
        function makeSortable()
        {
            if (dzFiles.hasClass('ui-sortable'))
            {
                dzFiles.sortable('destroy');
            }
            dzFiles.sortable(
            {
                items: 'div.dropZoneSortable',
                opacity: 0.5, axis: 'y', cursor: 'move', handle: '.dropZoneFileSortHandle',
                // order dropzone's internal file list accordingly
                stop: function (e, ui)
                {
                    var order = $(this).find('.dropZoneFileName').map(function () { return $(this).data('orig'); }).get();
                    dzInst.files = dzInst.files.sort(function (a, b)
                    {
                        return order.indexOf(a.name) - order.indexOf(b.name);
                    });
                }
            });
        }
        makeSortable();

        // ignore file drops on the original form (so that accidential drops outside the
        // DropzoneJS don't load that file)
        $('body').on('drop dragover', function (e)
        {
            e.preventDefault();
            e.stopPropagation();
        });
        DEBUG('uplForm', uplForm);


        /* ***** arm the DropzoneJS interactions ************************************************* */

        // on error, add a tooltip to the file entry with the error message
        dzInst.on('error', function (file, msg, xhr)
        {
            DEBUG('error file: ' + msg, [ file, xhr, $(file.previewElement) ]);
            var preview = $(file.previewElement);
            preview.find('.dropZoneForm').remove();
            $('<div>').addClass('dropZoneErrorMessage').text(msg).appendTo(preview);
            preview.find('.dropZoneFileName').attr('readonly', true);
        });

        // display a message while DropzoneJS is processing dropped/added files
        dzInst.on('drop', function (e)
        {
            dzFiles.block({ message: 'Processing files&hellip;' });
        });

        // open file selection dialog (see also dzOpts.clickable)
        addButton.on('click', function (e)
        {
            e.preventDefault();
            if ($(this).hasClass('dropZoneActionDisabled'))
            {
                DEBUG('hasclass', $(this));
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
            clearButton.addClass('dropZoneActionDisabled');
        });

        // start upload
        uploadButton.on('click', function (e)
        {
            e.preventDefault();
            if ($(this).hasClass('dropZoneActionDisabled'))
            {
                return;
            }
            DEBUG('upload', { e: e });
            dzInst.processQueue();
            dzInst.options.autoProcessQueue = true;
            progBar.progressbar('value', undefined);
            progBar.progressbar('enable');
            uploadButton.hide();
            cancelButton.show();
            addButton.addClass('dropZoneActionDisabled');
            clearButton.addClass('dropZoneActionDisabled');
            uploadStartedTs = +(new Date);
        });
        uploadButton.addClass('dropZoneActionDisabled');
        clearButton.addClass('dropZoneActionDisabled');

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
        // FIXME: why is this triggered when a too big file is added?! (we don't want to disable the Upload button)
        dzInst.on('queuecomplete', function ()
        {
            dzInst.options.autoProcessQueue = false;
            progBar.progressbar('disable');
            uploadButton.show();
            cancelButton.hide();
            addButton.removeClass('dropZoneActionDisabled');
            clearButton.removeClass('dropZoneActionDisabled');
            if (uploadStartedTs)
            {
                uploadButton.addClass('dropZoneActionDisabled');
                updateAttachmentsTable(dzInst.files.map(function (x) { return x.ourName; }));
            }
            uploadStartedTs = 0;
        });

        dzInst.on('removedfile', function (file)
        {
            //DEBUG('removedfile', [ this, file ]);
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
            //DEBUG('uploadprogress', [ this, uploadProgress, totalBytes, totalBytesSent ]);
            // need to recalculate these because DropzoneJS calculates rubbish
            uploadProgress = totalBytes = totalBytesSent = 0;
            var nDone = 0;
            this.files.forEach(function (f)
            {
                if (f.upload)
                {
                    totalBytes += f.upload.total || 0;
                    totalBytesSent += f.upload.bytesSent || 0;
                }
                if (f.status === 'success')
                {
                    nDone++;
                }
            });
            uploadProgress = totalBytes ? (totalBytesSent / totalBytes * 1e2) : 0;
            if (uploadProgress && (totalBytesSent === totalBytes))
            {
                nDone = this.files.length;
            }

            // calculate upload speed
            var speedStr = '';
            if (uploadProgress && uploadStartedTs)
            {
                var dt = (+(new Date) - uploadStartedTs) * 1e-3;
                var speed = totalBytesSent / dt;
                speedStr = ', ' + this.filesize(speed) + '/s';
            }

            // update progress bar and its text
            progBar.progressbar('value', uploadProgress);
            if (uploadProgress)
            {
                progLabel.html('Uploaded  ' + nDone + ' of ' + this.files.length
                               + ' (' + this.filesize(totalBytesSent) + ' of ' + this.filesize(totalBytes)
                               + ', ' + uploadProgress.toFixed(0) + '%' + speedStr + ').');
            }
            else
            {
                progLabel.html('Nothing uploaded yet.');
            }
        });
        dzInst.updateTotalUploadProgress();

        // when a file is dropped or added...
        dzInst.on('addedfile', function (file)
        {
            DEBUG('addedfile file', [ file, file.previewElement ] );
            var dzPreview = $(file.previewElement);

            // ...replace filename <span> with <input>
            var fnSpan = dzPreview.find('.dropZoneFileName');
            var fnInput = $('<input>').addClass('dropZoneFileName').val(fnSpan.text())
                .data('orig', fnSpan.text()).attr('placeholder', 'filename');
            fnSpan.replaceWith(fnInput);

            // ...reset filename if field is left empty
            fnInput.on('focusout', function (e)
            {
                if (!fnInput.val())
                {
                    fnInput.val(fnInput.data('orig')).effect('highlight', 2000);
                }
            });

            // ...remove leading and trainling whitespace
            fnInput.on('keyup', function (e)
            {
                var val = fnInput.val();
                var val2 = val.replace(/^\s*/, '').replace(/\s*$/, '');
                if (val != val2)
                {
                    fnInput.val(val2).effect('highlight').trigger('focusout');
                }
            });

            // TODO: strip leading and trailing whitespace

            // ...add a tooltip to the remove icon
            $(file._removeLink).attr('title', dictRemoveFile);

            // ...disable checkbox that are not applicable (if possible)
            dzPreview.find('.dropZoneAttrCb input').each(function ()
            {
                var cb = $(this);
                var fnmatch = cb.data('filenamematch');
                var fn = fnInput.val();
                if (fnmatch && fnmatch.length && fn && fn.length)
                {
                    var match = false;
                    try
                    {
                        var re = new RegExp(fnmatch, 'i');
                        match = re.test(fn);
                    }
                    catch (e)
                    {
                        match = false;
                    }
                    if (!match)
                    {
                        cb.prop('checked', false).attr('disabled', true);
                        cb.parent().addClass('dropZoneAttrCbNotAvail').attr('title', 'not available for this file');
                    }
                }
            });

            // add double-click handler
            dzPreview.find('.dropZoneAttrCb').on('dblclick', function (e)
            {
                e.preventDefault();
                e.stopPropagation();
                if (dzPreview.hasClass('dz-complete'))
                {
                    return;
                }

                var cbDiv = $(this);
                var input = cbDiv.find('input');
                var status = input.is(':checked');
                var name   = input.attr('name');
                dzFiles.find('input[name=' + name + ']').each(function ()
                {
                    var inp = $(this);
                    if (!inp.parent().hasClass('dropZoneAttrCbNotAvail') &&
                        !inp.parents('.dz-preview').hasClass('dz-complete') )
                    {
                        inp.prop('checked', status);
                    }
                });

            });

            // ...update progress bar info
            this.updateTotalUploadProgress();

            uploadButton.removeClass('dropZoneActionDisabled');
            clearButton.removeClass('dropZoneActionDisabled');

            // (mostly) done processing files
            dzFiles.unblock();
        });

        // add form parameters to the POST request (the upload)
        dzInst.on('sending', function (file, xhr, form)
        {
            DEBUG('sending file', { file: file, xhr: xhr, form: form, nonce: nonce });

            // set required foswiki upload form data
            form.append('noredirect', 1);
            if (nonce !== undefined)
            {
                if ( (nonce.charAt(0) == '?') && (typeof StrikeOne === 'object') )
                {
                    form.append('validation_key', StrikeOne.calculateNewKey(nonce));
                }
                else if (nonce)
                {
                    form.append('validation_key', nonce);
                }
            }

            var dropZoneForm = $(file.previewElement).find('.dropZoneForm');
            var dropZoneFileName = $(file.previewElement).find('.dropZoneFileName');

            // disable inputs
            dropZoneForm.find('input[type=checkbox]').attr('disabled', true);
            dropZoneForm.find('input[type=text]').attr('readonly', true);
            dropZoneFileName.attr('readonly', true);

            // set all the data from the upload form
            dropZoneForm.find('input[type=checkbox]').each(function ()
            {
                if ($(this).is(':checked'))
                {
                    form.append($(this).attr('name'), 'on');
                }
            });
            dropZoneForm.find('input[type=text]').each(function ()
            {
                form.append($(this).attr('name'), $(this).val());
            });
            form.append('filename', dropZoneFileName.val());
            //file.name = dropZoneFileName.val(); // read-only :-(
            file.ourName = dropZoneFileName.val();

            // we cannot CSS style the placeholder (easily), so set an invisible dummy value for empty elements
            dropZoneForm.find('input[type=text]').each(function ()
            {
                if (!$(this).val()) { $(this).val(' '); }
            });

            dzFiles.scrollTo($(file.previewElement), 500, { axis: 'y', offset: -40 });

            // this file is now no longer sortable
            $(file.previewElement).removeClass('dropZoneSortable');
            //dzFiles.sortable('refresh').sortable('refreshPositions');
            makeSortable(); // 'refresh' isn't enough... :-(
        });

        // update nonce if we got a new one in Foswiki's response
        dzInst.on('complete', function (file)
        {
            DEBUG('complete file', { file: file });
            if (file && file.xhr)
            {
                var newNonce = file.xhr.getResponseHeader('X-Foswiki-Validation');
                DEBUG('success file', { file: file, newNonce: newNonce });
                if (newNonce)
                {
                    nonce = '?' + newNonce;
                }

                // consider filename change
                var res = file.xhr.responseText;
                // OK: IMG_1555.JPG uploaded
                // OK: OopsException(attention/upload_name_changed web=>Sandbox topic=>BlaBlaTest params=>[IMG_1555 (foo "bar").JPG,IMG_1555 (foo bar).JPG])
                if (res.indexOf('upload_name_changed') > 0)
                {
                    var offs = res.indexOf(file.ourName) + file.ourName.length + 1;
                    var newName = res.substr(offs, res.length - offs - 2);
                    if (newName)
                    {
                        DEBUG('file name change: ' + file.ourName + ' -> ' + newName);
                        file.ourName = newName;
                        $(file.previewElement).find('.dropZoneFileName').val(newName).effect('highlight', 2000);
                    }
                }
            }

            // this file is now no longer sortable
            $(file.previewElement).removeClass('dropZoneSortable');
            //dzFiles.sortable('refresh').sortable('refreshPositions');
            makeSortable(); // 'refresh' isn't enough... :-(

            if (file && (file.status == 'error'))
            {
                return;
            }

            // file done after cancelling, do stuff we otherwise would do in the
            // "queuecomplete" handler
            if (!dzInst.options.autoProcessQueue)
            {
                progBar.progressbar('disable');
                uploadButton.show();
                cancelButton.removeClass('dropZoneActionDisabled').hide();
                addButton.removeClass('dropZoneActionDisabled');
                clearButton.removeClass('dropZoneActionDisabled');
                updateAttachmentsTable(dzInst.files.map(function (x) { return x.ourName; }));
            }
        });

        // allow one more file on success
        //dzInst.on('success', function (file)
        //{
        //    dzInst.options.maxFiles++;
        //});

    });

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
                console.log('dz: ' + strOrObj + ': %o', obj);
            }
            else if (typeof strOrObj === 'object')
            {
                console.log('dz: %o', strOrObj);
            }
            else
            {
                console.log('dz: ' + strOrObj);
            }
        }
    }

    // escape string so that it's suitable for HTML attributes
    function escAttr(str)
    {
        return str.replace('<', '&lt;').replace('>', '&gt;').replace('"', '&quot;');
    }

    // reload attachments table and highlight newly uploaded files
    function updateAttachmentsTable(filenames)
    {
        var orig = $('div.foswikiAttachments');
        DEBUG('updateAttachmentsTable', [ filenames, orig ]);
        orig.block({ message: 'Refreshing&hellip;' });
        $.ajax(
        {
            method: 'GET', timeout: 20000,
            url: foswiki.getScriptUrlPath('rest') + '/RenderPlugin/template',
            data: { name: 'attach', expand: 'existingattachments', render: 'on',
                    topic: foswiki.preferences.WEB + '/' + foswiki.preferences.TOPIC },
            complete:  function (jqXHR, textStatus)
            {
                orig.unblock();
            },
            success: function (data, textStatus, jqXHR)
            {
                //DEBUG('data', data);
                // abort if it doesn't seem to contain the table
                if (data.indexOf('foswikiAttachments') < 0)
                {
                    return;
                }
                // add table if there are no previous attachments
                if (!orig.length)
                {
                    $('div.foswikiTopic').append(data);
                }
                // replace table
                else
                {
                    var table = $('<div>').html(data);
                    orig.html(table.find('div.foswikiAttachments table'));
                }
                // highlight uploaded files
                $('div.foswikiAttachments table tr').filter(function ()
                {
                    var trText = $(this).text();
                    var res = false;
                    filenames.forEach(function (fn)
                    {
                        if (trText.indexOf(fn) > -1)
                        {
                            res = true;
                        }
                    });
                    return res;
                })
                    .removeClass(function (ix, cls)
                    {
                        return (cls.match(/(^| +)foswikiTableRowdataBg[^ ]+/g) || []).join(' ');
                    })
                    .addClass('bulkUploadHighlight');
            },
            error: function (jqXHR, textStatus, errorThrown)
            {
                // whatever.. perhaps the RenderPlugin is not installed
                DEBUG('RenderPlugin not installed and activated?');
                $.pnotify({ type: 'warning', width: '50em', delay: 8000,
                            text: 'Could not refresh attachment table. RenderPlugin not installed or activated?' });
            }
        });
    }
});

// eof

