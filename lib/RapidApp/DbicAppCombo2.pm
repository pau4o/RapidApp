package RapidApp::DbicAppCombo2;
use strict;
use warnings;
use Moose;
extends 'RapidApp::AppCombo2';

use RapidApp::Include qw(sugar perlutil);

### TODO: Bring this into the fold with DbicLink. For now, it is simple enough this isn't really needed

has 'ResultSet' => ( is => 'ro', isa => 'Object', required => 1 );
has 'RS_condition' => ( is => 'ro', isa => 'Ref', default => sub {{}} );
has 'RS_attr' => ( is => 'ro', isa => 'Ref', default => sub {{}} );
has 'record_pk' => ( is => 'ro', isa => 'Str', required => 1 );

sub BUILD {
	my $self = shift;
	
	# Remove the width hard coded in AppCombo2 (still being left in AppCombo2 for legacy
	# but will be removed in the future)
	$self->delete_extconfig_param('width');
	
	$self->apply_extconfig(
		itemId	=> $self->name . '_combo',
		forceSelection => \1,
		editable => \0,
	);
}

use RapidApp::Role::DbicLink2;
sub param_decodeIf { RapidApp::Role::DbicLink2::param_decodeIf(@_) }

sub read_records {
	my $self = shift;
	
	my $Rs = $self->get_ResultSet;
  
  my $Source = $Rs->result_source;
  my $source_name = $Rs->result_source->source_name;
  my $class = $Source->schema->class($source_name);
    
	# TODO: Get this duplicate crap out of here and make this work natively with
	# DbicLink2 methods
	$Rs = $self->RapidApp::Role::DbicLink2::chain_Rs_req_explicit_resultset($Rs);
  
  # -- NEW: if no order_by is defined, set it to by on the displayField
  # which is the most obvious/useful behavior:
  #   TODO/FIXME: This is using a tmp/hack in order to support the case
  #   where the displayField is a Virtual Column. See the notes with the
  #   RapidApp::DBIC::Component::VirtualColumnsExt::_virtual_column_select()
  #   method, .... and actually, really address this. This has been a known
  #   thing for a long time, and is the reason this default order_by wasn't
  #   enabled in the first place. But I don't want this practical/useful/common-sense
  #   feature to be held up. So this is about being practical (and is also
  #   a useful REMINDER that this still needs to be addressed)
  unless (exists $Rs->{attrs}{order_by}) {
    my $col_select = $self->displayField;
    if($class->can('_virtual_column_select')) {
      $col_select = $class->_virtual_column_select($col_select);
    }
    $Rs = $Rs->search_rs(undef,{
      order_by => { '-asc' => $col_select }
    });
  }
  # --
  
  # New: fail-safe max-rows:
  $Rs = $Rs->search_rs(undef,{ rows => 500 }) unless (exists $Rs->{attrs}{rows});

  my $rows = [];
  # We still have to do it the slow way for virtual display columns (#66):
  if($class->can('has_virtual_column') && $class->has_virtual_column($self->displayField)) {
    foreach my $row ($Rs->all) {
      my $data = { $row->get_columns };
      push @$rows, $data;
    }
  }
  else {
    # Much faster but doesn't work for virtual columns:
    $Rs = $Rs->search_rs(undef, { result_class => 'DBIx::Class::ResultClass::HashRefInflator' });
    $rows = [ $Rs->all ];
  }

  return {
    rows    => $rows,
    results => scalar(@$rows)
  };
}


sub get_ResultSet {
	my $self = shift;
	my $params = $self->c->req->params;
  
  # See also DBIx::Class::Helper::ResultSet::SearchOr for an approach
  # to the problem the below code is solving...
	
	# todo: merge this in with the id_in stuff in dbiclink... Superbox??
	# this module is really currently built just for TableSpec...
	my $search = $self->RS_condition;
	$search = { '-or' => [ $self->RS_condition, { 'me.' . $self->record_pk => $params->{valueqry} } ] } if (
		defined $params->{valueqry} and
		scalar (keys %{ $self->RS_condition }) > 0 #<-- if RS_Condition is empty don't restrict
	);
	
	my $Rs = $self->ResultSet;
	
	# Allow creating a custom 'AppComboRs' method within the ResultSet Class
	# for global use: (TODO: get a better/more well though out API):
	$Rs = $Rs->AppComboRs if ($Rs->can('AppComboRs'));
	
	return $Rs->search_rs($search,$self->RS_attr);
}



1;


