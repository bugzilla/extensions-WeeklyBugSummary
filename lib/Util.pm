# The contents of this file are subject to the Mozilla Public
# License Version 1.1 (the "License"); you may not use this file
# except in compliance with the License. You may obtain a copy of
# the License at http://www.mozilla.org/MPL/
#
# weekly-bug-summary.cgi
#
# Display some nice bug stats for the GNOME weekly summary.
#
# This file was based on the original mostfrequent.cgi but has been
# modified GREATLY by Wayne Schuller (k_wayne@linuxpower.org), Jan 2002.
#
# It was later ported to be a Bugzilla extension by Frederic Peters
# (fpeters@0d.be), Sep 2009.
#
# TODO
#   - Some products have way too many bugs. Break it down via component.
#   - Use percentages for the diff figures.

package Bugzilla::Extension::WeeklyBugSummary::Util;

use strict;
use base qw(Exporter);

use Bugzilla;
use Bugzilla::Constants;
use Bugzilla::Error;
use Bugzilla::Util;
use Bugzilla::User;
use Bugzilla::Field;

our @EXPORT = qw(
    page
);

sub page {
    my %params = @_;
    my ($vars, $page) = @params{qw(vars page_id)};
    if ($page =~ /^weekly-bug-summary\./) {
        _page_weekly_bug_summary($vars);
    }
}

sub _page_weekly_bug_summary {
    my $vars = shift;

    my $cgi = Bugzilla->cgi;
    my $dbh = Bugzilla->dbh;
    my $user = Bugzilla->user;

    # make sensible defaults.
    my $version = undef;               # Don't limit to "2.7/2.8" or "2.5/2.6", etc.
    my $days = 7;           # Change this if defn of week changes.
    my $products = 15;      # Show the top 15 products.
    my $hunters = 15;       # Show the top 15 hunters 
    my $reporters = 15;     # Show the top 15 reporters
    my $patchers = 10;      # Show the top 10 patchers
    my $reviewers = 10;     # Show the top 10 reviewers
    my $keyword = undef;    # Don't limit to any keyword.
    my $classification=undef;   # Don't limit to just one classification.
    my $product = undef;    # Don't limit to just one product.
    my $links = "yes";      # Create links (can get very large sometimes)

    if (defined $cgi->param('days') && $cgi->param('days') ne ""){
        $days = $cgi->param('days');
        detaint_natural($days) || die "days parameter must be a number";
    }

    if (defined $cgi->param('products') && $cgi->param('products') ne ""){
        $products = $cgi->param('products');
        detaint_natural($products) || die "products parameter must be a number";
    }

    if (defined $cgi->param('hunters') && $cgi->param('hunters') ne ""){
        $hunters = $cgi->param('hunters');
        detaint_natural($hunters) || die "hunters parameter must be a number";
    }

    if (defined $cgi->param('reporters') && $cgi->param('reporters') ne ""){
        $reporters = $cgi->param('reporters');
        detaint_natural($reporters) || die "reporters parameter must be a number";
    }

    if (defined $cgi->param('patchers') && $cgi->param('patchers') ne ""){
        $patchers = $cgi->param('patchers');
        detaint_natural($patchers) || die "patchers parameter must be a number";
    }

    if (defined $cgi->param('reviewers') && $cgi->param('reviewers') ne ""){
        $reviewers = $cgi->param('reviewers');
        detaint_natural($reviewers) || die "reviewers parameter must be a number";
    }

    if (defined $cgi->param('links')){
        $links = $cgi->param('links');
    }

    if (defined $cgi->param('keyword')){
        $keyword = $cgi->param('keyword');
        trick_taint($keyword);
    }

    if (defined $cgi->param('version') && $cgi->param('version') ne ""){
        $version = $cgi->param('version');
        trick_taint($version);
    }

    if (defined $cgi->param('classification') && $cgi->param('classification') ne ""){
        $classification = get_classification_id($cgi->param('classification'));
    }

    if (defined $cgi->param('product') && $cgi->param('product') ne ""){
        $product = get_product_id($cgi->param('product'));
        $products = 0;
        $classification = undef;
    }

    if ($days >= 90) {
        $links = 'no';
    }

    my $totalbugs = &get_total_bugs_on_bugzilla($keyword, $version, 
                                                $classification, $product);

    my ($bugs_opened, $opened_buglist) = &bugs_opened($days, $keyword, $version,
                                                      $classification, $product);
    my ($bugs_closed, $closed_buglist) = &bugs_closed($days, $keyword, $version,
                                                      $classification, $product);

    #if ($links eq "yes") {
    #    print "<a href=\"$buglist\">$bugs_closed</a> reports closed";
    #} else {
    #    print "$bugs_closed reports closed";
    #}

    my ($productlist) =
        &get_product_bug_lists($products, $days, $keyword, $links, $version,
                               $classification);

    my ($hunterlist) = 
        &get_bug_hunters_list($hunters, $days, $keyword, 
                              $links, $version, $classification, $product);

    my ($reporterlist) =
        &get_bug_reporters_list($reporters, $days, $keyword, 
                                $links, $version, $classification, $product);

    my ($patchsubmitterlist) = 
        &get_patch_submitters_list($patchers, $days, $keyword,
                                   $links, $version, $classification, $product);

    my ($patchreviewerlist) = 
        &get_patch_reviewers_list($reviewers, $days, $keyword,
                                  $links, $version, $classification, $product);

    # CGI params / defaults:
    $vars->{'days'} = $days;
    $vars->{'keyword'} = $keyword;
    $vars->{'links'} = $links;
    $vars->{'version'} = $version;
    $vars->{'classification'} =
        $classification ? get_classification_name($classification) : undef;;
    $vars->{'product'} = $product ? get_product_name($product) : undef;
    $vars->{'products'} = $products;
    $vars->{'hunters'} = $hunters;
    $vars->{'reporters'} = $reporters;
    $vars->{'patchers'} = $patchers;
    $vars->{'reviewers'} = $reviewers;

    # Retrieved from queries:
    $vars->{'totalbugs'} = $totalbugs;
    $vars->{'openbugs'} = $bugs_opened;
    $vars->{'openbuglist'} = $opened_buglist;
    $vars->{'closedbugs'} = $bugs_closed;
    $vars->{'closedbuglist'} = $closed_buglist;
    $vars->{'productlist'} = $productlist;
    $vars->{'hunterlist'} = $hunterlist;
    $vars->{'reporterlist'} = $reporterlist;
    $vars->{'patcherlist'} = $patchsubmitterlist;
    $vars->{'reviewerlist'} = $patchreviewerlist;
}

sub get_total_bugs_on_bugzilla {
    my($keyword, $version, $classification_id, $product_id) = @_;

    my @args;

    my $query = "
     SELECT COUNT(bugs.bug_id)
       FROM bugs";

    if ($classification_id) {
        $query .= "
 INNER JOIN products
         ON bugs.product_id = products.id";
    }

    $query .= "
      WHERE (bugs.bug_status = 'NEW' OR bugs.bug_status = 'ASSIGNED'
             OR bugs.bug_status = 'REOPENED'
             OR bugs.bug_status = 'UNCONFIRMED')";

    if ($keyword) {
        push(@args, lc($keyword));
        $query .= "
        AND INSTR(LOWER(bugs.keywords), ?)";
    }
    if ($version) {
        push(@args, $version);
        $query .= "
        AND bugs.cf_gnome_version = ?";
    }
    if ($classification_id) {
        push(@args, $classification_id);
        $query .= "
        AND products.classification_id = ?";
    }
    if ($product_id) {
        push(@args, $product_id);
        $query .= "
        AND bugs.product_id = ?";
    }

    my ($count) = Bugzilla->dbh->selectrow_array($query, undef, @args);
    return($count);
}

# bugs_closed
# Show how many bugs have been closed for $product_id in $days.
# Pass undef as product_id to get all products.
sub bugs_closed {
    my($days, $keyword, $version, $classification_id, $product_id) = @_;

    my $dbh = Bugzilla->dbh;
    my @args;

    # We are going to build a long SQL query.
    my $query = "
     SELECT DISTINCT bugs.bug_id
       FROM bugs
 INNER JOIN bugs_activity
         ON bugs.bug_id = bugs_activity.bug_id";

    if ($classification_id) {
        $query .= "
 INNER JOIN products
         ON bugs.product_id = products.id";
    }

    $query .= "
      WHERE bugs.bug_status IN ('RESOLVED','CLOSED','VERIFIED')
        AND bugs_activity.added IN ('RESOLVED','CLOSED')
        AND bugs_activity.bug_when >= " .
            $dbh->sql_date_math('LOCALTIMESTAMP(0)', '-', '?', 'DAY');

    push(@args, $days);

    if ($keyword) {
        push(@args, lc($keyword));
        $query .= "
        AND INSTR(LOWER(bugs.keywords), ?)";
    }
    if ($version) {
        push(@args, $version);
        $query .= "
        AND bugs.cf_gnome_version = ?";
    }
    if ($classification_id) {
        push(@args, $classification_id);
        $query .= "
        AND products.classification_id = ?";
    }
    if ($product_id) {
        $query .= "
        AND bugs.product_id = $product_id";
    }

    $query .= "
   GROUP BY bugs.bug_id";

    my $bugs = Bugzilla->dbh->selectcol_arrayref($query, undef, @args);

    # Create URL of all the bugs that match this function.
    my $urlbase = Bugzilla->params->{'urlbase'};
    my $buglist = "$urlbase/buglist.cgi?bug_id=" . join(",", @$bugs);
    my $count = scalar @$bugs;

    return(($count, $buglist));
}

# bugs_opened
# Show how many bugs have been opened for $product_id in $days.
# Pass undef as product_id to get all products.
sub bugs_opened {
    my($days, $keyword, $version, $classification_id, $product_id) = @_;

    my $dbh = Bugzilla->dbh;
    my @args;

    # We are going to build a long SQL query.
    my $query = "
     SELECT bugs.bug_id
       FROM bugs";
    
    if ($classification_id) {
        $query .= "
 INNER JOIN products
         ON bugs.product_id = products.id";
    }

    $query .= "
      WHERE bugs.creation_ts >= " . $dbh->sql_date_math('LOCALTIMESTAMP(0)', '-', '?', 'DAY');

    push(@args, $days);

    if ($keyword) {
        push(@args, lc($keyword));
        $query .= "
        AND INSTR(LOWER(bugs.keywords), ?)";
    }
    if ($version) {
        push(@args, $version);
        $query .= "
        AND bugs.cf_gnome_version = ?";
    }
    if ($classification_id) {
        push(@args, $classification_id);
        $query .= "
        AND products.classification_id = ?";
    }
    if ($product_id) {
        push(@args, $product_id);
        $query .= "
        AND bugs.product_id = ?";
    }

    $query .= "
      GROUP BY bugs.bug_id";

    my $bugs = Bugzilla->dbh->selectcol_arrayref($query, undef, @args);

    # Create URL of all the bugs that match this function.
    my $urlbase = Bugzilla->params->{'urlbase'};
    my $buglist = "$urlbase/buglist.cgi?bug_id=" . join(",", @$bugs);
    my $count = scalar @$bugs;

    return(($count, $buglist));
}

sub get_product_bug_lists {
    my($number, $days, $keyword, $links, $version, $classification_id) = @_;

    my @args;

    # We are going to build a long SQL query.
    my $query = "
        SELECT bugs.product_id, products.name AS product, COUNT(bugs.bug_id) AS n 
          FROM bugs
    INNER JOIN products
            ON bugs.product_id = products.id
         WHERE (bugs.bug_status = 'NEW' OR bugs.bug_status = 'ASSIGNED' 
                OR bugs.bug_status = 'REOPENED'
                OR bugs.bug_status = 'UNCONFIRMED')
           AND bugs.bug_severity != 'enhancement'";

    if ($keyword) {
        push(@args, lc($keyword));
        $query .= "
           AND INSTR(LOWER(bugs.keywords), ?)";
    }
    if ($version) {
        push(@args, $version);
        $query .= "
           AND bugs.cf_gnome_version = ?";
    }
    if ($classification_id) {
        push(@args, $classification_id);
        $query .= "
           AND products.classification_id = ?";
    }

    $query .= "
      GROUP BY bugs.product_id
      ORDER BY n DESC " . Bugzilla->dbh->sql_limit($number);

    my $productlist = Bugzilla->dbh->selectall_arrayref($query, undef, @args);

    foreach my $rowRef (@$productlist) {
        my ($product_id, $product, $count) = @$rowRef;

        my ($opened, $openedlist) = &bugs_opened($days, $keyword, $version,
                                                 $classification_id, $product_id);
        my ($closed, $closedlist) = &bugs_closed($days, $keyword, $version,
                                                 $classification_id, $product_id);

        my $change = $opened-$closed;

        push(@$rowRef, $opened, $openedlist, $closed, $closedlist, $change);
    }

    return $productlist;
}

sub get_bug_hunters_list {
    my($number, $days, $keyword, $links, $version,
       $classification_id, $product_id) = @_;

    my $dbh = Bugzilla->dbh;
    my @args;

    # We are going to build a long SQL query.
    my $query = "
        SELECT bugs_activity.who AS userid, COUNT(bugs.bug_id) as n 
          FROM bugs
    INNER JOIN bugs_activity
            ON bugs.bug_id = bugs_activity.bug_id";

    if ($classification_id) {
        $query .= "
    INNER JOIN products
            ON bugs.product_id = products.id";
    }

    $query .= "
         WHERE bugs.bug_status IN ('RESOLVED','CLOSED','VERIFIED')
           AND bugs_activity.added IN ('RESOLVED','CLOSED')
           AND bugs_activity.bug_when =
                 (SELECT MAX(bug_when)
                    FROM bugs_activity ba
                   WHERE ba.added IN ('RESOLVED','CLOSED')
                     AND ba.removed IN ('UNCONFIRMED','REOPENED',
                                        'NEW','ASSIGNED','NEEDINFO')
                     AND ba.bug_id = bugs_activity.bug_id)
           AND bugs_activity.bug_when >= " .
                   $dbh->sql_date_math('LOCALTIMESTAMP(0)', '-', '?', 'DAY');

    push(@args, $days);

    if ($keyword) {
        push(@args, lc($keyword));
        $query .= "
           AND INSTR(LOWER(bugs.keywords), ?)";
    }
    if ($version) {
        push(@args, $version);
        $query .= "
           AND bugs.cf_gnome_version = ?";
    }
    if ($classification_id) {
        push(@args, $classification_id);
        $query .= "
           AND products.classification_id = ?";
    }
    if ($product_id) {
        push(@args, $product_id);
        $query .= "
           AND bugs.product_id = ?";
    }

    $query .= "
      GROUP BY bugs_activity.who
      ORDER BY n desc " . Bugzilla->dbh->sql_limit($number);

    my $hunterlist = Bugzilla->dbh->selectall_arrayref($query, undef, @args);

    foreach my $rowRef (@$hunterlist) {
        my($userid, $count) = @$rowRef;
        
        push(@$rowRef, new Bugzilla::User($userid));
        if ($links eq "yes") {
            my $buglist = &get_hunter_bugs($userid, $days, $keyword, $version,
                                           $classification_id, $product_id);
            push(@$rowRef, $buglist);
        }
    }

    return $hunterlist;
}

sub get_hunter_bugs {
    my($userid, $days, $keyword, $version, $classification_id, $product_id) = @_;

    my $dbh = Bugzilla->dbh;
    my @args;

    # We are going to build a long SQL query.
    my $query = "
         SELECT DISTINCT bugs.bug_id
           FROM bugs
     INNER JOIN bugs_activity
             ON bugs.bug_id = bugs_activity.bug_id";

    if ($classification_id) {
        $query .= "
          INNER JOIN products
                  ON bugs.product_id = products.id";
    }

    $query .= "
         WHERE bugs.bug_status IN ('RESOLVED','CLOSED','VERIFIED')
           AND bugs_activity.added IN ('RESOLVED','CLOSED')
           AND bugs_activity.bug_when =
                 (SELECT MAX(bug_when)
                    FROM bugs_activity ba
                   WHERE ba.added IN ('RESOLVED','CLOSED')
                     AND ba.removed IN ('UNCONFIRMED','REOPENED',
                                        'NEW','ASSIGNED','NEEDINFO')
                     AND ba.bug_id = bugs_activity.bug_id)
            AND bugs_activity.bug_when >= " .
                    $dbh->sql_date_math('LOCALTIMESTAMP(0)', '-', '?', 'DAY') . "
            AND bugs_activity.who = ?";

    push(@args, $days, $userid);

    if ($keyword) {
        push(@args, lc($keyword));
        $query .= "
           AND INSTR(LOWER(bugs.keywords), ?)";
    }
    if ($version) {
        push(@args, $version);
        $query .= "
           AND bugs.cf_gnome_version = ?";
    }
    if ($classification_id) {
        push(@args, $classification_id);
        $query .= "
                 AND products.classification_id = ?";
    }
    if ($product_id) {
        push(@args, $product_id);
        $query .= "
           AND bugs.product_id = ?";
    }

    my $bugs = Bugzilla->dbh->selectcol_arrayref($query, undef, @args);

    my $urlbase = Bugzilla->params->{'urlbase'};
    my $buglist = "$urlbase/buglist.cgi?bug_id=" . join(",", @$bugs);

    return ($buglist);
}

sub get_bug_reporters_list {
    my($number, $days, $keyword, $links, $version,
       $classification_id, $product_id) = @_;

    my $dbh = Bugzilla->dbh;
    my @args;

    # We are going to build a long SQL query.
    my $query = "
        SELECT bugs.reporter AS userid, COUNT(DISTINCT bugs.bug_id) AS n 
          FROM bugs";

    if ($classification_id) {
        $query .= "
          INNER JOIN products
                  ON bugs.product_id = products.id";
    }

    $query .= "
         WHERE bugs.creation_ts >= " . $dbh->sql_date_math('LOCALTIMESTAMP(0)', '-', '?', 'DAY') . "
           AND NOT (bugs.bug_status = 'RESOLVED' AND 
                    bugs.resolution IN ('DUPLICATE','INVALID','NOTABUG',
                                        'NOTGNOME','INCOMPLETE'))";

    push(@args, $days);

    if ($keyword) {
        push(@args, lc($keyword));
        $query .= "
           AND INSTR(LOWER(bugs.keywords), ?)";
    }
    if ($version) {
        push(@args, $version);
        $query .= "
           AND bugs.cf_gnome_version = ?";
    }
    if ($classification_id) {
        push(@args, $classification_id);
        $query .= "
           AND products.classification_id = ?";
    }
    if ($product_id) {
        push(@args, $product_id);
        $query .= "
           AND bugs.product_id = ?";
    }
    
    $query .= "
      GROUP BY bugs.reporter
      ORDER BY n DESC " . Bugzilla->dbh->sql_limit($number);

    my $reporterlist = Bugzilla->dbh->selectall_arrayref($query, undef, @args);

    foreach my $rowRef (@$reporterlist) {
        my ($userid, $count) = @$rowRef;

        push(@$rowRef, new Bugzilla::User($userid));
        if ($links eq "yes") {
            my $buglist = &get_reporter_bugs($userid, $days, $keyword,
                                             $version, $classification_id,
                                             $product_id);
            push(@$rowRef, $buglist);
        }
    }

    return $reporterlist;
}

sub get_reporter_bugs() {
    my($userid, $days, $keyword, $version, $classification_id, $product_id) = @_;

    my $dbh = Bugzilla->dbh;
    my @args;

    # We are going to build a long SQL query.
    my $query = "
     SELECT bugs.bug_id
       FROM bugs";

    if ($classification_id) {
        $query .= "
 INNER JOIN products
         ON bugs.product_id = products.id";
    }

    $query .= "
      WHERE bugs.creation_ts >= " . $dbh->sql_date_math('LOCALTIMESTAMP(0)', '-', '?', 'DAY') . "
        AND bugs.reporter = ?
        AND NOT (bugs.bug_status = 'RESOLVED' AND 
                 bugs.resolution IN ('DUPLICATE','INVALID','NOTABUG',
                                     'NOTGNOME','INCOMPLETE'))";
    
    push(@args, $days, $userid);
    
    if ($keyword) {
        push(@args, lc($keyword));
        $query .= "
           AND INSTR(LOWER(bugs.keywords), ?)";
    }
    if ($version) {
        push(@args, $version);
        $query .= "
           AND bugs.cf_gnome_version = ?";
    }
    if ($classification_id) {
        push(@args, $classification_id);
        $query .= "
       AND products.classification_id = ?";
    }
    if ($product_id) {
        push(@args, $product_id);
        $query .= "
       AND bugs.product_id = ?";
    }

    my $bugs = Bugzilla->dbh->selectcol_arrayref($query, undef, @args);

    my $urlbase = Bugzilla->params->{'urlbase'};
    my $buglist = "$urlbase/buglist.cgi?bug_id=" . join(",", @$bugs);

    return ($buglist);
}

sub get_patch_submitters_list {
    my($number, $days, $keyword, $links, $version,
       $classification_id, $product_id) = @_;

    my $dbh = Bugzilla->dbh;
    my @args;

    # We are going to build a long SQL query.
    my $query = "      SELECT attachments.submitter_id AS userid, 
                              COUNT(DISTINCT attachments.attach_id) AS n 
                         FROM attachments ";
    if ($keyword || $version || $classification_id || $product_id) {
        $query .=" INNER JOIN bugs
                           ON attachments.bug_id = bugs.bug_id ";
    }
    if ($classification_id) {
        $query .= "
          INNER JOIN products
                  ON bugs.product_id = products.id";
    }
    $query .= "         WHERE attachments.creation_ts >= " .
                                  $dbh->sql_date_math('LOCALTIMESTAMP(0)', '-', '?', 'DAY') . "
                          AND attachments.ispatch = 1
                          AND attachments.isobsolete = 0";

    push(@args, $days);

    if ($keyword) {
        push(@args, lc($keyword));
        $query .= "       AND INSTR(LOWER(bugs.keywords), ?)";
    }
    if ($version) {
        push(@args, $version);
        $query .= "       AND bugs.cf_gnome_version = ?";
    }
    if ($classification_id) {
        push(@args, $classification_id);
        $query .= "
                 AND products.classification_id = ?";
    }
    if ($product_id) {
        push(@args, $product_id);
        $query .= "
       AND bugs.product_id = ?";
    }
    
    $query .= "      GROUP BY attachments.submitter_id
                     ORDER BY n DESC " . Bugzilla->dbh->sql_limit($number);

    my $submitterlist = Bugzilla->dbh->selectall_arrayref($query, undef, @args);

    foreach my $rowRef (@$submitterlist) {
        my ($userid, $count) = @$rowRef;

        push(@$rowRef, new Bugzilla::User($userid));
#        if ($links eq "yes") {
#            my $buglist = &get_reporter_bugs($userid, $days, $keyword, $version);
#            push(@$rowRef, $buglist);
#        }
    }

    return $submitterlist;
}

sub get_patch_reviewers_list {
    my($number, $days, $keyword, $links, $version,
       $classification_id, $product_id) = @_;

    my $dbh = Bugzilla->dbh;
    my @args;

    # We are going to build a long SQL query.
    my $query = "
        SELECT bugs_activity.who AS userid, COUNT(DISTINCT bugs_activity.attach_id) as n 
          FROM bugs_activity ";
    if ($keyword || $version || $classification_id || $product_id) {
        $query .= "
    INNER JOIN bugs
            ON bugs_activity.bug_id = bugs.bug_id ";
    }
    if ($classification_id) {
        $query .= "
    INNER JOIN products
            ON bugs.product_id = products.id";
    }
    $query .= "
         WHERE bugs_activity.fieldid = ?
           AND bugs_activity.removed = 'none'
           AND bugs_activity.bug_when >= " .
                   $dbh->sql_date_math('LOCALTIMESTAMP(0)', '-', '?', 'DAY');

    # XXX  - relies on attachments.status
    push(@args, get_field_id('attachments.status'), $days);

    if ($keyword) {
        push(@args, lc($keyword));
        $query .= "
           AND INSTR(LOWER(bugs.keywords), ?)";
    }
    if ($version) {
        push(@args, $version);
        $query .= "
           AND bugs.cf_gnome_version = ?";
    }
    if ($classification_id) {
        push(@args, $classification_id);
        $query .= "
           AND products.classification_id = ?";
    }
    if ($product_id) {
        push(@args, $product_id);
        $query .= "
           AND bugs.product_id = ?";
    }

    $query .= "
      GROUP BY bugs_activity.who
      ORDER BY n desc " . Bugzilla->dbh->sql_limit($number);

    my $hunterlist = Bugzilla->dbh->selectall_arrayref($query, undef, @args);

    foreach my $rowRef (@$hunterlist) {
        my($userid, $count) = @$rowRef;
        
        push(@$rowRef, new Bugzilla::User($userid));
#        if ($links eq "yes") {
#            my $buglist = &get_hunter_bugs($userid, $days, $keyword, $version);
#            push(@$rowRef, $buglist);
#        }
    }

    return $hunterlist;
}
