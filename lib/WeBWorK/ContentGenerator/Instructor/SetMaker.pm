################################################################################
# WeBWorK Online Homework Delivery System
# Copyright � 2000-2003 The WeBWorK Project, http://openwebwork.sf.net/
# $CVSHeader: webwork-modperl/lib/WeBWorK/ContentGenerator/Instructor/SetMaker.pm,v 1.12 2004/05/21 23:38:53 jj Exp $
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


package WeBWorK::ContentGenerator::Instructor::SetMaker;
use base qw(WeBWorK::ContentGenerator::Instructor);

=head1 NAME

WeBWorK::ContentGenerator::Instructor::SetMaker - Make problem sets.

=cut

use strict;
use warnings;

use CGI::Pretty qw();
use WeBWorK::Form;
use WeBWorK::Utils qw(readDirectory max);
use WeBWorK::Utils::Tasks qw(renderProblems);

require WeBWorK::Utils::ListingDB;

use constant MAX_SHOW => 20;

## Flags for operations on files

use constant ADDED => 1;
use constant HIDDEN => (1 << 1);
use constant SUCCESS => (1 << 2);

## Maybe this should be in ContentGenerator.pm

sub adderrmsg {
  my $self = shift;
  my $msg = shift;
  $self->addmessage(CGI::div({class=>"ResultsWithError"}, $msg));
}


## This is for searching the disk for directories containing pg files.
## to make the recursion work, this returns an array where the first 
## item is 1 or 0 depending on whether or not the current
## directory has any pg files.  The second is a list of directories
## which contain pg files.
sub get_library_sets {
  my $amtop = shift;
  my $topdir =  shift;
  my @lis = readDirectory($topdir);
  my @pgs = grep { m/\.pg$/ and (not m/Header\.pg/) and -f "$topdir/$_"} @lis;
  my $havepg = scalar(@pgs)>0 ? 1 : 0;
  my @mdirs = grep {$_ ne "." and $_ ne ".." and $_ ne "Library"
		      and -d "$topdir/$_"} @lis;
  if($amtop) { # we don't want the library
     @mdirs = grep {$_ ne "Library"} @mdirs;
  }
  my ($adir, @results, @thisresult);
  for $adir (@mdirs) {
    @results = get_library_sets(0, "$topdir/$adir");
    my $isadirok = shift @results;
    @thisresult = (@thisresult, @results);
    if ($isadirok) {
      @thisresult = ("$topdir/$adir", @thisresult);
    }
  }
  return(($havepg, @thisresult));
}

## List all the pg files in the requested directory
sub list_pg_files {
  my $templatedir = shift;
  my $topdir = shift;

  my @lis = readDirectory("$templatedir/$topdir");
  my @pgs = grep { m/\.pg$/ and (not m/Header\.pg/) and -f "$templatedir/$topdir/$_"} @lis;
  @pgs = map { "$topdir/$_" } @pgs;
  return(@pgs);
}

## go through past page getting a list of identifiers for the problems
## and whether or not they are selected, and whether or not they should
## be hidden

sub get_past_problem_files {
  my $r = shift;
  my @found=();
  my $count =1;
  while (defined($r->param("filetrial$count"))) {
    my $val = 0;
    $val |= ADDED if($r->param("trial$count"));
    $val |= HIDDEN if($r->param("hideme$count"));
    push @found, [$r->param("filetrial$count"), $val];		  
    $count++;
  }
  return(\@found);
}

#### For adding new problems

sub add_selected {
  my $self = shift;
  my $db = shift;
  my $setName = shift;
  my @past_problems = @{$self->{past_problems}};
  my @selected = @past_problems;
  my (@path, $file, $selected, $freeProblemID);
  $freeProblemID = max($db->listGlobalProblems($setName)) + 1;
  my $addedcount=0;

  for $selected (@selected) {
    if($selected->[1] & ADDED) {
      $file = $selected->[0];
      @path = split "/", $selected->[0];
      pop @path;			# Remove the file name from the path
      shift @path if $path[0] eq ""; # remove the null element from the begining
      my $problemRecord = $db->newGlobalProblem();
      $problemRecord->problem_id($freeProblemID++);
      $problemRecord->set_id($setName);
      $problemRecord->source_file($file);
      $problemRecord->value("1");
      $problemRecord->max_attempts("-1");
      $db->addGlobalProblem($problemRecord);
      $self->assignProblemToAllSetUsers($problemRecord);
      $selected->[1] &= SUCCESS;
      $addedcount++;
    }
  }
  return($addedcount);
}


############# List of sets of problems in templates directory

sub get_problem_directories {
  my $ce = shift;
  my @all_problem_directories = get_library_sets(1, $ce->{courseDirs}->{templates});
  my $includetop = shift @all_problem_directories;
  my $j;
  for ($j=0; $j<scalar(@all_problem_directories); $j++) {
    $all_problem_directories[$j] =~ s|^$ce->{courseDirs}->{templates}/?||;
  }
  @all_problem_directories = sort @all_problem_directories;
  unshift @all_problem_directories, '  -- Top --  ' if($includetop);
  return (\@all_problem_directories);
}

### The browsing panel has three versions
#####  Version 1 is local problems
sub browse_local_panel {
  my $self = shift;
  my $library_selected = shift;

  my $list_of_prob_dirs= get_problem_directories($self->r->ce);
  if(scalar(@$list_of_prob_dirs) == 0) {
    $library_selected = "Found no directories containing problems";
    unshift @{$list_of_prob_dirs}, $library_selected;
  } else {
    my $default_value = "Select a Local Problem Collection";
    if (not $library_selected or $library_selected eq $default_value) {
      unshift @{$list_of_prob_dirs},  $default_value;
      $library_selected = $default_value;
    }
  }
  
  print CGI::Tr(CGI::td({-class=>"InfoPanel"}, "Local Problems: ",
			CGI::popup_menu(-name=> 'library_sets', 
					-values=>$list_of_prob_dirs, 
					-default=> $library_selected),
			CGI::br(), 
			CGI::submit(-name=>"view_local_set", -value=>"View Problems"),
		       ));
}

#####  Version 2 is local problem sets
sub browse_mysets_panel {
  my $self = shift;
  my $library_selected = shift;
  my $list_of_local_sets = shift;
  my $default_value = "Select a Problem Set";

  if(scalar(@$list_of_local_sets) == 0) {
    $list_of_local_sets = ['There are no local sets yet'];
  } elsif (not $library_selected or $library_selected eq $default_value) { 
    unshift @{$list_of_local_sets},  $default_value; 
    $library_selected = $default_value; 
  } 

  print CGI::Tr(CGI::td({-class=>"InfoPanel"}, "Browse from: ",
			CGI::popup_menu(-name=> 'library_sets', 
					-values=>$list_of_local_sets, 
					-default=> $library_selected),
			CGI::br(), 
			CGI::submit(-name=>"view_mysets_set", -value=>"View This Set"),
		       ));
}

#####  Version 3 is the problem library


# There a different levels, and you can pick a new chapter,
# pick a new section, pick all from chapter, pick all from section
#
# Incoming data - current chapter, current section
sub browse_library_panel {
  my $self = shift;
  my $r = $self->r;
  my $ce = $r->ce;

  my $libraryRoot = $r->{ce}->{problemLibrary}->{root};

  unless($libraryRoot) {
    print CGI::Tr(CGI::td(CGI::div({class=>'ResultsWithError', align=>"center"}, 
        "The problem library has not been installed.")));
    return;
  }
  # Test if the Library directory exists.  If not, try to make it
  unless(-d "$ce->{courseDirs}->{templates}/Library") {
    unless(symlink($libraryRoot, "$ce->{courseDirs}->{templates}/Library")) {
      my $msg =  <<"HERE";
You are missing the directory <code>templates/Library</code>, which is needed
for the Problem Library to function.  It should be a link pointing to
<code>$libraryRoot</code>, which you set in <code>conf/global.conf</code>.
I tried to make the link for you, but that failed.  Check the permissions
in your <code>templates</code> directory.
HERE
      $self->adderrmsg($msg);
    }
  }

  my $default_chap = "All Chapters";
  my $default_sect = "All Sections";

  my @chaps = WeBWorK::Utils::ListingDB::getAllChapters($r->{ce});
  unshift @chaps, $default_chap;
  my $chapter_selected = $r->param('library_chapters') || $default_chap;

  my @sects=();
  if ($chapter_selected ne $default_chap) {
    @sects = WeBWorK::Utils::ListingDB::getAllSections($r->{ce}, $chapter_selected);
  }

  my @textbooks = ('Textbook info not ready');

  unshift @sects, $default_sect;
  my $section_selected =  $r->param('library_sections') || $default_sect;

  print CGI::Tr(CGI::td({-class=>"InfoPanel"}, 
			CGI::start_table(),
                        CGI::Tr(
				CGI::td(["Chapter:",
					 CGI::popup_menu(-name=> 'library_chapters', 
							 -values=>\@chaps,
							 -default=> $chapter_selected,
							 -onchange=>"submit();return true"
							),
					 CGI::submit(-name=>"lib_select_chapter", -value=>"Update Section List")])),
			CGI::Tr(
				CGI::td("Section:"),
				CGI::td({-colspan=>2},
					CGI::popup_menu(-name=> 'library_sections', 
							-values=>\@sects,
							-default=> $section_selected
						       ))),

# 			CGI::Tr(
# 				CGI::td("Textbook:"),
# 				CGI::td({-colspan=>2},
# 					CGI::popup_menu(-name=> 'library_textbooks', 
# 							-values=>\@textbooks,
# 							#						 -default=> $section_selected
# 						       ))),

# 			CGI::Tr(
# 				CGI::td("Keywords:"),
#                                 CGI::td({-colspan=>2}, CGI::textfield(-name=>"keywords",
# 								      -default=>"Keywords not implemented yet",
# 								      -override=>1, -size=>60))),
			CGI::Tr(CGI::td({-colspan=>3},CGI::submit(-name=>"lib_view", -value=>"View Problems"))),
			CGI::end_table(),
		       ));
}

sub make_top_row {
  my $self = shift;
  my $r = $self->r;
  my %data = @_;

  my $list_of_local_sets = $data{all_set_defs};
  my $have_local_sets = scalar(@$list_of_local_sets);
  my $browse_which = $data{browse_which};
  my $library_selected = $r->param('library_sets');
  my $set_selected = $r->param('local_sets');

  my ($dis1, $dis2, $dis3) = ("","","");
  $dis1 =  '-disabled' if($browse_which eq 'browse_library');  
  $dis2 =  '-disabled' if($browse_which eq 'browse_local');
  $dis3 =  '-disabled' if($browse_which eq 'browse_mysets');

  my $these_widths = "width: 27ex";
  print CGI::Tr(CGI::td({-class=>"InfoPanel", -align=>"center"},
			CGI::submit(-name=>"browse_library", -value=>"Browse Problem Library", -style=>$these_widths, $dis1),
			CGI::submit(-name=>"browse_local", -value=>"Browse Local Problems", -style=>$these_widths, $dis2),
			CGI::submit(-name=>"browse_mysets", -value=>"Browse From This Course", -style=>$these_widths, $dis3),
		       ));

  print CGI::Tr(CGI::td({-bgcolor=>"black"}));

  if ($browse_which eq 'browse_local') {
    $self->browse_local_panel($library_selected);
  } elsif ($browse_which eq 'browse_mysets') {
    $self->browse_mysets_panel($library_selected, $list_of_local_sets);
  } else {
    $self->browse_library_panel();
  }

  print CGI::Tr(CGI::td({-bgcolor=>"black"}));

  if($have_local_sets ==0) {
    $list_of_local_sets = ['There are no local sets yet'];
  } elsif (not $set_selected or $set_selected eq "Select a Set for This Course") {
    if ($list_of_local_sets->[0] eq "Select a Problem Set") {
      shift @{$list_of_local_sets};
    }
    unshift @{$list_of_local_sets}, "Select a Set for This Course";
    $set_selected = "Select a Set for This Course";
  }

  print CGI::Tr(CGI::td({-class=>"InfoPanel"}, "Current Set: ",
			CGI::popup_menu(-name=> 'local_sets', 
					-values=>$list_of_local_sets, 
					-default=> $set_selected),
			CGI::submit(-name=>"edit_local", -value=>"Edit Current Set"),
			CGI::br(), 
			CGI::br(), 
			CGI::submit(-name=>"new_local_set", -value=>"Create New Local Set:"),
			"  ",
			CGI::textfield(-name=>"new_set_name", 
				       -default=>"Name for new set here",
				       -override=>1, -size=>30),
			CGI::br(),
		       ));

  print CGI::Tr(CGI::td({-bgcolor=>"black"}));

  print CGI::Tr(CGI::td({-class=>"InfoPanel", -align=>"center"},
			CGI::submit(-name=>"update", -style=>$these_widths,
				    -value=>"Act on Marked Problems"),
			CGI::submit(-name=>"rerandomize", 
				    -style=>$these_widths,
				    -value=>"Rerandomize"),
			CGI::submit(-name=>"cleardisplay", 
				    -style=>$these_widths,
				    -value=>"Clear Problem Display")));

}

sub make_data_row {
  my $self = shift;
  my $sourceFileName = shift;
  my $pg = shift;
  my $cnt = shift;

  $sourceFileName =~ s|^./||; # clean up top ugliness

  my $urlpath = $self->r->urlpath;
  my $problem_output = $pg->{flags}->{error_flag} ?
    CGI::em("This problem produced an error") 
    : CGI::div({class=>"RenderSolo"}, $pg->{body_text});


  my $edit_link =  '';
  #if($self->{r}->param('browse_which') ne 'browse_library') {
  if($sourceFileName !~ /^Library\//) {
    $edit_link = CGI::a({href=>$self->systemLink($urlpath->newFromModule("WeBWorK::ContentGenerator::Instructor::PGProblemEditor",
						courseID =>$urlpath->arg("courseID"),
						setID=>"Undefined_Set",
						problemID=>"1"),
						params=>{sourceFilePath => "$sourceFileName"}
						  )}, "Edit it" );
  }

  my $try_link = CGI::a({href=>$self->systemLink($urlpath->newFromModule("WeBWorK::ContentGenerator::Problem",
						courseID =>$urlpath->arg("courseID"),
						setID=>"Undefined_Set",
						problemID=>"1"),
						  params =>{effectiveUser => $self->r->param('user'), 
							    editMode => "SetMaker", 
							    sourceFilePath => "$sourceFileName"}  )}, "Try it");

      

  print CGI::Tr({-align=>"left"}, CGI::td(

					  CGI::div({-style=>"background-color: #DDDDDD; margin: 0px auto"},
CGI::span({-style=>"float:left ; text-align: left"},"File name: $sourceFileName "), 
CGI::span({-style=>"float:right ; text-align: right"}, $edit_link, " ", $try_link)
						  ), CGI::br(),




					  CGI::checkbox(-name=>"hideme$cnt",-value=>1,-label=>"Don't show me on the next update"),
					  CGI::br(),
					  CGI::checkbox(-name=>"trial$cnt",-value=>1,-label=>"Add me to the current set on the next update"),
					  CGI::hidden(-name=>"filetrial$cnt", -default=>[$sourceFileName]).
					  CGI::p($problem_output),
					 ));
}


sub pre_header_initialize {
  my ($self) = @_;
  my $r = $self->r;
  ## For all cases, lets set some things
  $self->{error}=0;
  my $ce = $r->ce;
  my $db = $r->db;


  my $userName = $r->param('user');
  my $user = $db->getUser($userName); # checked 
  die "record for user $userName (real user) does not exist." 
    unless defined $user;
  my $authz = $r->authz;
  unless ($authz->hasPermissions($userName, "modify_problem_sets")) {
    return(""); # Error message already produced in the body
  }

  ## Now one action we have to deal with here
  if ($r->param('edit_local')) {
    my $urlpath = $r->urlpath;
    my $db = $r->db;
    my $checkset = $db->getGlobalSet($r->param('local_sets'));
    if (not defined($checkset)) {
      $self->{error} = 1;
      $self->adderrmsg('You need to select a "Current Set" before you can edit it.');
    } else {
      my $page = $urlpath->newFromModule('WeBWorK::ContentGenerator::Instructor::ProblemSetEditor', setID=>$r->param('local_sets'), courseID=>$urlpath->arg("courseID"));
      my $url = $self->systemLink($page);
      $self->reply_with_redirect($url);
    }
  }

  ## Next, lots of set up so that errors can be reported with message()

  ############# List of problems we have already printed

  $self->{past_problems} = get_past_problem_files($r);
  my $none_shown = scalar(@{$self->{past_problems}})==0;
  my @pg_files=();
  my $use_previous_problems = 1;
  my $first_shown = $r->param('first_shown') || 0;
  my $last_shown = $r->param('last_shown');
  if (not defined($last_shown)) {
    $last_shown = -1;
  }
  my @all_past_list = ();	# these are include requested, but not shown
  my $j = 0;
  while (defined($r->param("all_past_list$j"))) {
    push @all_past_list, $r->param("all_past_list$j");
    $j++;
  }

  ############# Default of which problem selector to display

  my $browse_which = $r->param('browse_which') || 'browse_local';

  my $problem_seed = $r->param('problem_seed') || 0;
  $r->param('problem_seed', $problem_seed); # if it wasn't defined before

  ########### Start the logic through if elsif elsif ...

  ##### Asked to browse certain problems
  if ($r->param('browse_library')) {
    $browse_which = 'browse_library';
    $r->param('library_sets', "");
  } elsif ($r->param('browse_local')) {
    $browse_which = 'browse_local';
    $r->param('library_sets', "");
  } elsif ($r->param('browse_mysets')) {
    $browse_which = 'browse_mysets';
    $r->param('library_sets', "");

    ##### Change the seed value

  } elsif ($r->param('rerandomize')) {
    $problem_seed++;
    $r->param('problem_seed', $problem_seed);
    $self->adderrmsg('Changing the problem seed for display, but there are no problems showing.') if $none_shown;

    ##### Clear the display

  } elsif ($r->param('cleardisplay')) {
    @pg_files = ();
    $use_previous_problems=0;
    $self->adderrmsg('The display was already cleared.') if $none_shown;

    ##### View problems selected from the local list

  } elsif ($r->param('view_local_set')) {

    my $set_to_display = $r->param('library_sets');
    if (not defined($set_to_display) or $set_to_display eq "Select a Local Problem Collection" or $set_to_display eq "Found no directories containing problems") {
      $self->adderrmsg('You need to select a set to view.');
    } else {
      $set_to_display = '.' if $set_to_display eq '  -- Top --  ';
      @pg_files = list_pg_files($ce->{courseDirs}->{templates},
				"$set_to_display");
      $use_previous_problems=0;
    }

    ##### View problems selected from the a set in this course

  } elsif ($r->param('view_mysets_set')) {

    my $set_to_display = $r->param('library_sets');
    if (not defined($set_to_display) 
        or $set_to_display eq "Select a Problem Set"
        or $set_to_display eq 'There are no local sets yet') {
      $self->adderrmsg("You need to select a set from this course to view.");
    } else {
      my @problemList = $db->listGlobalProblems($set_to_display);
      my $problem;
      @pg_files=();
      for $problem (@problemList) {
	my $problemRecord = $db->getGlobalProblem($set_to_display, $problem); # checked
	die "global $problem for set $set_to_display not found." unless
	  $problemRecord;
	push @pg_files, $problemRecord->source_file;

      }
      $use_previous_problems=0;
    }

    ##### View whole chapter from the library
    ## This will change somewhat later
 
  } elsif ($r->param('lib_view')) { 
 
    @pg_files=();
    my $chap = $r->param('library_chapters') || "";
    $chap = "" if($chap eq "All Chapters");
    my $sect = $r->param('library_sections') || "";
    $sect = "" if($sect eq "All Sections");
    my @dbsearch = WeBWorK::Utils::ListingDB::getSectionListings($r->{ce}, "$chap", "$sect");
    my ($result, $tolibpath);
    for $result (@dbsearch) {
      $tolibpath = "Library/$result->{path}/$result->{filename}";
      
      ## Too clunky!!!!
      push @pg_files, $tolibpath;
    }
    $use_previous_problems=0; 

    ##### Edit the current local problem set

  } elsif ($r->param('edit_local')) { ## Jump to set edit page

    ; # already handled


    ##### Make a new local problem set

  } elsif ($r->param('new_local_set')) {
    if ($r->param('new_set_name') !~ /^[\w.-]*$/) {
      $self->adderrmsg("The name ".$r->param('new_set_name')." is not a valid set name.  Use only letters, digits, -, _, and .");
    } else {
      my $newSetName = $r->param('new_set_name');
      $newSetName =~ s/^set//;
      $newSetName =~ s/\.def$//;
      $r->param('local_sets',$newSetName);
      my $newSetRecord   = $db->getGlobalSet($newSetName);
      if (defined($newSetRecord)) {
	$self->adderrmsg("The set name $newSetName is already in use.  Pick a different name if you would like to start a new set.");
      } else {			# Do it!
	$newSetRecord = $db->{set}->{record}->new();
	$newSetRecord->set_id($newSetName);
	$newSetRecord->set_header("");
	$newSetRecord->problem_header("");
	$newSetRecord->open_date(time()+60*60*24*7); # in one week
	$newSetRecord->due_date(time()+60*60*24*7*2); # in two weeks
	$newSetRecord->answer_date(time()+60*60*24*7*3); # in three weeks
	eval {$db->addGlobalSet($newSetRecord)};
      }
    }

    ##### Add selected problems to the current local set

  } elsif ($r->param('update')) {
    ## first handle problems to be added before we hide them
    my($localSet, @selected);

    @pg_files = grep {($_->[1] & ADDED) != 0 } @{$self->{past_problems}}; 
    @selected = map {$_->[0]} @pg_files;

    my @action_files = grep {$_->[1] > 0 } @{$self->{past_problems}};
    if(scalar(@action_files) == 0) {
      $self->adderrmsg('Act on marked problems requested, but no problems were marked.');
    }

    if (scalar(@selected)>0) {	# if some are to be added, they need a place to go
      $localSet = $r->param('local_sets');
      if (not defined($localSet)) {
	$self->adderrmsg('You are trying to add problems to something, but you did not select a "Current Set" name as a target.');
      } else {
	my $newSetRecord   = $db->getGlobalSet($localSet);
	if (not defined($newSetRecord)) {
	  $self->adderrmsg("You are trying to add problems to $localSet, but that set does not seem to exist!  I bet you used your \"Back\" button.");
	} else {
	  my $addcount = add_selected($self, $db, $localSet);
	  if($addcount > 0) {
	    $self->addgoodmessage("Successfully added $addcount problem".(($addcount>1)?'s':'').
	      " to $localSet.");
	  }
	}
      }
    }
    ## now handle problems to be hidden

    ## only keep the ones which are not hidden
    @pg_files = grep {($_->[1] & HIDDEN) ==0 } @{$self->{past_problems}};
    @pg_files = map {$_->[0]} @pg_files;
    @all_past_list = (@all_past_list[0..($first_shown-1)],
		      @pg_files,
		      @all_past_list[($last_shown+1)..(scalar(@all_past_list)-1)]);
    $last_shown = $first_shown+MAX_SHOW -1;
    $last_shown = (scalar(@all_past_list)-1) if($last_shown>=scalar(@all_past_list));

    ## FIXME: you should say something if no problems are selected
    ##        maybe the add button should be disabled if there are no problems
    ##        showing


  } elsif ($r->param('next_page')) {
    $first_shown = $last_shown+1;
    $last_shown = $first_shown+MAX_SHOW-1;
    $last_shown = (scalar(@all_past_list)-1) if($last_shown>=scalar(@all_past_list));
  } elsif ($r->param('prev_page')) {
    $last_shown = $first_shown-1;
    $first_shown = $last_shown - MAX_SHOW+1;

    $first_shown = 0 if($first_shown<0);

    ##### No action requested, probably our first time here

  } else {
    #my $c = $r->connection;
    #print "Debug info: ". $r->get_remote_host ."<p>".  $c->remote_ip ;
    ;
  }				##### end of the if elsif ...


  ############# List of local sets

  my @all_set_defs = $db->listGlobalSets;
  for ($j=0; $j<scalar(@all_set_defs); $j++) {
    $all_set_defs[$j] =~ s|^set||;
    $all_set_defs[$j] =~ s|\.def||;
  }

  if ($use_previous_problems) {
    @pg_files = @all_past_list;
  } else {
    $first_shown = 0;
    $last_shown = scalar(@pg_files)<MAX_SHOW ? scalar(@pg_files) : MAX_SHOW;
    $last_shown--;		# to make it an array index
  }
  ############# Now store data in self for retreival by body
  $self->{first_shown} = $first_shown;
  $self->{last_shown} = $last_shown;
  $self->{browse_which} = $browse_which;
  $self->{problem_seed} = $problem_seed;
  $self->{pg_files} = \@pg_files;
  $self->{all_set_defs} = \@all_set_defs;

}


sub title {
  return "Problem Set Maker";
}

sub body {
  my ($self) = @_;

  my $r = $self->r;
  my $ce = $r->ce;		# course environment
  my $db = $r->db;		# database
  my $j;			# garden variety counter

  my $userName = $r->param('user');

  my $user = $db->getUser($userName); # checked
  die "record for user $userName (real user) does not exist."
    unless defined $user;

  ### Check that this is a professor
  my $authz = $r->authz;
  unless ($authz->hasPermissions($userName, "modify_problem_sets")) {
    print "User $userName returned " . 
      $authz->hasPermissions($user, "modify_problem_sets") . 
	" for permission";
    return(CGI::div({class=>'ResultsWithError'},
	  CGI::em("You are not authorized to access the Instructor tools.")));
  }

  ##########  Extract information computed in pre_header_initialize

  my $first_shown = $self->{first_shown};
  my $last_shown = $self->{last_shown};  
  my $browse_which = $self->{browse_which};
  my $problem_seed = $self->{problem_seed};
  my @pg_files = @{$self->{pg_files}};
  my @all_set_defs = @{$self->{all_set_defs}};

  my @pg_html=($last_shown>=$first_shown) ?
    renderProblems($r,$user, @pg_files[$first_shown..$last_shown]) : ();

  ##########  Top part
  print CGI::startform({-method=>"POST", -action=>$r->uri}),
    $self->hidden_authen_fields,
      '<div align="center">',
	CGI::start_table({-border=>2});
  $self->make_top_row('all_set_defs'=>\@all_set_defs, 
	       'browse_which'=> $browse_which);
  print CGI::hidden(-name=>'browse_which', -default=>[$browse_which]),
    CGI::hidden(-name=>'problem_seed', -default=>[$problem_seed]);
  for ($j = 0 ; $j < scalar(@pg_files) ; $j++) {
    print CGI::hidden(-name=>"all_past_list$j", -default=>$pg_files[$j]);
  }

  print CGI::hidden(-name=>'first_shown', -default=>[$first_shown]);
  print CGI::hidden(-name=>'last_shown', -default=>[$last_shown]);


  ########## Now print problems
  my $jj;
  for ($jj=0; $jj<scalar(@pg_html); $jj++) { 
    $pg_files[$jj] =~ s|^$ce->{courseDirs}->{templates}/?||;
    $self->make_data_row($pg_files[$jj+$first_shown], $pg_html[$jj], $jj+1);
  }

  ########## Finish things off
  print CGI::end_table();
  print '</div>';
  #  if($first_shown>0 or (1+$last_shown)<scalar(@pg_files)) {
  my ($next_button, $prev_button) = ("", "");
  if ($first_shown > 0) {
    $prev_button = CGI::submit(-name=>"prev_page", -style=>"width:15ex",
			       -value=>"Previous page");
  }
  if ((1+$last_shown)<scalar(@pg_files)) {
    $next_button = CGI::submit(-name=>"next_page", -style=>"width:15ex",
			       -value=>"Next page");
  }
  if (scalar(@pg_files)>0) {
    print CGI::p(($first_shown+1)."-".($last_shown+1)." of ".scalar(@pg_files).
		 " shown.", $prev_button, " ", $next_button);
  }
  #  }
  print CGI::endform(), "\n";

  return "";	
}

############################################## End of Body

# SKEL: To emit your own HTTP header, uncomment this:
# 
#sub header {
#	my ($self) = @_;
#	
#	# Generate your HTTP header here.
#	
#	# If you return something, it will be used as the HTTP status code for this
#	# request. The Apache::Constants module might be useful for gerating status
#	# codes. If you don't return anything, the status code "OK" will be used.
#	return "";
#}

# SKEL: If you need to do any processing after the HTTP header is sent, but before
# any template processing occurs, or you need to calculate values that will be
# used in multiple methods, do it in this method:
# 
#sub initialize {
#my ($self) = @_;
#}

# SKEL: If you need to add tags to the document <HEAD>, uncomment this method:
# 
#sub head {
#	my ($self) = @_;
#	
#	# You can print head tags here, like <META>, <SCRIPT>, etc.
#	
#	return "";
#}

# SKEL: To fill in the "info" box (to the right of the main body), use this
# method:
# 
#sub info {
#	my ($self) = @_;
#	
#	# Print HTML here.
#	
#	return "";
#}

# SKEL: To provide navigation links, use this method:
# 
#sub nav {
#	my ($self, $args) = @_;
#	
#	# See the documentation of path() and pathMacro() in
#	# WeBWorK::ContentGenerator for more information.
#	
#	return "";
#}

# SKEL: For a little box for display options, etc., use this method:
# 
#sub options {
#	my ($self) = @_;
#	
#	# Print HTML here.
#	
#	return "";
#}

# SKEL: For a list of sibling objects, use this method:
# 
#sub siblings {
#	my ($self, $args) = @_;
#	
#	# See the documentation of siblings() and siblingsMacro() in
#	# WeBWorK::ContentGenerator for more information.
#	# 
#	# Refer to implementations in ProblemSet and Problem.
#	
#	return "";
#}

=head1 AUTHOR

Written by John Jones, jj (at) asu.edu.

=cut



1;
