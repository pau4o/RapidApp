package RapidApp::Role::DataStore2;
use Moose::Role;

use strict;

use RapidApp::Include qw(sugar perlutil);

use RapidApp::DataStore2;

has 'record_pk'			=> ( is => 'ro', default => 'id' );
has 'DataStore_class'	=> ( is => 'ro', default => 'RapidApp::DataStore2' );

has 'DataStore' => (
	is			=> 'rw',
	isa		=> 'RapidApp::DataStore2',
	handles => {
		JsonStore					=> 'JsonStore',
#		store_read					=> 'store_read',
#		store_read_raw				=> 'store_read_raw',
		columns						=> 'columns',
		column_order				=> 'column_order',
		include_columns			=> 'include_columns',
		exclude_columns			=> 'exclude_columns',
		include_columns_hash		=> 'include_columns_hash',
		exclude_columns_hash		=> 'exclude_columns_hash',
		apply_columns				=> 'apply_columns',
		column_list					=> 'column_list',
		apply_to_all_columns		=> 'apply_to_all_columns',
		apply_columns_list		=> 'apply_columns_list',
		set_sort						=> 'set_sort',
		batch_apply_opts			=> 'batch_apply_opts',
		set_columns_order			=> 'set_columns_order',
#		record_pk					=> 'record_pk',
		getStore						=> 'getStore',
		getStore_code				=> 'getStore_code',
		store_load_code			=> 'store_load_code',
		store_listeners			=> 'listeners',
		apply_store_listeners	=> 'apply_listeners',
		apply_store_config		=> 'apply_extconfig',
		valid_colname				=> 'valid_colname',
		apply_columns_ordered	=> 'apply_columns_ordered',
		
	
	}
);




has 'DataStore_build_params' => ( is => 'ro', default => undef, isa => 'Maybe[HashRef]' );

sub BUILD {}
before 'BUILD' => sub {
	my $self = shift;

	my $store_params = { record_pk => $self->record_pk };
	
	if ($self->can('create_records')) {
		$self->apply_flags( can_create => 1 ) unless ($self->flag_defined('can_create'));
		$store_params->{create_handler}	= RapidApp::Handler->new( scope => $self, method => 'create_records' ) if ($self->has_flag('can_create'));
	}
	
	if ($self->can('read_records')) {
		$self->apply_flags( can_read => 1 ) unless ($self->flag_defined('can_read'));
		$store_params->{read_handler}	= RapidApp::Handler->new( scope => $self, method => 'read_records' ) if ($self->has_flag('can_read'));
	}
	
	if ($self->can('update_records')) {
		$self->apply_flags( can_update => 1 ) unless ($self->flag_defined('can_update'));
		$store_params->{update_handler}	= RapidApp::Handler->new( scope => $self, method => 'update_records' ) if ($self->has_flag('can_update'));
	}
	
	if ($self->can('destroy_records')) {
		$self->apply_flags( can_destroy => 1 ) unless ($self->flag_defined('can_destroy'));
		$store_params->{destroy_handler}	= RapidApp::Handler->new( scope => $self, method => 'destroy_records' ) if ($self->has_flag('can_destroy'));
	}
	
	$store_params = {
		%$store_params,
		%{ $self->DataStore_build_params }
	} if (defined $self->DataStore_build_params);
	
	$self->apply_modules( store => {
		class		=> $self->DataStore_class,
		params	=> $store_params
	});
	$self->DataStore($self->Module('store',1));
	
	#init the store with all of our flags:
	$self->DataStore->apply_flags($self->all_flags);
	
	$self->add_ONREQUEST_calls('store_init_onrequest');
	$self->add_ONREQUEST_calls_late('apply_store_to_extconfig');
};


sub store_init_onrequest {
	my $self = shift;
	
	# Simulate direct ONREQUEST:
	$self->Module('store');
	

	
	$self->apply_extconfig( columns => $self->DataStore->column_list );
	$self->apply_extconfig( sort => $self->DataStore->get_extconfig_param('sort_spec') );
}


sub apply_store_to_extconfig {
	my $self = shift;
	$self->apply_extconfig( store => $self->Module('store')->JsonStore );
}





#### --------------------- ####


no Moose;
#__PACKAGE__->meta->make_immutable;
1;