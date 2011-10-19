package RapidApp::Role::DbicLink2;
use strict;
use Moose::Role;

use RapidApp::Include qw(sugar perlutil);
use RapidApp::TableSpec::Role::DBIC;


# Colspec attrs can be specified as simple arrayrefs
has 'include_colspec' => ( is => 'ro', isa => 'ArrayRef[Str]', default => sub {[]} );

has 'relation_sep' => ( is => 'ro', isa => 'Str', default => '__' );

has 'ResultSource' => (
	is => 'ro',
	isa => 'DBIx::Class::ResultSource',
	required => 1
);

has 'ResultClass' => ( is => 'ro', lazy_build => 1 );
sub _build_ResultClass {
	my $self = shift;
	my $source_name = $self->ResultSource->source_name;
	return $self->ResultSource->schema->class($source_name);
}

has 'TableSpec' => ( is => 'ro', isa => 'RapidApp::TableSpec', lazy_build => 1 );
sub _build_TableSpec {
	my $self = shift;
	my $TableSpec = RapidApp::TableSpec->with_traits('RapidApp::TableSpec::Role::DBIC')->new(
		name => $self->ResultClass->table,
		relation_sep => $self->relation_sep,
		ResultClass => $self->ResultClass,
		include_colspec => $self->include_colspec
	);
	
	$TableSpec->add_all_related_TableSpecs_recursive;
	return $TableSpec;
}


sub _ResultSet {
	my $self = shift;
	my $Rs = $self->ResultSource->resultset;
	$Rs = $self->ResultSet($Rs) if ($self->can('ResultSet'));
	return $Rs;
}


sub read_records {
	my $self = shift;
	my $params = shift || $self->c->req->params;
	
	scream_color(BOLD.MAGENTA,$params);
	
	my $Rs = $self->_ResultSet;
	
	# Apply base Attrs:
	$Rs = $self->chain_Rs_req_base_Attr($Rs,$params);
	
	# Apply
	
	
	#$Rs->search_rs({},$self->req_Rs_Attr_spec($params));

	# Apply multifilter:
	#$Rs = $Rs->search_rs
	
	
	
	# don't use Row objects
	$Rs = $Rs->search_rs(undef, { result_class => 'DBIx::Class::ResultClass::HashRefInflator' });

	return {
		rows    => [ $Rs->all ],
		results => $Rs->pager->total_entries,
	};
}

sub req_Rs_Search_spec {
	my $self = shift;
	my $params = shift || $self->c->req->params;
	
	return {};
	
	# TEMP:
	#return RapidApp::DbicExtQuery->Search_spec($params)
}

# Applies base request attrs to ResultSet:
sub chain_Rs_req_base_Attr {
	my $self = shift;
	my $Rs = shift || $self->_ResultSet;
	my $params = shift || $self->c->req->params;
	
	$params = {
		start => 0,
		limit => 100000,
		dir => 'asc',
		%$params
	};
	
	my $attr = {
		'+select' => [],
		'+as' => [],
		join => {},
		page => int($params->{start}/$params->{limit}) + 1,
		rows => $params->{limit}
	};
	
	$attr->{order_by} = {
		'-' . $params->{dir} => lc($self->TableSpec->resolve_dbic_colname($params->{sort},$attr->{join}))
	} if (defined $params->{sort} and defined $params->{dir});
	
	my $columns = $self->param_decodeIf($params->{columns},[]);
	
	# Remove duplicates:
	my %Seen = ();
	@$columns = grep { ! $Seen{$_}++ } @$columns;
	
	for my $col (@$columns) {
		my $dbic_name = $self->TableSpec->resolve_dbic_colname($col,$attr->{join});
		push @{$attr->{'+select'}}, $dbic_name;
		push @{$attr->{'+as'}}, $col;
	}
	
	# This makes it look prettier, but is probably not needed:
	#$attr->{join} = $self->TableSpec->hash_with_undef_values_to_array_deep($attr->{join});
	
	return $Rs->search_rs({},$attr);
}

=pod
# Applies multifilter search to ResultSet:
sub chain_Rs_req_multifilter {
	my $self = shift;
	my $Rs = shift || $self->_ResultSet;
	my $params = shift || $self->c->req->params;
	
	my $multifilter = $self->param_decodeIf($params->{multifilter}) or return $Rs;
	
	return $Rs;
	
	return $Rs unless (defined $params->{multifilter});
	
		my $multifilter = JSON::PP::decode_json($params->{multifilter});
	
		my $map_dbfnames;
		$map_dbfnames = sub {
			my $multi = shift;
			if(ref($multi) eq 'HASH') {
				return $map_dbfnames->($multi->{'-and'}) if (defined $multi->{'-and'});
				return $map_dbfnames->($multi->{'-or'}) if (defined $multi->{'-or'});
				
				foreach my $f (keys %$multi) {
					# Not sure why this is commented out.
					# next unless $self->search_permitted($f);
					
					# convert table column name to db field name
					my $dbfName = $self->ExtNamesToDbFields->{$f};
					if (!defined $dbfName) {
						$self->c->log->error("Client supplied Unknown multifilter-field '$f' in Ext Query!");
						next;
					}
					
					$multi->{$dbfName} = $multi->{$f};
					delete $multi->{$f};
					
					# --- translate special content conditions to "LIKE" conditions
					if (defined $multi->{$dbfName}->{contains}) {
						$multi->{$dbfName}->{like} = '%' . $multi->{$dbfName}->{contains} . '%';
						delete $multi->{$dbfName}->{contains};
					}
					
					if (defined $multi->{$dbfName}->{starts_with}) {
						$multi->{$dbfName}->{like} = $multi->{$dbfName}->{starts_with} . '%';
						delete $multi->{$dbfName}->{starts_with};
					}
					
					if (defined $multi->{$dbfName}->{ends_with}) {
						$multi->{$dbfName}->{like} = '%' . $multi->{$dbfName}->{ends_with};
						delete $multi->{$dbfName}->{ends_with};
					}
					
					if (defined $multi->{$dbfName}->{not_contain}) {
						$multi->{$dbfName}->{'not like'} = '%' . $multi->{$dbfName}->{not_contain} . '%';
						delete $multi->{$dbfName}->{not_contain};
					}
					# ---
					
					# -- Add '%' characters to "like" searches: (disabled in favor of special content conditions above)
					#if (defined $multi->{$dbfName}->{like} and not $multi->{$dbfName}->{like} =~ /\%/) {
					#	$multi->{$dbfName}->{like} = '%' . $multi->{$dbfName}->{like} . '%';
					#}
					# --

				}
			}
			elsif(ref($multi) eq 'ARRAY') {
				foreach my $item (@$multi) {
					$map_dbfnames->($item);
				}
			}
		};
		
		$map_dbfnames->($multifilter);
	
	
		# Recursive sub to make all lists explicitly '-and' lists:
		my $add_ands;
		$add_ands = sub {
			my $multi = shift;
			return $multi unless (ref($multi) eq 'ARRAY');
			
			foreach my $item (@$multi) {
				$item = $add_ands->($item);
			}
			return { '-and' => $multi };
		};
		
		push @$filter_search, $add_ands->($multifilter);
	}
	
	
}
=cut

sub param_decodeIf {
	my $self = shift;
	my $param = shift;
	my $default = shift || undef;
	
	return $default unless (defined $param);
	
	return $param if (ref $param);
	return $self->json->decode($param);
}


1;