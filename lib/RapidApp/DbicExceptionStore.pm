package RapidApp::DbicExceptionStore;

use Moose;
with 'RapidApp::Role::ExceptionStore';

use RapidApp::Include 'perlutil';

use Storable ('freeze', 'thaw');

=head1 NAME

RapidApp::DbicExceptionStore;

=cut

has 'resultSource' => ( is => 'rw', isa => 'DBIx::Class::ResultSource' );

=head1 ATTRIBUTES

=over

=item resultSource

The DBIC ResultSource matching the required schema (below)

=back

=head1 DESCRIPTION

This module provides the ExceptionStore role which reads/writes rows to the exceptions table,
and then serializes relevant bits of data into a blob field to be deserialized and inspected later.

The required schema is (subject to change):

=over

=item who

Stored in database column.  The UserID from the user object in the catalyst object, as found in
the RapidApp::Error object.

=item what

Stored in database column.  The summary text of the exception, limited to 64 characters,
useful for quick identification in grid lists.  This is the RapidApp::Error->message text.

=item when

Stored in database column.  The DateTime of when the exception occured.  This columns should be
configured to inflate and deflate from DateTime objects.

=item where

The source location where the exception occured.  This is extracted from the Error object and
duplicated here for SQL searchability.

=item why

Serialized into the blob.  The exception object itself, which is a RapidApp::Error object.

=back

In SQL DDL:
  CREATE TABLE exception (
    id int not null AUTO_INCREMENT,
    who int, # or string, or whatever needed
    what varchar(64) not null,
    when DateTime not null,
    where varchar(64) not null,
    why BLOB,
    PRIMARY KEY (id)
  )

=head1 METHODS

=head2 $id= $store->saveException( $err )

Writes out a new record in the table, saving this exception object.

=cut
sub saveException {
	my ($self, $err)= @_;
	my $log= RapidApp::ScopedGlobals->log;
	
	my $uid= (defined $err->data && defined $err->data->{user})? $err->data->{user}->id : undef;
	
	my $msg= $err->message;
	# truncate strings which actually go into varchar columns
	length($msg) < 64 or $msg= substr($msg,0,60).'...';
	
	my $srcLoc= $err->srcLoc;
	# truncate strings which actually go into varchar columns
	$srcLoc =~ s|.*?/lib/||;
	!defined($srcLoc) || length($srcLoc) < 64 or $srcLoc= substr($srcLoc,0,64);
	
	my $refId;
	try {
		
		$err->trimTrace;
		local $Storable::forgive_me= 1; # ignore non-storable things
		my $serialized= freeze( $err );
		if (!defined $serialized || length($serialized) > 65000) {
			$log->warn("Error serialization was ".length($serialized)." bytes, attempting to save an approximation");
			
			$serialized= freeze( { map { substr(''.$_, 0, 1000) } %$err } );
			if (!defined $serialized || length($serialized) > 65000) {
				$serialized= freeze( { message => 'Unable to save error object' } );
			}
		}
		
		my $rs= $self->resultSource;
		defined $rs or die "Missing ResultSource";
		
		my $row= $rs->resultset->create({
			who   => $uid,
			what  => $msg,
			when  => $err->dateTime,
			where => $srcLoc,
			why   => $serialized,
		});
		$refId= $row->id;
		$log->info("Exception saved as refId ".$refId);
	}
	catch {
		$log->error("Failed to save exception to database: ".$_);
		$refId= undef;
	};
	return $refId;
}

=head2 $err= $store->loadException( $id )

=cut
sub loadException {
	my ($self, $id)= @_;
	
	my $rs= $self->resultSource;
	defined $rs or die "Missing ResultSource";
	
	my $row= $rs->resultset->find($id);
	defined $row or die "No excption exists for id $id";
	
	my $serialized= $row->why;
	RapidApp::ScopedGlobals->log->debug('Read '.length($serialized).' bytes of serialized error');
	my $err= thaw($serialized);
	defined $err or die "Failed to deserialize exception";
	return $err;
}

1;
