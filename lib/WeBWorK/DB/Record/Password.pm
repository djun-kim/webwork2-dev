################################################################################
# WeBWorK mod_perl (c) 2000-2002 WeBWorK Project
# $Id$
################################################################################

package WeBWorK::DB::Record::Password;
use base WeBWorK::DB::Record;

=head1 NAME

WeBWorK::DB::Record::Password - represent a record from the password table.

=cut

use strict;
use warnings;

sub KEYFIELDS {qw(
	user_id
)}

sub NONKEYFIELDS {qw(
	password
)}

sub FIELDS {qw(
	user_id
	password
)}

1;
