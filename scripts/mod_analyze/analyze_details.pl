#!/usr/bin/perl	
# This file is part of Taranis, Copyright NCSC-NL. See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

use Taranis::Analysis;
use Taranis::Assess;
use Taranis::Database qw(withTransaction);
use Taranis::Users qw(getUserRights);
use Taranis::Template;
use Taranis::Tagging;
use Taranis::MetaSearch;
use Taranis::Config;
use Taranis::SessionUtil qw(setUserAction right getSessionUserSettings);
use Taranis::FunctionalWrapper qw(Config Users);
use Taranis::Session qw(sessionGet);
use Taranis qw(:all);
use strict;

my @EXPORT_OK = qw(
	openDialogAnalyzeDetails saveAnalyzeDetails openDialogNewAnalysis
	saveNewAnalysis closeAnalysis analyzeDetailsMetaSearch openDialogAnalyzeDetailsReadOnly
);

sub analyze_details_export {
	return @EXPORT_OK;
}

sub openDialogAnalyzeDetails {
	my ( %kvArgs ) = @_;
	my ( $vars, $tpl, $message, $locked, $openedByFullname, $isJoined );

	my $oTaranisAnalysis = Taranis::Analysis->new( Config );
	my $oTaranisTemplate = Taranis::Template->new;
	my $oTaranisTagging = Taranis::Tagging->new( Config );

	$vars->{pageSettings} = getSessionUserSettings();
	my $id = val_int $kvArgs{id};

	if ( $id ) {
		my $analysis = $oTaranisAnalysis->getRecordsById( table => "analysis", id => $id )->[0];

		$isJoined = ( $analysis->{status} =~ /^joined$/i ) ? 1 : 0;

		$analysis->{idstring} = trim( $analysis->{idstring} );
		$analysis->{name}     = analysis_name $id;

	    $vars->{analysis} = $analysis;
		$vars->{items} = $oTaranisAnalysis->getLinkedItems( $id );
		my $tags = $oTaranisTagging->getTagsByItem( $id, "analysis" );
		$vars->{tags} = "@$tags";

		my $userId = sessionGet('userid');

		if ( my $openedBy = $oTaranisAnalysis->isOpenedBy( $id ) ) {
			$locked = ( $openedBy->{opened_by} =~ $userId ) ? 0 : 1;
			$vars->{openedByFullname} = $openedBy->{fullname};
		} elsif( right("write") ) {
			if ( $oTaranisAnalysis->openAnalysis( $userId, $id ) ) {
				$locked = 0;
			} else {
				$locked = 1;
			}
		} else {
			$locked = 1;
		}
		$tpl = 'analyze_details.tt';
	} else {
		$tpl = 'dialog_no_right.tt';
		$message = 'Invalid id...';
	}

	$vars->{isLocked} = $locked;

	my $dialogContent = $oTaranisTemplate->processTemplate( $tpl, $vars, 1 );

	return {
		dialog => $dialogContent,
		params => {
			id => $id,
			isLocked => $locked,
			isJoined => $isJoined
		}
	};
}

sub openDialogNewAnalysis {
	my ( %kvArgs ) = @_;
	my ( $vars, $tpl );

	my $oTaranisTemplate = Taranis::Template->new;

	if ( right("write") ) {
		my $username = sessionGet('userid');
		my $fullname = Users->getUser($username)->{fullname};
		my $date     = nowstring(7);

		$vars->{newAnalysis} = 1;
		$vars->{analysis}{status} = 'pending';
		$vars->{analysis}{comments} = "[== Created manually by $fullname on $date ==]\n\n";
		$vars->{pageSettings} = getSessionUserSettings();
		$tpl = "analyze_details_tab1.tt";
	} else {
		$tpl = "dialog_no_right.tt";
		$vars->{message} = 'No rights...'; 	
	}	

	my $dialogContent = $oTaranisTemplate->processTemplate( $tpl, $vars, 1 );		

	return { dialog => $dialogContent };
}

sub saveNewAnalysis {
	my ( %kvArgs ) = @_;
	my ( $message, $analysisId );

	my $analysisIsAdded = 0;
	my $tagsAreSaved = 0;

	if ( right("write") ) {
		my $oTaranisAnalysis = Taranis::Analysis->new( Config );
		my $idstring = join ' ', $kvArgs{idstring} =~ /(CVE-\d{4}-\d{4,10})/g;

		if ( $analysisId = $oTaranisAnalysis->addObject( 	
			table => "analysis",
			title => $kvArgs{title},
			comments => $kvArgs{comments},
			idstring => $idstring,
			rating => $kvArgs{rating},
			status => $kvArgs{status}
		)) {
			my @tags = grep length, split /[\s,]+/, $kvArgs{tags};
			$tagsAreSaved = 1 if !@tags;

			if ( $analysisId ) {

				my $oTaranisTagging = Taranis::Tagging->new( Config );
				withTransaction {
					foreach my $t ( @tags ) {
						$t = trim( $t );

						my $tag_id;
						if ( !$oTaranisTagging->{dbh}->checkIfExists( { name => $t }, "tag", "IGNORE_CASE" ) ) {
							$oTaranisTagging->addTag( $t );
							$tag_id = $oTaranisTagging->{dbh}->getLastInsertedId( "tag" );
						} else {
							$tag_id = $oTaranisTagging->getTagId( $t );
						}

						if ( !$oTaranisTagging->setItemTag( $tag_id, "analysis", $analysisId ) ) {
							$message = $oTaranisTagging->{errmsg};
						}
					}
				};

			} else {
				$message = "Cannot save tag(s), missing analysis id."
			}

			if ( $message ) {
				$message .= " The analysis has been saved.";
			} else {
				$tagsAreSaved = 1;
			}

			$analysisIsAdded = 1;
		} else {
			$message = $oTaranisAnalysis->{errmsg};
		}	
	}

	if ( $analysisIsAdded ) {
		setUserAction( action => 'add analysis', comment => "Added analysis with ID ". analysis_name $analysisId);
	} else {
		setUserAction( action => 'add analysis', comment => "Got error while trying to add analysis with title '$kvArgs{title}'");
	}

	return {
		params => {
			analysisIsAdded => $analysisIsAdded,
			message => $message,
			tagsAreSaved => $tagsAreSaved,
			id => $analysisId
		}
	};
}

sub saveAnalyzeDetails {
	my ( %kvArgs ) = @_;
	my ( $message );
	my $oTaranisAnalysis = Taranis::Analysis->new( Config );

	my $isSaved = 0;
	my $analysisId = ( exists($kvArgs{id}) && $kvArgs{id} =~ /^\d{8}$/ ) ? $kvArgs{id} : undef;	

	if ( $analysisId ) {
		my $analysisName = analysis_name $analysisId;
        my $idstring = join ' ', $kvArgs{idstring} =~ /(CVE-\d{4}-\d{4,10})/g;

		if ( !$oTaranisAnalysis->setAnalysis(
			id => $analysisId,
			title => $kvArgs{title},
			comments => $kvArgs{comments},
			idstring => $idstring,
			rating => $kvArgs{rating},
			status => $kvArgs{status},
			original_status => $kvArgs{original_status}
		)) {
			$message = $oTaranisAnalysis->{errmsg};
			setUserAction( action => 'edit analysis', comment => "Got error while trying to edit analysis $analysisName");
		} else {
			$isSaved = 1;
			setUserAction( action => 'edit analysis', comment => "Edited analysis $analysisName");
		}
	} else {
		$message = 'Invalid id...';
	}

	return {
		params => {
			isSaved => $isSaved,
			message => $message,
			analysisId => $analysisId
		}
	};
}

sub closeAnalysis {
	my ( %kvArgs ) = @_;

	my $oTaranisAnalysis = Taranis::Analysis->new( Config );

	my $id = $kvArgs{id};

	my $userid = sessionGet('userid');

	my $is_admin = getUserRights(
		entitlement => "admin_generic",
		username => $userid
	)->{admin_generic}->{write_right};

	my $openedBy = $oTaranisAnalysis->isOpenedBy( $id );

	if ( ( exists( $openedBy->{opened_by} ) && $openedBy->{opened_by} eq $userid ) || $is_admin ) {
		$oTaranisAnalysis->closeAnalysis( $id );
	}

	return {
		params => {
			id => $id,
			removeItem => $kvArgs{removeItem}
		}
	};
}

sub analyzeDetailsMetaSearch {
	my ( %kvArgs ) = @_;
	my ( $vars );

	my $oTaranisTemplate = Taranis::Template->new;
	my $oTaranisMetaSearch = Taranis::MetaSearch->new;

	my $searchArchive = !! $kvArgs{archive};
	my $analysisId = $kvArgs{id};

	$vars->{results} = $oTaranisMetaSearch->search(
		search_field => trim($kvArgs{ids}),
		item         => { archive => $searchArchive },
		analyze      => { searchAnalyze => 1 },
		publication  => { searchAllProducts => 1 },
		publication_advisory  => { status => 3 },
		publication_endofweek => { status => 3 },
	);

	my $analyzeDetailsTab3Html = $oTaranisTemplate->processTemplate( 'analyze_details_tab3.tt', $vars, 1 );

	return {
		params => {
			searchResultsHtml => $analyzeDetailsTab3Html,
			id => $analysisId
		}
	};
}

sub openDialogAnalyzeDetailsReadOnly {
	my ( %kvArgs ) = @_;
	my ( $vars, $tpl, $message );

	my $oTaranisAnalysis = Taranis::Analysis->new( Config );
	my $oTaranisTemplate = Taranis::Template->new;

	$vars->{pageSettings} = getSessionUserSettings();

	if ( $kvArgs{id} =~ /^\d{8}$/ ) {
		my $analysis = $oTaranisAnalysis->getRecordsById( table => "analysis", id => $kvArgs{id} )->[0];

		$analysis->{idstring} = trim( $analysis->{idstring} );

		$vars->{analysis} = $analysis;
		$vars->{items} = $oTaranisAnalysis->getLinkedItems( $kvArgs{id} );

		my $userId = sessionGet('userid');

		$tpl = 'analyze_details_readonly.tt';
	} else {
		$tpl = 'dialog_no_right.tt';
		$message = 'Invalid id...';
	}

	my $dialogContent = $oTaranisTemplate->processTemplate( $tpl, $vars, 1 );

	return { dialog => $dialogContent };
}

1;
