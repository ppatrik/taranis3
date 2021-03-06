/*
 * This file is part of Taranis, Copyright NCSC-NL.  See http://taranis.ncsc.nl
 * Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html
 */

function openDialogPublishEosCallback ( params ) {

	var context =  $('#eos-publish-form[data-publicationid="' + params.publicationId + '"]');
	
	$.main.activeDialog.dialog('option', 'buttons', [
		{
			text: 'Set to Pending',
			click: function () {
				$.main.ajaxRequest({
					modName: 'write',
					pageName: 'eos',
					action: 'setEosStatus',
					queryString: 'publicationId=' + params.publicationId + '&status=0',
					success: refreshPublicationList({pub_type: 'eos'})
				});
				
				$('#screen-overlay').hide();
				$(this).dialog('close');
			}
		},
		{
			text: 'Publish',
			click: function () {

				// we're trimming the text because some PGP signing tools add extra newlines at start and/or end of text 
				$('#eos-preview-text', context).val( $.trim( $('#eos-preview-text', context).val() ) );

				var publicationText = encodeURIComponent( $('#eos-preview-text', context).val() );
				
				$.main.ajaxRequest({
					modName: 'publish',
					pageName: 'publish',
					action: 'checkPGPSigning',
					queryString: 'id=' + params.publicationId + '&publicationType=eos&publicationText=' + publicationText,
					success: publishEos
				});
			}
		},
		{
			text: 'Cancel',
			click: function () { $(this).dialog('close') }
		}
	]);
}

function publishEos ( params ) {
	
	var context = $('#eos-publish-form[data-publicationid="' + params.publicationId + '"]');
	
	if ( params.pgpSigningOk == 1 ) {

		$.main.activeDialog.dialog('option', 'buttons', []);
		$.main.activeDialog.html('Publishing End-of-shift...');
		
		$.main.ajaxRequest({
			modName: 'publish',
			pageName: 'publish_eos',
			action: 'publishEos',
			queryString: $(context).serializeWithSpaces() + '&id=' + params.publicationId,
			success: publishEosCallback
		});
		
	} else {
		$(context).siblings('#dialog-error')
			.removeClass('hidden')
			.text(params.message);
	}
}

function publishEosCallback ( params ) {
	// change close event for this dialog
	$.main.activeDialog.bind( "dialogclose", function(event, ui) {
		refreshPublicationList({pub_type: 'eos'});
	});
	
	// setup dialog buttons
	$.main.activeDialog.dialog('option', 'buttons', [
		{
			text: 'Close',
			click: function () { $(this).dialog('close') }
		}
	]);		
}
