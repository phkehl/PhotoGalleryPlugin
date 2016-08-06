/* PhotoGalleryPlugin DropzoneJS Foswiki integration javascript code */

jQuery(function($)
{
    "use strict";

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
        var submitButton       = uplForm.find('input[type=submit]');
        var validationkeyInput = uplForm.find('input[name=validation_key]');
        var filePropsInputs    = uplForm.find('input[type=text], input[type=radio], input[type=checkbox], select');
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

        DEBUG('dropzonejsskin', { uplFileSel: uplFileSel, uplForm: uplForm,
            dzCont: dzCont, uploadAction: uploadAction, dzFiles: dzFiles,
            dzFilesResize: dzFilesResize, validationkeyInput: validationkeyInput,
            filePropsInputs: filePropsInputs, origActionButtons: origActionButtons,
            nonce: nonce, addButton: addButton, clearButton: clearButton,
            uploadButton: uploadButton, cancelButton: cancelButton,
            progBar: progBar, progLabel: progLabel });

        // maximum number of file we allow to upload in one go FIXME: reasonable number?
        var maxNumFiles = 100;

        // other global states
        var uploadStartedTs = 0; // upload started timestamp in [ms]

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
            maxFiles:               maxNumFiles,
            clickable:              $('<div/>').appendTo(dzCont).get(0), // dummy
            paramName:              'filepath',
            dictRemoveFile:         ' ',
            dictFileTooBig:         dictFileTooBig,
            // fall-back to original upload form if the browser isn't supported
            //forceFallback: true, // for testing
            previewTemplate:        '' +
                '<div class="dz-preview dz-file-preview">' +
                '<div class="dz-filename"><span class="dropZoneFileName" data-dz-name></span></div>' +
                '<div class="dz-size"><span data-dz-size></span></div>' +
                '<div class="dz-progress"><span class="dz-upload" data-dz-uploadprogress></span></div>' +
                '<div class="dz-success-mark">&nbsp;</div>' +
                '</div>',
            // restore original upload form if DropzoneJS is not supported by the browser
            fallback: function () { uplFileSel.show(); origActionButtons.show(); dzCont.remove(); }
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

        // ignore file drops on the original form (so that accidential drops outside the
        // DropzoneJS don't load that file)
        $('body').on('drop dragover', function (e)
        {
            e.preventDefault();
            e.stopPropagation();
        });
        DEBUG('uplForm', uplForm);

        // reset inputs to the original state FIXME: doesn't work :-(
        //uplForm.find('input[type=checkbox]').each(function () { $(this).prop('checked', $(this).attr('checked') ? true : false); });
        //uplForm.find('input[type=text]').each(function () { $(this).val( $(this).attr('value') ); });


        /* ***** arm the DropzoneJS interactions ************************************************* */

        // on error, add a tooltip to the file entry with the error message
        dzInst.on('error', function (file, msg, xhr)
        {
            DEBUG('error file: ' + msg, [ file, xhr ]);
            addTooltip(file.previewElement, msg, 'error');
        });

        // display a message while DropzoneJS is processing dropped/added files
        dzInst.on('drop', function (e)
        {
            dzFiles.block({ message: 'Processing files&hellip;' });
        });

        // arm buttons tooltips, FIXME: these don't work reliably and will stick occasionally
        //[ addButton, clearButton, uploadButton, cancelButton ].forEach(function (el)
        //{
        //    addTooltip(el, el.attr('title'), 'help');
        //});

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
            updateAttachmentsTable(dzInst.files.map(function (x) { return x.name; }));
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
            this.files.forEach(function (f)
            {
                if (f.upload)
                {
                    totalBytes += f.upload.total || 0;
                    totalBytesSent += f.upload.bytesSent || 0;
                }
            });
            uploadProgress = totalBytes ? (totalBytesSent / totalBytes * 1e2) : 0;

            // calculate upload speed
            var speedStr = '??';
            if (uploadProgress && uploadStartedTs)
            {
                var dt = (+(new Date) - uploadStartedTs) * 1e-3;
                DEBUG('speed: ' + dt.toFixed(1) + ' ' + totalBytesSent);
                var speed = totalBytesSent / dt;
                speedStr = this.filesize(speed) + '/s';
            }

            // update progress bar and its text
            progBar.progressbar('value', uploadProgress);
            if (uploadProgress)
            {
                progLabel.html('Uploaded  ' + this.filesize(totalBytesSent) + ' of ' + this.filesize(totalBytes)
                               + ' (' + uploadProgress.toFixed(0) + '%, ' + speedStr + ').');
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
            DEBUG('addedfile file', { file: file } );

            // ...add a tooltip to the remove icon
            //addTooltip(file._removeLink, dictRemoveFile, 'help');
            $(file._removeLink).attr('title', dictRemoveFile);
            // destroy tooltip object or we'll end up with a stray tooltip sticking on the page
            $(file._removeLink).on('click', function ()
            {
                //if ($(this).hasClass('jqInitedTooltip'))
                //{
                //    $(this).tooltip('destroy')
                //}
                $(this).parents('.dz-preview.jqInitedTooltip').tooltip('destroy');
            });

            // ...update progress bar info
            this.updateTotalUploadProgress();

            // ...save form data
            formToData($(file.previewElement), filePropsInputs)

            uploadButton.removeClass('dropZoneActionDisabled');

            // (mostly) done processing files
            dzFiles.unblock();
        });

        // add form parameters to the POST request (the upload)
        dzInst.on('sending', function (file, xhr, form)
        {
            DEBUG('sending file', { file: file, xhr: xhr, form: form, nonce: nonce });

            // set required foswiki upload form data
            form.append('noredirect', 1);
            if (nonce.charAt(0) == '?')
            {
                form.append('validation_key', StrikeOne.calculateNewKey(nonce));
            }
            else if (nonce)
            {
                form.append('validation_key', nonce);
            }

            // set all the data from the upload form
            var data = $(file.previewElement).data('uploadFormData');
            DEBUG('data', data);
            Object.keys(data).forEach(function (k)
            {
                form.append(k, data[k]);
            });

            dzFiles.scrollTo($(file.previewElement), 500, { axis: 'y', offset: -40 });
        });

        // update nonce if we got a new one in Foswiki's response
        dzInst.on('complete', function (file)
        {
            DEBUG('complete file', { file: file});
            if (file && file.xhr)
            {
                var newNonce = file.xhr.getResponseHeader('X-Foswiki-Validation');
                DEBUG('success file', { file: file, newNonce: newNonce });
                if (newNonce)
                {
                    nonce = '?' + newNonce;
                }
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
                updateAttachmentsTable(dzInst.files.map(function (x) { return x.name; }));
            }
        });

        // allow one more file on success
        //dzInst.on('success', function (file)
        //{
        //    dzInst.options.maxFiles++;
        //});

        // allow selecting a file by clicking the filename
        // and sync selected file with file upload properties form
        var formHighlight = filePropsInputs.parents('.foswikiFormStep');
        var selectedFile = undefined;
        var formDefaults = $('<div/>').appendTo(dzCont);
        formToData(formDefaults, filePropsInputs);
        // clicking the filename with select/deselect the file
        dzFiles.on('click', '.dropZoneFileName', function (e)
        {
            //DEBUG('click', $(this));
            e.stopPropagation();
            formHighlight.effect('highlight');
            if ($(this).hasClass('dropZoneSelected'))
            {
                $(this).removeClass('dropZoneSelected');
                selectedFile = undefined;
                dataToForm(formDefaults, filePropsInputs);
                return;
            }
            if (selectedFile)
            {
                selectedFile.removeClass('dropZoneSelected');
            }
            selectedFile = $(this);
            selectedFile.addClass('dropZoneSelected');
            var dzPreview = $(this).parents('.dz-preview');
            if (dzPreview.hasClass('dz-error'))
            {
                filePropsInputs.attr('disabled', true);
            }
            else
            {
                filePropsInputs.attr('disabled', false);
            }
            dataToForm(dzPreview, filePropsInputs);

        });
        // clicking outside will deselct the currently selected file (if any)
        dzFiles.on('click', function (e)
        {
            //DEBUG('click', $(this));
            if (selectedFile)
            {
                selectedFile.trigger('click');
            }
        });
        // update the saved file upload props when the form inputs change
        filePropsInputs.on('change', function (e)
        {
            //DEBUG('change', $(this));
            if (selectedFile)
            {
                formToData(selectedFile.parents('.dz-preview'), filePropsInputs);
            }
        });
        var inpKeyupTo; // debounce
        filePropsInputs.on('keyup', function (e)
        {
            if (inpKeyupTo)
            {
                clearTimeout(inpKeyupTo);
            }
            var $this = $(this);
            inpKeyupTo = setTimeout(function ()
            {
                if (selectedFile)
                {
                    formToData(selectedFile.parents('.dz-preview'), filePropsInputs);
                }
            }, 250);
        });
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
            position: 'bottom', delay: 250, arrow: true, duration: 200, items: el,
            content: tooltip, tooltipClass: ((type || 'default') + ' dropZoneTooltip')
        }).addClass('jqUITooltip');
    }

    // save form data to the file element
    function formToData(target, inputs)
    {
        var data = {};
        inputs.each(function (ix, inp)
        {
            inp = $(inp);
            var name = inp.attr('name');
            var value;
            if (inp.is('input[type=checkbox], input[type=radio]'))
            {
                value = inp.prop('checked') ? 'on' : '';
            }
            else
            {
                value = inp.val();
            }
            data[name] = value;
        });
        target.data('uploadFormData', data);
        target.effect('highlight');
        DEBUG('formToData', [ target, data ]);
    }

    // load form data from the file element
    function dataToForm(target, inputs)
    {
        var data = target.data('uploadFormData') || {};
        inputs.each(function (ix, inp)
        {
            inp = $(inp);
            var name = inp.attr('name');
            if (inp.is('input[type=checkbox], input[type=radio]'))
            {
                inp.prop('checked', data[name] ? true : false);
            }
            else
            {
                inp.val(data[name]);
            }
        });
    }

    function updateAttachmentsTable(filenames)
    {
        DEBUG('updateAttachmentsTable', filenames);
        var orig = $('div.foswikiAttachments');
        orig.block({ message: 'Refreshing&hellip;' });
        $.ajax(
        {
            method: 'GET', timeout: 20000,
            url: foswiki.getScriptUrlPath('rest') + '/RenderPlugin/template',
            data: { name: 'attach', expand: 'existingattachments', 'render' : 'on',
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
                        if (trText.match(fn))
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
            }
        });
    }
});

// eof

