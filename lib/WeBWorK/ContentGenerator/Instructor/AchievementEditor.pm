################################################################################
# WeBWorK Online Homework Delivery System
# Copyright � 2000-2007 The WeBWorK Project, http://openwebwork.sf.net/
# $CVSHeader: webwork2/lib/WeBWorK/ContentGenerator/Skeleton.pm,v 1.5 2006/07/08 14:07:34 gage Exp $
# 
# This program is free software; you can redistribute it and/or modify it under
# the terms of either: (a) the GNU General Public License as published by the
# Free Software Foundation; either version 2, or (at your option) any later
# version, or (b) the "Artistic License" which comes with this package.
# 
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE.  See either the GNU General Public License or the
# Artistic License for more details.
################################################################################

package WeBWorK::ContentGenerator::Instructor::AchievementEditor;
use base qw(WeBWorK);
use base qw(WeBWorK::ContentGenerator::Instructor);
use base qw(WeBWorK::ContentGenerator::renderViaXMLRPC);

=head1 NAME

WeBWorK::ContentGenerator::Instructor::AchievementEditor - edit an achevement evaluator file

=cut

use strict;
use warnings;
#use CGI qw(-nosticky );
use WeBWorK::CGI;
use WeBWorK::Utils qw(readFile surePathToFile path_is_subdir);
use HTML::Entities;
use URI::Escape;
use WeBWorK::Utils qw(has_aux_files not_blank);
use File::Copy;
use WeBWorK::Utils::Tasks qw(fake_user fake_set renderProblems);
use Data::Dumper;
use Fcntl;


use constant ACTION_FORMS => [qw(save save_as)]; 
use constant DEFAULT_ICON => "defaulticon.png";


sub pre_header_initialize {
	my ($self)         = @_;
	my $r              = $self->r;
	my $ce             = $r->ce;
	my $urlpath        = $r->urlpath;
	my $authz          = $r->authz;
	my $user           = $r->param('user');
	$self->{courseID}   = $urlpath->arg("courseID");
	$self->{achievementID}      = $r->urlpath->arg("achievementID") ; 

	my $submit_button   = $r->param('submit');  # obtain submit command from form
	my $actionID        = $r->param('action');

	# Check permissions
	return unless ($authz->hasPermissions($user, "edit_achievements"));

	#get the achievement
	my $Achievement = $r->db->getAchievement($self->{achievementID});

	if (not $Achievement) {
	    $self->addbadmessage("Achievement $self->{achievementID} not found!");
	    die;
	}

	$self->{achievement} = $Achievement;
	$self->{sourceFilePath} = $ce->{courseDirs}->{achievements}."/".$Achievement->test;
	$self->{r_achievementContents}= undef;
	
	#perform a save or save_as action
 	if ($actionID) {
 		unless (grep { $_ eq $actionID } @{ ACTION_FORMS() } ) {
 			die "Action $actionID not found";
 		}
 
 
		my $actionHandler = "${actionID}_handler";
		my %genericParams =();
		my %actionParams = $self->getActionParams($actionID);
		my %tableParams = (); 
		$self->{action}= $actionID;
		$self->$actionHandler(\%genericParams, \%actionParams, \%tableParams);
		
 	} else {
	    # we just opened up this file for the first time
 		$self->{action}='fresh_edit';
 		my $actionHandler = "fresh_edit_handler";
 		my %genericParams;
 		my %actionParams = (); 
 		my %tableParams = (); 
		my $achievementContents = '';
		$self->{r_achievementContents}=\$achievementContents;
 		$self->$actionHandler(\%genericParams, \%actionParams, \%tableParams);
 	}
 
	
	##############################################################################
	# Return 
	#   If  file saving fails or 
	#   if no redirects are required. No further processing takes place in this subroutine.
	#   Redirects are required only for the following submit values
	#        'Save'
	#        'Save as'
	# 
	#########################################
	
	return if $self->{failure};
	# FIXME: even with an error we still open a new page because of the target specified in the form
	my $action = $self->{action};
	return ;
	
}


sub initialize  {
	my ($self) = @_;
	my $r = $self->r;
	my $authz = $r->authz;
	my $user = $r->param('user');
	my $sourceFilePath = $self->{sourceFilePath};
	

	# Check permissions
	return unless ($authz->hasPermissions($user, "edit_achievements"));
	
	
	$self->addmessage($r->param('status_message') ||'');  # record status messages carried over if this is a redirect

	# Check source file path
	if ( not( -e $sourceFilePath) ) {
	    $self->addbadmessage("The file '".$self->shortPath($sourceFilePath)."' cannot be found.");
	}
}

sub path {
	my ($self, $args) = @_;
	my $r = $self->r;
	my $urlpath = $r->urlpath;
	my $courseName  = $urlpath->arg("courseID");
	my $achievementName = $r->urlpath->arg("achievementID") || '';

	# we need to build a path to the achievement being edited by hand, since it is not the same as the urlpath
	# For this page the bread crum path leads back to the problem being edited, not to the Instructor tool.
	my @path = ( 'WeBWork', $r->location,
	          "$courseName", $r->location."/$courseName",
		  'Achievement', $r->location."/$courseName/instructor/achievement_list",
	          "$achievementName",    $r->location."/$courseName/instructor/achievement_list",
	);
	
	#print "\n<!-- BEGIN " . __PACKAGE__ . "::path -->\n";
	print $self->pathMacro($args, @path);
	#print "<!-- END " . __PACKAGE__ . "::path -->\n";
	
	return "";
}

sub title {
	my $self = shift;
	my $r = $self->r;
	my $courseName    = $r->urlpath->arg("courseID");
	my $achievementID  = $r->urlpath->arg("achievementID");

	return "Achievement Evaluator for achievement $achievementID";

}

sub body {
	my ($self) = @_;
	my $r = $self->r;
	my $db = $r->db;
	my $ce = $r->ce;
	my $authz = $r->authz;
	my $user = $r->param('user');
 
	# Check permissions
	return CGI::div({class=>"ResultsWithError"}, "You are not authorized to edit achievements.")
		unless $authz->hasPermissions($user, "edit_achievements");
	
	# Gathering info
	my $sourceFilePath    = $self->{sourceFilePath}; # path to the permanent file to be edited
	my $achievementID     = $self->{achievementID} ;
	my $Achievement       = $self->{achievement};


	#########################################################################
	# Find the text for the achievement 
	#########################################################################
	
	my $achievementContents = ${$self->{r_achievementContents}};

	unless ( $achievementContents =~/\S/)   { # non-empty contents
	    die "Path is Unsafe!" unless path_is_subdir($sourceFilePath, $ce->{courseDirs}->{achievements}, 1);
	    
	    eval { $achievementContents = WeBWorK::Utils::readFile($sourceFilePath) };
	    
	    $achievementContents = $@ if $@;
		       
	} else {
	    #warn "obtaining input from r_problemContents";
	}

	my $header = CGI::i("Editing achievement in file '".$self->shortPath($sourceFilePath)."'");
	
	#########################################################################
	# Format the page
	#########################################################################
	
	# Define parameters for textarea
	my $rows            = 20;
	my $columns         = 90;
	my $mode_list       = $ce->{pg}->{displayModes};
	my $uri             = $r->uri;
	
	my $force_field = (not_blank( $self->{sourceFilePath}) ) ? # path is  a non-blank string
		CGI::hidden(-name=>'sourceFilePath',
		            -default=>$self->{sourceFilePath}) : '';

	print CGI::p($header),

		CGI::start_form({method=>"POST", id=>"editor", name=>"editor", action=>"$uri", enctype=>"application/x-www-form-urlencoded"}),

		$self->hidden_authen_fields,
		$force_field,

		CGI::p(
			CGI::textarea(
				-name => 'achievementContents', -default => $achievementContents,
				-rows => $rows, -cols => $columns, -override => 1,
			),
		);


	
######### print action forms
		
	print CGI::start_table({});
	
	my @formsToShow = @{ ACTION_FORMS() };
	my $default_choice = $formsToShow[0];
	my $i = 0;
	foreach my $actionID (@formsToShow) {
	    my $actionForm = "${actionID}_form";
	    my %actionParams = $self->getActionParams($actionID);
	    my $line_contents = $self->$actionForm(%actionParams);
	    my $radio_params = {-type=>"radio", -name=>"action", -value=>$actionID};
	    $radio_params->{checked}=1 if ($actionID eq $default_choice) ;
	    $radio_params->{id} = "action$i";
	    print CGI::Tr({-valign=>"top"},
			  CGI::td({}, CGI::input($radio_params)),
			  CGI::td({}, $line_contents)
		) if $line_contents;
	    
	    $i++;
	}
	
	print CGI::Tr({}, CGI::td({-colspan=>2}, "Select above then:",
				  CGI::submit(-name=>'submit', -value=>"Take Action!"),
				  ));
	
	print CGI::end_table();	
	
	
	print  CGI::end_form();

	print CGI::script("updateTarget()");
	return "";


}

#
#  Convert long paths to [ACHEVDIR]
#
sub shortPath {
  my $self = shift; my $file = shift;
  my $ache = $self->r->ce->{courseDirs}{achievements};
  $file =~ s|^$ache|[ACHEVDIR]|; 
  return $file;
}

################################################################################
# Utilities
################################################################################

sub getRelativeSourceFilePath {
	my ($self, $sourceFilePath) = @_;
	
	my $achievementsDir = $self->r->ce->{courseDirs}->{achievements};
	$sourceFilePath =~ s|^${achievementsDir}/*||; # remove templates path and any slashes that follow
	
	return $sourceFilePath;
}

sub saveFileChanges {

################################################################################
# saveFileChanges does most of the work. it is a separate method so that it can
# be called from either pre_header_initialize() or initilize(), depending on
# whether a redirect is needed or not.
# 
# it actually does a lot more than save changes to the file being edited, and
# sometimes less.
################################################################################

	my ($self, $outputFilePath, $achievementContents ) = @_;
 	my $r             = $self->r;
 	my $ce            = $r->ce;

	my $action          = $self->{action}||'no action';
	
	if (defined($achievementContents) and ref($achievementContents) ) {
		$achievementContents = ${$achievementContents};
	} elsif( ! not_blank($achievementContents)  ) {      # if the AchievementContents is undefined or empty
		$achievementContents = ${$self->{r_achievementContents}};
	}
	

	unless (not_blank($outputFilePath) ) {
	    $self->addbadmessage("You must specify an file name in order to save a new file.");
	    return "";
	}
	my $do_not_save    = 0 ;       # flag to prevent saving of file
	my $editErrors = '';	
	
	##############################################################################
	# write changes to the approriate files
	# FIXME  make sure that the permissions are set correctly!!!
	# Make sure that the warning is being transmitted properly.
	##############################################################################
   
	my $writeFileErrors;
	if ( not_blank($outputFilePath)  ) {   # save file
	    
	    # make sure any missing directories are created
	    WeBWorK::Utils::surePathToFile($ce->{courseDirs}->{achievements},
					   $outputFilePath);
	    die "outputFilePath is unsafe!" unless path_is_subdir($outputFilePath, $ce->{courseDirs}->{achievements}, 1); # 1==path can be relative to dir
	    
	    eval {
		local *OUTPUTFILE;
		open OUTPUTFILE,  ">$outputFilePath"
		    or die "Failed to open $outputFilePath";
		print OUTPUTFILE $achievementContents;
		close OUTPUTFILE;		
		# any errors are caught in the next block
	    };
	    
	    $writeFileErrors = $@ if $@;
	} 
	
	###########################################################
	# Catch errors in saving files,
	###########################################################
	
	$self->{saveError} = $do_not_save;    # don't do redirects if the file was not saved.
	                                    # don't unlink files or send success messages
	
	if ($writeFileErrors) {
	    # get the current directory from the outputFilePath
	    $outputFilePath =~ m|^(/.*?/)[^/]+$|;
	    my $currentDirectory = $1;
	    
	    my $errorMessage;
	    # check why we failed to give better error messages
	    if ( not -w $ce->{courseDirs}->{achievements} ) {
		$errorMessage = "Write permissions have not been enabled in the templates directory.  No changes can be made.";
	    } elsif ( not -w $currentDirectory ) {
		$errorMessage = "Write permissions have not been enabled in '".$self->shortPath($currentDirectory)."'.  Changes must be saved to a different directory for viewing.";
	    } elsif ( -e $outputFilePath and not -w $outputFilePath ) {
		$errorMessage = "Write permissions have not been enabled for '".$self->shortPath($outputFilePath)."'.  Changes must be saved to another file for viewing.";
	    } else {
		$errorMessage = "Unable to write to '".$self->shortPath($outputFilePath)."': $writeFileErrors";
	    }
	    
	    $self->{failure} = 1;
	    $self->addbadmessage(CGI::p($errorMessage));
	    
	} 
	
	unless( $writeFileErrors or $do_not_save) {  # everything worked!  unlink and announce success!

		if ( defined($outputFilePath) and ! $self->{failure} ) {  
		            # don't announce saving of temporary editing files
			my $msg = "Saved to file '".$self->shortPath($outputFilePath)."'.";

			$self->addgoodmessage($msg);
		}

	}


}  # end saveFileChanges





sub getActionParams {
	my ($self, $actionID) = @_;
	my $r = $self->{r};
	
	my %actionParams=();
	foreach my $param ($r->param) {
		next unless $param =~ m/^action\.$actionID\./;
		$actionParams{$param} = [ $r->param($param) ];
	}
	return %actionParams;
}

sub fixAchievementContents {
		#NOT a method
		my $AchievementContents = shift;
		# Handle the problem of line endings.  
		# Make sure that all of the line endings are of unix type.  
		# Convert \r\n to \n
		$AchievementContents =~ s/\r\n/\n/g;
		$AchievementContents =~ s/\r/\n/g;
		$AchievementContents;
}

sub save_form {
	my ($self, %actionParams) = @_;
	my $r => $self->r;

	if (-w $self->{sourceFilePath}) {

		return "Save ".CGI::b($self->shortPath($self->{sourceFilePath}));	

	} else {
		return ""; #"Can't save -- No write permission";
	}

}

sub save_handler {
	my ($self, $genericParams, $actionParams, $tableParams) = @_;
	my $r= $self->r;
	my $courseName      =  $self->{courseID};
	my $achievementName         =  $self->{achievementID};
	
	#################################################
	# grab the achievementContents from the form in order to save it to the source path
	#################################################
	my $achievementContents = fixAchievementContents($self->r->param('achievementContents'));
	$self->{r_achievementContents} = \$achievementContents;
	
	#################################################
	# Construct the output file path
	#################################################
	$self->saveFileChanges($self->{sourceFilePath});	

	return;

}



sub save_as_form {  # calls the save_as_handler 
	my ($self, %actionParams) = @_;
	my $sourceFilePath  = $self->{sourceFilePath};
	my $achievementsDir  =  $self->r->ce->{courseDirs}->{achievements};
	my $achievementID    = $self->{achievementID};	
	my $sourceFileName = getRelativeSourceFilePath($self,$sourceFilePath);

	#There are three things you can do with a new achievement editor
	#you can replace the editior in the current achievement
	my $use_in_current_achievement  =
	    CGI::input({
		-type      => 'radio',
		-name      => "action.save_as.saveMode",
		-value     => "use_in_current",
		-label     => '',
		-checked   => 'checked',
			 },"and use in achievement ".CGI::b("$achievementID"));
		       
	#Use can use it in a new achievement
	my $create_new_achievement      =
	    CGI::input({
		-type      => 'radio',
		-name      => "action.save_as.saveMode",
		-value     => 'use_in_new',
    			 -label     => '',
		       },"and use in new achievement ",).CGI::textfield(
		-name => "action.save_as.id",
		-value => "",
		-width => "50",
			   );  
	
	#you can not use it at all
	my $dont_use_in_achievement  =
	    CGI::input({
		-type      => 'radio',
		-name      => "action.save_as.saveMode",
		-value     => "dont_use",
		-label     => '',
		       },"and don't use in an achievement");
	
	my $andRelink = CGI::br(). $use_in_current_achievement.CGI::br().
	    $create_new_achievement.CGI::br().$dont_use_in_achievement;
	    
	return 'Save as '.
	    CGI::textfield(
		-name=>'action.save_as.target_file', -size=>80, -value=>"$sourceFileName",  
	    ).",".
	    CGI::hidden(-name=>'action.save_as.source_file', -value=>$sourceFilePath ).
	    $andRelink;
}



sub save_as_handler {
	my ($self, $genericParams, $actionParams, $tableParams) = @_;
	my $r = $self->r;
	my $db = $r->db;
	$self->{status_message} = ''; ## DPVC -- remove bogus old messages
	my $courseName      =  $self->{courseID};
	my $achievementName         =  $self->{achievementID};
	my $effectiveUserName = $self->r->param('effectiveUser');
	
	my $do_not_save = 0;
	my $saveMode       = $actionParams->{'action.save_as.saveMode'}->[0] || 'no_save_mode_selected';
	my $new_file_name  = $actionParams->{'action.save_as.target_file'}->[0] || '';
	my $sourceFilePath = $actionParams->{'action.save_as.source_file'}->[0] || '';
	my $targetAchievementID  =  $actionParams->{'action.save_as.id'}->[0] || '';

	$self ->{sourceFilePath} = $sourceFilePath;  # store for use in saveFileChanges
	$new_file_name =~ s/^\s*//;  #remove initial and final white space
	$new_file_name =~ s/\s*$//;
	if ( $new_file_name !~ /\S/) { # need a non-blank file name
		# setting $self->{failure} stops saving and any redirects
		$do_not_save = 1;
		$self->addbadmessage(CGI::p("Please specify a file to save to."));
	}
	
	#################################################
	# grab the achievementContents from the form in order to save it to a new permanent file
	#################################################
	my $achievementContents = fixAchievementContents($self->r->param('achievementContents'));
	$self->{r_achievementContents} = \$achievementContents;
	warn "achievement contents is empty" unless $achievementContents;
	#################################################
	# Rescue the user in case they forgot to end the file name with .at
	#################################################
	
	$new_file_name =~ s/\.at$//; # remove it if it is there
	$new_file_name .= '.at'; # put it there
	
       	
	#################################################
	# Construct the output file path
	#################################################
	my $outputFilePath = $self->r->ce->{courseDirs}->{achievements} . '/' . 
								 $new_file_name; 		
	if (defined $outputFilePath and -e $outputFilePath) {
		# setting $do_not_save stops saving and any redirects
		$do_not_save = 1;
		$self->addbadmessage(CGI::p("File '".$self->shortPath($outputFilePath)."' exists.  
		File not saved. No changes have been made."));
	} elsif ($saveMode eq 'use_in_new' && not $targetAchievementID) {
	    $self->addbadmessage("No new Achievement ID specified.  No new achievement created.  File not saved.");
	    $do_not_save = 1;
	    
	} elsif ($saveMode eq 'use_in_new' && $db->existsAchievement($targetAchievementID)) {
	    $self->addbadmessage("Achievement ID exists!  No new achievement created.  File not saved.");
	    $do_not_save = 1;
	} else {
	    $self->{editFilePath} = $outputFilePath;
	    $self->{inputFilePath} = '';
	}

	return "" if $do_not_save;
	

	#Save changes
	$self->saveFileChanges($outputFilePath);
	
	if ($saveMode eq 'use_in_current' and -r $outputFilePath) { 
	    #################################################
	    # Modify evaluator path in current achievement
	    #################################################
	    my $achievement = $self->r->db->getAchievement($achievementName);
	    $achievement->test($new_file_name);
	    if ($self->r->db->putAchievement($achievement)) {
		$self->addgoodmessage("The evaluator for $achievementName has been renamed to '".$self->shortPath($outputFilePath)."'.") ;
	    } else {
		$self->addbadmessage("Unable to change the evaluator for set $achievementName. Unknown error.");
	    }
	    
	} elsif ($saveMode eq 'use_in_new') {
	    #Create a new achievement to use the evaluator in
	    my $achievement = $self->r->db->newAchievement();
	    $achievement->achievement_id($targetAchievementID);
	    $achievement->test($new_file_name);
	    $achievement->icon(DEFAULT_ICON());
	    
	    $self->r->db->addAchievement($achievement);
	    $self->addgoodmessage("Achievement $targetAchievementID created with evaluator '".$self->shortPath($outputFilePath)."'.") ;			    
	    
	} elsif ($saveMode eq 'dont_use') {
	    #################################################
	    # Don't change any achievements - just report 
	    #################################################
	    $self->addgoodmessage("A new file has been created at '".$self->shortPath($outputFilePath)."'");
	} else {
	    $self->addbadmessage("Don't recognize saveMode: |$saveMode|. Unknown error.");
	}
	
      
	
	#################################################
	# Set up redirect
	# The redirect gives the server time to detect that the new file exists.
	#################################################
	my $problemPage;

	if ($saveMode eq 'dont_use' ) {
		$problemPage = $self->r->urlpath->newFromModule("WeBWorK::ContentGenerator::Instructor::AchievementEditor",$r,
			courseID => $courseName, achievementID => $achievementName);
	} elsif ($saveMode eq 'use_in_current') {
		$problemPage = $self->r->urlpath->newFromModule("WeBWorK::ContentGenerator::Instructor::AchievementEditor",$r,
			courseID => $courseName, achievementID => $achievementName);
	} elsif ($saveMode eq 'use_in_new') {
	    $problemPage = $self->r->urlpath->newFromModule("WeBWorK::ContentGenerator::Instructor::AchievementEditor",$r,
			courseID => $courseName, achievementID => $targetAchievementID);
	} else {
		$self->addbadmessage(" Please use radio buttons to choose the method for saving this file. Can't recognize saveMode: |$saveMode|.");
		# can't continue since paths have not been properly defined.
		return "";
	}
	
	#warn "save mode is $saveMode";

	my $relativeOutputFilePath = $self->getRelativeSourceFilePath($outputFilePath);
	
	my $viewURL = $self->systemLink($problemPage, 
					params=>{
					    sourceFilePath     => $relativeOutputFilePath,
					    status_message     => uri_escape($self->{status_message})}
					
	    );
	
	$self->reply_with_redirect($viewURL);
    return "";  # no redirect needed
}

sub fresh_edit_handler {
	my ($self, $genericParams, $actionParams, $tableParams) = @_;
	#$self->addgoodmessage("fresh_edit_handler called");
}


1;
