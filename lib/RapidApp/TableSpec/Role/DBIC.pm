package RapidApp::TableSpec::Role::DBIC;
use strict;
use Moose::Role;
use Moose::Util::TypeConstraints;

use RapidApp::TableSpec::DbicTableSpec;
use RapidApp::TableSpec::ColSpec;

use RapidApp::Include qw(sugar perlutil);

use RapidApp::DBIC::Component::TableSpec;

use Text::Glob qw( match_glob );
use Text::WagnerFischer qw(distance);
use Clone qw( clone );

use Switch qw(switch);

# ---
# Attributes 'ResultSource', 'ResultClass' and 'schema' are interdependent. If ResultSource
# is not supplied to the constructor, both ResultClass and schema must be.
has 'ResultSource', is => 'ro', isa => 'DBIx::Class::ResultSource', lazy => 1,
default => sub {
	my $self = shift;
	
	my $schema_attr = $self->meta->get_attribute('schema');
	$self->meta->throw_error("'schema' not supplied; cannot get ResultSource automatically!")
		unless ($schema_attr->has_value($self));
	
	return $self->schema->source($self->ResultClass);
};

has 'ResultClass', is => 'ro', isa => 'Str', lazy => 1, 
default => sub {
	my $self = shift;
	my $source_name = $self->ResultSource->source_name;
	return $self->ResultSource->schema->class($source_name);
};

has 'schema', is => 'ro', lazy => 1, default => sub { (shift)->ResultSource->schema; };
# ---


=pod
has 'data_type_profiles' => ( is => 'ro', isa => 'HashRef', default => sub {{
	text 			=> [ 'bigtext' ],
	blob 			=> [ 'bigtext' ],
	varchar 		=> [ 'text' ],
	char 			=> [ 'text' ],
	float			=> [ 'number' ],
	integer		=> [ 'number', 'int' ],
	tinyint		=> [ 'number', 'int' ],
	mediumint	=> [ 'number', 'int' ],
	bigint		=> [ 'number', 'int' ],
	datetime		=> [ 'datetime' ],
	timestamp	=> [ 'datetime' ],
	date			=> [ 'date' ]
}});
=cut

subtype 'ColSpec', as 'Object';
coerce 'ColSpec', from 'ArrayRef[Str]', 
	via { RapidApp::TableSpec::ColSpec->new(colspecs => $_) };

has 'include_colspec', is => 'ro', isa => 'ColSpec', 
	required => 1, coerce => 1, trigger =>  sub { (shift)->_colspec_attr_init_trigger(@_) };
	
has 'updatable_colspec', is => 'ro', isa => 'ColSpec', 
	default => sub {[]}, coerce => 1, trigger =>  sub { (shift)->_colspec_attr_init_trigger(@_) };
	
has 'creatable_colspec', is => 'ro', isa => 'ColSpec', 
	default => sub {[]}, coerce => 1, trigger => sub { (shift)->_colspec_attr_init_trigger(@_) };
	
has 'always_fetch_colspec', is => 'ro', isa => 'ColSpec', 
	default => sub {[]}, coerce => 1, trigger => sub { (shift)->_colspec_attr_init_trigger(@_) };

sub _colspec_attr_init_trigger {
	my ($self,$ColSpec) = @_;
	my $sep = $self->relation_sep;
	/${sep}/ and die "Fatal: ColSpec '$_' is invalid because it contains the relation separater string '$sep'" for ($ColSpec->all_colspecs);
	
	$ColSpec->expand_colspecs(sub {
		$self->expand_relspec_wildcards(\@_)
	});
}



sub BUILD {}
after BUILD => sub {
	my $self = shift;
	
	$self->init_relspecs;
	
};

sub init_relspecs {
	my $self = shift;
	
	$self->multi_rel_columns_indx;
	
	$self->include_colspec->expand_colspecs(sub {
		$self->expand_relationship_columns(@_)
	});
	
	$self->include_colspec->expand_colspecs(sub {
		$self->expand_related_required_fetch_colspecs(@_)
	});
	
	
	foreach my $col ($self->no_column_colspec->base_colspec->all_colspecs) {
		$self->Cnf_columns->{$col} = {} unless ($self->Cnf_columns->{$col});
		%{$self->Cnf_columns->{$col}} = (
			%{$self->Cnf_columns->{$col}},
			no_column => \1, 
			no_multifilter => \1, 
			no_quick_search => \1
		);
		push @{$self->Cnf_columns_order},$col;
	}
	uniq($self->Cnf_columns_order);
	
	my @rels = $self->include_colspec->all_rel_order;
	
	$self->add_related_TableSpec($_) for (grep { $_ ne '' } @rels);
	
	$self->init_local_columns;
	
	foreach my $rel (@{$self->related_TableSpec_order}) {
		my $TableSpec = $self->related_TableSpec->{$rel};
		for my $name ($TableSpec->updated_column_order) {
			die "Column name conflict: $name is already defined (rel: $rel)" if ($self->has_column($name));
			$self->column_name_relationship_map->{$name} = $rel;
		}
	}
	
}


hashash 'column_data_alias';
has 'no_column_colspec', is => 'ro', isa => 'ColSpec', coerce => 1, default => sub {[]};
sub expand_relationship_columns {
	my $self = shift;
	my @columns = @_;
	my @expanded = ();
	
	my $rel_cols = $self->get_Cnf('relationship_column_names') || return;
	
	my @no_cols = ();
	foreach my $col (@columns) {
		push @expanded, $col;
		
		foreach my $relcol (@$rel_cols) {
			next unless (match_glob($col,$relcol));
		
			my @add = (
				$self->Cnf_columns->{$relcol}->{keyField},
				$relcol . '.' . $self->Cnf_columns->{$relcol}->{displayField},
				$relcol . '.' . $self->Cnf_columns->{$relcol}->{valueField}
			);
			push @expanded, @add;
			$self->apply_column_data_alias( $relcol => $self->Cnf_columns->{$relcol}->{keyField} );
			push @no_cols, grep { !$self->colspecs_to_colspec_test(\@columns,$_) } @add;
		}
	}
	$self->no_column_colspec->add_colspecs(@no_cols);
	
	return @expanded;
}

sub expand_related_required_fetch_colspecs {
	my $self = shift;
	my @columns = @_;
	my @expanded = ();
	
	my $local_cols = $self->get_Cnf_order('columns');

	my @no_cols = ();
	foreach my $spec (@columns) {
		push @expanded, $spec;
		
		foreach my $col (@$local_cols) {
			next unless (match_glob($spec,$col));
		
			my $req = $self->Cnf_columns->{$col}->{required_fetch_colspecs} or next;
			$req = [ $req ] unless (ref $req);
			
			my @req_columns = ();
			foreach my $spec (@$req) {
				my $colname = $spec;
				my $sep = $self->relation_sep;
				$colname =~ s/\./${sep}/g;
				push @req_columns, $self->column_prefix . $colname;
				#push @req_columns, $colname;
			}
			# This is then used later during the store read request in DbicLink2
			$self->Cnf_columns->{$col}->{required_fetch_columns} = [] 
				unless (defined $self->Cnf_columns->{$col}->{required_fetch_columns});
				
			push @{$self->Cnf_columns->{$col}->{required_fetch_columns}}, @req_columns;

			push @expanded, @$req;
			push @no_cols, grep { !$self->colspecs_to_colspec_test(\@columns,$_) } @$req;
		}
	}
	$self->no_column_colspec->add_colspecs(@no_cols);

	return @expanded;
}


sub base_colspec {
	my $self = shift;
	return $self->include_colspec->base_colspec->colspecs;
}

has 'Cnf_columns', is => 'ro', isa => 'HashRef', lazy => 1, default => sub {
	my $self = shift;
	return clone($self->get_Cnf('columns'));
};
has 'Cnf_columns_order', is => 'ro', isa => 'ArrayRef', lazy => 1, default => sub {
	my $self = shift;
	return clone($self->get_Cnf_order('columns'));
};

sub init_local_columns  {
	my $self = shift;
	
	my $class = $self->ResultClass;
	$class->set_primary_key( $class->columns ) unless ( $class->primary_columns > 0 );
	
	my @order = @{$self->Cnf_columns_order};
	@order = $self->filter_base_columns(@order);
	
	$self->add_db_column($_,$self->Cnf_columns->{$_}) for (@order);
};


sub add_db_column($@) {
	my $self = shift;
	my $name = shift;
	my %opt = (ref($_[0]) eq 'HASH') ? %{ $_[0] } : @_; # <-- arg as hash or hashref
	
	%opt = $self->get_relationship_column_cnf($name,\%opt) if($opt{relationship_info});
	
	$opt{name} = $self->column_prefix . $name;
	
	my $editable = $self->filter_updatable_columns($name,$opt{name});
	my $creatable = $self->filter_creatable_columns($name,$opt{name});
	
	$opt{allow_edit} = \0 unless ($editable);
	$opt{allow_add} = \0 unless ($creatable);

	unless ($editable or $creatable) {
		$opt{rel_combo_field_cnf} = $opt{editor} if($opt{editor});
		$opt{editor} = '' ;
	}
	
	return $self->add_columns(\%opt);
}



# Load and process config params from TableSpec_cnf in the ResultClass plus
# additional defaults:
hashash 'Cnf_order';
hashash 'Cnf', lazy => 1, default => sub {
	my $self = shift;
	my $class = $self->ResultClass;
	
	#my $cf;
	#if($class->can('TableSpec_cnf')) {
	#	$cf = $class->get_built_Cnf;
	#}
	#else {
	#	$cf = RapidApp::DBIC::Component::TableSpec::default_TableSpec_cnf($class);
	#}
	
	# Load the TableSpec Component on the Result Class if it isn't already:
	# (should this be done like this? this is a global change and could be an overreach)
	unless($class->can('TableSpec_cnf')) {
		$class->load_components('+RapidApp::DBIC::Component::TableSpec');
		$class->apply_TableSpec;
	}
	
	my $cf = $class->get_built_Cnf;
	
	%{$self->Cnf_order} = %{ $cf->{order} || {} };
	return $cf->{data} || {};
};







has 'relationship_column_configs', is => 'ro', isa => 'HashRef', lazy_build => 1; 
sub _build_relationship_column_configs {
	my $self = shift;
	
	my $class = $self->ResultClass;
	return {} unless ($class->can('TableSpec_cnf'));
	
	my %rel_cols_indx = map {$_=>1} @{$self->get_Cnf('relationship_column_names')};
	my %columns = $class->TableSpec_get_conf('columns');
	return { map { $_ => $columns{$_} } grep { $rel_cols_indx{$_} } keys %columns };
};



# colspecs that were added solely for the relationship columns
# get stored in 'added_relationship_column_relspecs' and are then
# hidden in DbicLink2.
# TODO: come up with a better way to handle this. It's ugly.
has 'added_relationship_column_relspecs' => ( 
	is => 'rw', isa => 'ArrayRef', default => sub {[]},
	#trigger => sub { my ($self,$val) = @_; uniq($val) }
);

=pod
sub expand_relspec_relationship_columns {
	my $self = shift;
	my $colspecs = shift;
	my $update = shift || 0;
	
	my $rel_configs = $self->relationship_column_configs;
	return @$colspecs unless (keys %$rel_configs > 0);
	
	my $match_data = {};
	my @rel_cols = $self->colspec_select_columns({
		colspecs => $colspecs,
		columns => [ keys %$rel_configs ],
		best_match_look_ahead => 1,
		match_data => $match_data
	});
	
	scream_color(RED.ON_BLUE,\@rel_cols);
	
	my %exist = map{$_=>1} @$colspecs;
	my $added = [];
	
	my @new_colspecs = @$colspecs;
	my $adj = 0;
	foreach my $rel (@rel_cols) {
		my @insert = ();
		push @insert, $rel . '.' . $rel_configs->{$rel}->{displayField} unless ($update);
		push @insert, $rel . '.' . $rel_configs->{$rel}->{valueField} unless ($update);
		push @insert, $rel_configs->{$rel}->{keyField};
		
		# Remove any expanded colspecs that were already defined (important to honor the user supplied column order)
		@insert = grep { !$exist{$_} } @insert;
		
		push @$added,@insert;
		unshift @insert, $rel unless ($exist{$rel});
		
		my $offset = $adj + $match_data->{$rel}->{index} + 1;
		
		splice(@new_colspecs,$offset,0,@insert);
		
		%exist = map{$_=>1} @new_colspecs;
		$adj += scalar @insert;
	}
	
	my @new_adds = grep { ! $self->colspecs_to_colspec_test($colspecs,$_) } @$added;
	
	@{$self->added_relationship_column_relspecs} = uniq(
		@{$self->added_relationship_column_relspecs},
		@new_adds
	);
	
	return @new_colspecs;
}
=cut

sub expand_relspec_wildcards {
	my $self = shift;
	my $colspec = shift;
	
	if(ref($colspec) eq 'ARRAY') {
		my @exp = ();
		push @exp, $self->expand_relspec_wildcards($_,@_) for (@$colspec);
		return @exp;
	}
	
	my $Source = shift || $self->ResultSource;
	my @ovr_macro_keywords = @_;
	
	# Exclude colspecs that start with #
	return () if ($colspec =~ /^\#/);
	
	my @parts = split(/\./,$colspec); 
	return ($colspec) unless (@parts > 1);
	
	my $clspec = pop @parts;
	my $relspec = join('.',@parts);
	
	# There is nothing to expand if the relspec doesn't contain wildcards:
	return ($colspec) unless ($relspec =~ /[\*\?\[\]\{]/);
	
	push @parts,$clspec;
	
	my $rel = shift @parts;
	my $pre; { $rel =~ s/^(\!)//; $pre = $1 ? $1 : ''; }
	
	my @rel_list = $Source->relationships;
	#scream($_) for (map { $Source->relationship_info($_) } @rel_list);
	
	my @macro_keywords = @ovr_macro_keywords;
	my $macro; { $rel =~ s/^\{([\?\:a-zA-Z0-9]+)\}//; $macro = $1; }
	push @macro_keywords, split(/\:/,$macro) if ($macro);
	my %macros = map { $_ => 1 } @macro_keywords;
	
	my @accessors = grep { $_ eq 'single' or $_ eq 'multi' or $_ eq 'filter'} @macro_keywords;
	if (@accessors > 0) {
		my %ac = map { $_ => 1 } @accessors;
		@rel_list = grep { $ac{ $Source->relationship_info($_)->{attrs}->{accessor} } } @rel_list;
	}

	my @matching_rels = grep { match_glob($rel,$_) } @rel_list;
	die 'Invalid ColSpec: "' . $rel . '" doesn\'t match any relationships of ' . 
		$Source->schema->class($Source->source_name) unless ($macros{'?'} or @matching_rels > 0);
	
	my @expanded = ();
	foreach my $rel_name (@matching_rels) {
		my @suffix = $self->expand_relspec_wildcards(join('.',@parts),$Source->related_source($rel_name),@ovr_macro_keywords);
		push @expanded, $pre . $rel_name . '.' . $_ for (@suffix);
	}

	return (@expanded);
}


has 'relation_sep' => ( is => 'ro', isa => 'Str', required => 1 );
has 'relspec_prefix' => ( is => 'ro', isa => 'Str', default => '' );
# needed_join is the relspec_prefix in DBIC 'join' attr format
has 'needed_join' => ( is => 'ro', isa => 'HashRef', lazy => 1, default => sub {
	my $self = shift;
	return {} if ($self->relspec_prefix eq '');
	return $self->chain_to_hash(split(/\./,$self->relspec_prefix));
});
has 'column_prefix' => ( is => 'ro', isa => 'Str', lazy => 1, default => sub {
	my $self = shift;
	return '' if ($self->relspec_prefix eq '');
	my $col_pre = $self->relspec_prefix;
	my $sep = $self->relation_sep;
	$col_pre =~ s/\./${sep}/g;
	return $col_pre . $self->relation_sep;
});




around 'get_column' => sub {
	my $orig = shift;
	my $self = shift;
	my $name = shift;
	
	my $rel = $self->column_name_relationship_map->{$name};
	if ($rel) {
		my $TableSpec = $self->related_TableSpec->{$rel};
		return $TableSpec->get_column($name) if ($TableSpec);
	}
	
	return $self->$orig($name);
};


# accepts a list of column names and returns the names that match the base colspec
sub filter_base_columns {
	my $self = shift;
	my @columns = @_;
	
	# Why has this come up?
	# filter out columns with invalid characters (*):
	@columns = grep { /^[A-Za-z0-9\-\_\.]+$/ } @columns;
	
	return $self->colspec_select_columns({
		colspecs => $self->base_colspec,
		columns => \@columns,
	});
}

sub filter_include_columns {
	my $self = shift;
	my @columns = @_;
	
	my @inc_cols = $self->colspec_select_columns({
		colspecs => $self->include_colspec->colspecs,
		columns => \@columns,
	});
	
	my @rel_cols = $self->colspec_select_columns({
		colspecs => $self->added_relationship_column_relspecs,
		columns => \@columns,
	});
	
	my %allowed = map {$_=>1} @inc_cols,@rel_cols;
	return grep { $allowed{$_} } @columns;
}

# accepts a list of column names and returns the names that match updatable_colspec
sub filter_updatable_columns {
	my $self = shift;
	my @columns = @_;
	
	#exclude all multi relationship columns
	@columns = grep {!$self->multi_rel_columns_indx->{$self->column_prefix . $_}} @columns;
	
	return $self->colspec_select_columns({
		colspecs => $self->updatable_colspec->colspecs,
		columns => \@columns,
	});
}



# accepts a list of column names and returns the names that match creatable_colspec
sub filter_creatable_columns {
	my $self = shift;
	my @columns = @_;
	
	#exclude all multi relationship columns
	@columns = grep {!$self->multi_rel_columns_indx->{$_}} @columns;

	# First filter by include_colspec:
	@columns = $self->filter_include_columns(@columns);
	
	return $self->colspec_select_columns({
		colspecs => $self->creatable_colspec->colspecs,
		columns => \@columns,
	});
}



# Tests whether or not the colspec in the second arg matches the colspec of the first arg
# The second arg colspec does NOT expand wildcards, it has to be a specific rel/col string
sub colspec_to_colspec_test {
	my $self = shift;
	my $colspec = shift;
	my $test_spec = shift;
	
	$colspec =~ s/^(\!)//;
	my $x = $1 ? -1 : 1;
	
	my @parts = split(/\./,$colspec);
	my @test_parts = split(/\./,$test_spec);
	return undef unless(scalar @parts == scalar @test_parts);
	
	foreach my $part (@parts) {
		my $test = shift @test_parts or return undef;
		return undef unless (match_glob($part,$test));
	}
	
	return $x;
}

sub colspecs_to_colspec_test {
	my $self = shift;
	my $colspecs = shift;
	my $test_spec = shift;
	
	$colspecs = [ $colspecs ] unless (ref($colspecs) eq 'ARRAY');
	
	my $match = 0;
	foreach my $colspec (@$colspecs) {
		my $result = $self->colspec_to_colspec_test($colspec,$test_spec) || next;
		return 0 if ($result < 0);
		$match = 1 if ($result > 0);
	}
	
	return $match;
}


#around colspec_test => &func_debug_around();

# TODO:
# abstract this logic (much of which is redundant) into its own proper class 
# (merge with Mike's class)
# Tests whether or not the supplied column name matches the supplied colspec.
# Returns 1 for positive match, 0 for negative match (! prefix) and undef for no match
sub colspec_test($$){
	my $self = shift;
	my $full_colspec = shift || die "full_colspec is required";
	my $col = shift || die "col is required";
	
	# @other_colspecs - optional.
	# If supplied, the column will also be tested against the colspecs in @other_colspecs,
	# and no match will be returned unless this colspec matches *and* has the lowest
	# edit distance of any other matches. This logic is designed so that remaining
	# colspecs to be tested can be considered, and only the best match will win. This
	# is meaningful when determining things like order based on a list of colspecs. This 
	# doesn't serve any purpose when doing a straight bool up/down test
	# tested with 
	my @other_colspecs = @_;
	
	my $full_colspec_orig = $full_colspec;
	$full_colspec =~ s/^(\!)//;
	my $x = $1 ? -1 : 1;
	my $match_return = $1 ? 0 : 1;
	
	my @parts = split(/\./,$full_colspec); 
	my $colspec = pop @parts;
	my $relspec = join('.',@parts);
	
	my $sep = $self->relation_sep;
	my $prefix = $relspec;
	$prefix =~ s/\./${sep}/g;
	
	@parts = split(/${sep}/,$col); 
	my $test_col = pop @parts;
	my $test_prefix = join($sep,@parts);
	
	# no match:
	return undef unless ($prefix eq $test_prefix);
	
	# match (return 1 or 0):
	if (match_glob($colspec,$test_col)) {
		# Calculate WagnerFischer edit distance
		my $distance = distance($colspec,$test_col);
		
		# multiply my $x to set the sign, then flip so bigger numbers 
		# mean better match instead of the reverse
		my $value = $x * (1000 - $distance); # <-- flip 
		
		foreach my $spec (@other_colspecs) {
			my $other_val = $self->colspec_test($spec,$col) or next;

			# A colspec in @other_colspecs is a better match than us, so we defer:
			return undef if (abs $other_val > abs $value);
		}
		return $value;
	};
	
	# no match:
	return undef;
}

# returns a list of loaded column names that match the supplied colspec set
sub get_colspec_column_names {
	my $self = shift;
	my @colspecs = @_;
	@colspecs = @{$_[0]} if (ref($_[0]) eq 'ARRAY');
	
	# support for passing colspecs with relspec wildcards:
	@colspecs = $self->expand_relspec_wildcards(\@colspecs,undef,'?');
	
	return $self->colspec_select_columns({
		colspecs => \@colspecs,
		columns => [ $self->updated_column_order ]
	});
}

# returns a list of all loaded column names except those that match the supplied colspec set
sub get_except_colspec_column_names {
	my $self = shift;
	
	my %colmap = map { $_ => 1} $self->get_colspec_column_names(@_);
	return grep { ! $colmap{$_} } $self->updated_column_order;
}

# Tests if the supplied colspec set matches all of the supplied columns
sub colspec_matches_columns {
	my $self = shift;
	my $colspecs = shift;
	my @columns = @_;
	my @matches = $self->colspec_select_columns({
		colspecs => $colspecs,
		columns => \@columns
	});
	return 1 if (@columns == @matches);
	return 0;
}

# Returns a sublist of the supplied columns that match the supplied colspec set.
# The colspec set is considered as a whole, with each column name tested against
# the entire compiled set, which can contain both positive and negative (!) colspecs,
# with the most recent match taking precidence.
sub colspec_select_columns {
	my $self = shift;
	my %opt = (ref($_[0]) eq 'HASH') ? %{ $_[0] } : @_; # <-- arg as hash or hashref
	
	my $colspecs = $opt{colspecs} or die "colspec_select_columns(): expected 'colspecs'";
	my $columns = $opt{columns} or die "colspec_select_columns(): expected 'columns'";
	
	# if best_match_look_ahead is true, the current remaining colspecs will be passed
	# to each invocation of colspec_test which will cause it to only return a match
	# when testing the *closest* (according to WagnerFischer edit distance) colspec
	# of the set to the column. This prevents 
	my $best_match = $opt{best_match_look_ahead};
	
	$colspecs = [ $colspecs ] unless (ref $colspecs);
	$columns = [ $columns ] unless (ref $columns);
	
	$opt{match_data} = {} unless ($opt{match_data});
	
	my %match = map { $_ => 0 } @$columns;
	my @order = ();
	my $i = 0;
	for my $spec (@$colspecs) {
		my @remaining = @$colspecs[++$i .. $#$colspecs];
		for my $col (@$columns) {

			my @arg = ($spec,$col);
			push @arg, @remaining if ($best_match); # <-- push the rest of the colspecs after the current for index
			
			my $result = $self->colspec_test(@arg) or next;
			push @order, $col if ($result > 0);
			$match{$col} = $result;
			$opt{match_data}->{$col} = {
				index => $i - 1,
				colspec => $spec
			} unless ($opt{match_data}->{$col});
		}
	}
	
	return uniq(grep { $match{$_} > 0 } @order);
}

# Applies the original column order defined in the table Schema:
sub apply_natural_column_order {
	my $self = shift;
	my $class = $self->ResultClass;
	$self->reorder_by_colspec_list(
		$class->columns,
		$class->relationships,
		@{ $self->include_colspec->colspecs || [] }
	);
}

# reorders the entire column list according to a list of colspecs. This is called
# by DbicLink2 to use the same include_colspec to also define the column order
sub reorder_by_colspec_list {
	my $self = shift;
	my @colspecs = @_;
	@colspecs = @{$_[0]} if (ref($_[0]) eq 'ARRAY');
	
	# Check the supplied colspecs for any that don't contain '.'
	# if there are none, and all of them contain a '.', then we
	# need to add the base colspec '*'
	my $need_base = 1;
	! /\./ and $need_base = 0 for (@colspecs);
	unshift @colspecs, '*' if ($need_base);
	
	my @new_order = $self->colspec_select_columns({
		colspecs => \@colspecs,
		columns => [ $self->updated_column_order ],
		best_match_look_ahead => 1
	});
	
	# Add all the current columns to the end of the new list in case any
	# got missed. (this prevents the chance of this operation dropping any 
	# of the existing columns, dupes are filtered out below):
	push @new_order, $self->updated_column_order;
	
	my %seen = ();
	@{$self->column_order} = grep { !$seen{$_}++ } @new_order;
	return $self->updated_column_order; #<-- for good measure
}

sub relation_colspecs {
	my $self = shift;
	return $self->include_colspec->subspec;
}

sub relation_order {
	my $self = shift;
	return $self->include_colspec->rel_order;
}


sub new_TableSpec {
	my $self = shift;
	return RapidApp::TableSpec::DbicTableSpec->new(@_);
	#return RapidApp::TableSpec->with_traits('RapidApp::TableSpec::Role::DBIC')->new(@_);
}


=pod
sub related_TableSpec {
	my $self = shift;
	my $rel = shift;
	my %opt = (ref($_[0]) eq 'HASH') ? %{ $_[0] } : @_; # <-- arg as hash or hashref
	
	my $info = $self->ResultClass->relationship_info($rel) or die "Relationship '$rel' not found.";
	my $class = $info->{class};
	
	# Manually load and initialize the TableSpec component if it's missing from the
	# related result class:
	#unless($class->can('TableSpec')) {
	#	$class->load_components('+RapidApp::DBIC::Component::TableSpec');
	#	$class->apply_TableSpec(%opt);
	#}
	
	my $relspec_prefix = $self->relspec_prefix;
	$relspec_prefix .= '.' if ($relspec_prefix and $relspec_prefix ne '');
	$relspec_prefix .= $rel;
	
	my $TableSpec = $self->new_TableSpec(
		name => $class->table,
		ResultClass => $class,
		relation_sep => $self->relation_sep,
		relspec_prefix => $relspec_prefix,
		%opt
	);
	
	return $TableSpec;
}
=cut

=pod
# Recursively flattens/merges in columns from related TableSpecs (matching include_colspec)
# into a new TableSpec object and returns it:
sub flattened_TableSpec {
	my $self = shift;
	
	#return $self;
	
	my $Flattened = $self->new_TableSpec(
		name => $self->name,
		ResultClass => $self->ResultClass,
		relation_sep => $self->relation_sep,
		include_colspec => $self->include_colspec->colspecs,
		relspec_prefix => $self->relspec_prefix
	);
	
	$Flattened->add_all_related_TableSpecs_recursive;
	
	#scream_color(CYAN,$Flattened->column_name_relationship_map);
	
	return $Flattened;
}
=cut

# Returns the TableSpec associated with the supplied column name
sub column_TableSpec {
	my $self = shift;
	my $column = shift;

	my $rel = $self->column_name_relationship_map->{$column};
	unless ($rel) {
		my %ndx = map {$_=>1} 
			keys %{$self->columns}, 
			@{$self->added_relationship_column_relspecs};
			
		#scream($column,\%ndx);
			
		return $self if ($ndx{$column});
		return undef;
	}
	
	return $self->related_TableSpec->{$rel}->column_TableSpec($column);
}

# Accepts a list of columns and divides them into a hash of arrays
# with keys of the relspec to which each set of columns belongs, with
# both the localized and original column names in a hashref.
# This logic is used in update in DbicLink2
sub columns_to_relspec_map {
	my $self = shift;
	my @columns = @_;
	my $map = {};
	
	foreach my $col (@columns) {
		my $TableSpec = $self->column_TableSpec($col) or next;
		my $pre = $TableSpec->column_prefix;
		my $local_name = $col;
		$local_name =~ s/^${pre}//;
		push @{$map->{$TableSpec->relspec_prefix}}, {
			local_colname => $local_name,
			orig_colname => $col
		};
	}
	
	return $map;
}


sub columns_to_reltree {
	my $self = shift;
	my @columns = @_;
	my %map = (''=>[]);
	foreach my $col (@columns) {
		my $rel = $self->column_name_relationship_map->{$col} || '';
		push @{$map{$rel}}, $col;
	}
	
	my %tree = map {$_=>1} @{delete $map{''}};
	#$tree{'@' . $_} = $self->columns_to_reltree(@{$map{$_}}) for (keys %map);
	
	foreach my $rel (keys %map) {
		my $TableSpec = $self->related_TableSpec->{$rel} or die "Failed to find related TableSpec $rel";
		$tree{'@' . $rel} = $TableSpec->columns_to_reltree(@{$map{$rel}});
	}

	return \%tree;
}


sub walk_columns_deep {
	my $self = shift;
	my $code = shift;
	my @columns = @_;
	
	my $recurse = 0;
	$recurse = 1 if((caller(1))[3] eq __PACKAGE__ . '::walk_columns_deep');
	local $_{return} = undef unless ($recurse);
	local $_{rel} = undef unless ($recurse);
	local $_{depth} = 0 unless ($recurse);

	
	my %map = (''=>[]);
	foreach my $col (@columns) {
		my $rel = $self->column_name_relationship_map->{$col} || '';
		push @{$map{$rel}}, $col;
	}
	
=pod
	local $_{depth} = $_{depth}; $_{depth}++;
	local $_{return};
	my $tree = $self->columns_to_reltree(@columns);
	foreach my $rel (grep { /^\@/ } keys %$tree) {
		my @cols = keys %{$tree->{$rel}};
		$rel =~ s/^\@//;
		
		my $TableSpec = $self->related_TableSpec->{$rel} or die "Failed to find related TableSpec $rel";
		local $_{rel} = $rel;
		$_{return} = $TableSpec->walk_columns_deep($code,@cols)
	}
	
	my @local_cols = grep { !/^\@/ } keys %$tree;
	
	my $pre = $self->column_prefix;
	my %name_map = map { my $name = $_; $name =~ s/^${pre}//; $name => $_ } @local_cols;
	local $_{name_map} = \%name_map;
	
	return $code->($self,@local_cols);
=cut
	
	
	
	
	
	my @local_cols = @{delete $map{''}};
	
	my $pre = $self->column_prefix;
	my %name_map = map { my $name = $_; $name =~ s/^${pre}//; $name => $_ } @local_cols;
	local $_{name_map} = \%name_map;
	local $_{return} = $code->($self,@local_cols);
	local $_{depth} = $_{depth}; $_{depth}++;
	foreach my $rel (keys %map) {
		my $TableSpec = $self->related_TableSpec->{$rel} or die "Failed to find related TableSpec $rel";
		local $_{last_rel} = $_{rel};
		local $_{rel} = $rel;
		$TableSpec->walk_columns_deep($code,@{$map{$rel}});
	}
	
	
	

	
	
=pod
	my @local_cols = @{delete $map{''}};
	
	local $_{depth} = $_{depth}; $_{depth}++;
	local $_{return};
	foreach my $rel (keys %map) {
		my $TableSpec = $self->related_TableSpec->{$rel} or die "Failed to find related TableSpec $rel";
		local $_{rel} = $rel;
		$_{return} = $TableSpec->walk_columns_deep($code,@{$map{$rel}});
	}
	
	my $pre = $self->column_prefix;
	my %name_map = map { my $name = $_; $name =~ s/^${pre}//; $name => $_ } @local_cols;
	local $_{name_map} = \%name_map;
	
	return $code->($self,@local_cols);
=cut
	
}











# Accepts a DBIC Row object and a relspec, and returns the related DBIC
# Row object associated with that relspec
sub related_Row_from_relspec {
	my $self = shift;
	my $Row = shift || return undef;
	my $relspec = shift || '';
	
	my @parts = split(/\./,$relspec);
	my $rel = shift @parts || return $Row;
	return $Row if ($rel eq '');
	
	my $info = $Row->result_source->relationship_info($rel) or die "Relationship $rel not found";
	
	# Skip unless its a single (not multi) relationship:
	return undef unless ($info->{attrs}->{accessor} eq 'single' || $info->{attrs}->{accessor} eq 'filter');
	
	my $Related = $Row->$rel;
	return $self->related_Row_from_relspec($Related,join('.',@parts));
}

=pod
sub add_all_related_TableSpecs_recursive {
	my $self = shift;
	
	foreach my $rel (@{$self->relation_order}) {
		next if ($rel eq '');
		my $TableSpec = $self->addIf_related_TableSpec($rel);
		#my $TableSpec = $self->add_related_TableSpec( $rel, {
			#include_colspec => $self->relation_colspecs->{$rel}
		#});
		
		$TableSpec->add_all_related_TableSpecs_recursive;
	}
	
	foreach my $rel (@{$self->related_TableSpec_order}) {
		my $TableSpec = $self->related_TableSpec->{$rel};
		for my $name ($TableSpec->column_names_ordered) {
			#die "Column name conflict: $name is already defined (rel: $rel)" if ($self->has_column($name));
			$self->column_name_relationship_map->{$name} = $rel;
		}
	}
	
	return $self;
}
=cut

# Is this func still used??
# Like column_order but only considers columns in the local TableSpec object
# (i.e. not in related TableSpecs)
sub local_column_names {
	my $self = shift;
	my %seen = ();
	return grep { !$seen{$_}++ && exists $self->columns->{$_} } @{$self->column_order}, keys %{$self->columns};
}


has 'column_name_relationship_map' => ( is => 'ro', isa => 'HashRef[Str]', default => sub {{}} );
has 'related_TableSpec' => ( is => 'ro', isa => 'HashRef[RapidApp::TableSpec]', default => sub {{}} );
has 'related_TableSpec_order' => ( is => 'ro', isa => 'ArrayRef[Str]', default => sub {[]} );
sub add_related_TableSpec {
	my $self = shift;
	my $rel = shift;
	my %opt = (ref($_[0]) eq 'HASH') ? %{ $_[0] } : @_; # <-- arg as hash or hashref
	
	die "There is already a related TableSpec associated with the '$rel' relationship - " . Dumper(caller_data_brief(20,'^RapidApp')) if (
		defined $self->related_TableSpec->{$rel}
	);
	
	my $info = $self->ResultClass->relationship_info($rel) or die "Relationship '$rel' not found.";
	my $relclass = $info->{class};

	my $relspec_prefix = $self->relspec_prefix;
	$relspec_prefix .= '.' if ($relspec_prefix and $relspec_prefix ne '');
	$relspec_prefix .= $rel;
	
	my %params = (
		name => $relclass->table,
		ResultClass => $relclass,
		schema => $self->schema, #<-- need both ResultClass and schema to identify ResultSource
		relation_sep => $self->relation_sep,
		relspec_prefix => $relspec_prefix,
		include_colspec => $self->include_colspec->get_subspec($rel),
	);
	
	$params{updatable_colspec} = $self->updatable_colspec->get_subspec($rel) || []; 
	$params{creatable_colspec} = $self->creatable_colspec->get_subspec($rel) || [];
	$params{no_column_colspec} = $self->no_column_colspec->get_subspec($rel) || [];
		
	%params = ( %params, %opt );
	
	my $class = $self->ResultClass;
	if($class->can('TableSpec_get_conf') and $class->TableSpec_has_conf('related_column_property_transforms')) {
		my $rel_transforms = $class->TableSpec_cnf->{'related_column_property_transforms'}->{data};
		$params{column_property_transforms} = $rel_transforms->{$rel} if ($rel_transforms->{$rel});
		
		# -- Hard coded default 'header' transform (2011-12-25 by HV)
		# If there isn't already a configured column_property_transform for 'header'
		# add one that appends the relspec prefix. This is currently built-in because
		# it is such a ubiquotous need and it is just more intuitive than creating yet
		# other param that will always be 'on'. I am sure there are cases where this is
		# not desired, but until I run across them it will just be hard coded:
		unless($params{column_property_transforms}->{header}) {
			$params{column_property_transforms}->{header} = sub { $_ ? "$_ ($relspec_prefix)" : $_ };
		}
		# --
		
	}
	
	my $TableSpec = $self->new_TableSpec(%params) or die "Failed to create related TableSpec";
	
	$self->related_TableSpec->{$rel} = $TableSpec;
	push @{$self->related_TableSpec_order}, $rel;
	
	return $TableSpec;
}

sub addIf_related_TableSpec {
	my $self = shift;
	my ($rel) = @_;
	
	my $TableSpec = $self->related_TableSpec->{$rel} || $self->add_related_TableSpec(@_);
	return $TableSpec;
}

around 'get_column' => \&_has_get_column_modifier;
around 'has_column' => \&_has_get_column_modifier;
sub _has_get_column_modifier {
	my $orig = shift;
	my $self = shift;
	my $name = $_[0];
	
	my $rel = $self->column_name_relationship_map->{$name};
	my $obj = $self;
	$obj = $self->related_TableSpec->{$rel} if (defined $rel);
	
	return $obj->$orig(@_);
}


around 'updated_column_order' => sub {
	my $orig = shift;
	my $self = shift;
	
	my %seen = ();
	# Start with and preserve the column order in this object:
	my @order = grep { !$seen{$_}++ } @{$self->column_order};
	
	# Pull in any unseen columns from the superclass (should normally be none, except when initializing)
	push @order, grep { !$seen{$_}++ } $self->$orig(@_);
	
	my @rels = ();
	push @rels, $self->related_TableSpec->{$_}->updated_column_order for (@{$self->related_TableSpec_order});
	
	# Preserve the existing order, adding only new/unseen related columns:
	push @order, grep { !$seen{$_}++ } @rels;
	
	@{$self->column_order} = @order;
	return @{$self->column_order};
};




hashash 'multi_rel_columns_indx', lazy => 1, default => sub {
	my $self = shift;
	my $list = $self->get_Cnf('multi_relationship_column_names') || [];
		
	my %indx = map { $_ => 
		{ %{$self->ResultClass->parse_relationship_cond(
				$self->ResultSource->relationship_info($_)->{cond}
			)}, 
			info => $self->ResultSource->relationship_info($_),
			rev_relname => (keys %{$self->ResultSource->reverse_relationship_info($_)})[0],
			relname => $_
		} 
	} @$list;
	
	# Add in any defined functions (this all needs to be cleaned up/refactored):
	$self->Cnf_columns->{$_}->{function} and $indx{$_}->{function} = $self->Cnf_columns->{$_}->{function} 
		for (keys %indx);
		
	#scream_color(GREEN,'loading');
	#scream_color(GREEN.BOLD,$_,$self->Cnf_columns->{$_}) for (keys %indx);
	
	#scream(\%indx);

	return \%indx;
};


=head2 $tableSpec->resolve_dbic_colname( $fieldName, \%merge_join, $get_render_col )

Returns a value which can be added to DBIC's ->{attr}{select} in order to select the column.

$fieldName is the ExtJS column name to resolve.
%merge_join is a in/out parameter which collects the total required joins
	for this query.
$get_render_col is a boolean of whether this function should instead return
	the DBIC name of the render column.

=cut
sub resolve_dbic_colname {
	my ($self, $name, $merge_join, $get_render_col)= @_;
	$get_render_col ||= 0;
	
	my ($rel,$col,$join,$cond_data) = $self->resolve_dbic_rel_alias_by_column_name($name,$get_render_col);
	
	%$merge_join = %{ merge($merge_join,$join) }
		if ($merge_join and $join);

	if (!defined $cond_data) {
		# it is a simple column
		return "$rel.$col";
	} else {
		# If cond_data is defined, the relation is a multi-relation, and we need to either
		#  join and group-by, or run a sub-query.  If join-and-group-by happens twice, it
		#  breaks COUNT() (because the number of joined rows gets multiplied) so by default
		#  we only use sub-queries.  In fact, join and group-by has a lot of problems on
		#  MySQL and we should probably never use it.
		
		# Support for a custom aggregate function
		if (ref($cond_data->{function}) eq 'CODE') {
			# TODO: we should use hash-style parameters
			return $cond_data->{function}->($self,$rel,$col,$join,$cond_data,$name);
		}
		else {
			# If not customized, we return a sub-query which counts the related items
			my $source = $self->schema->source($cond_data->{info}{source});
			my $rel_rs= $source->resultset_class->new($source, { alias => 'inner' })->search_rs(
				{ "inner.$cond_data->{foreign}" => \[" = $rel.$cond_data->{self}"] },
				{ %{$cond_data->{info}{attrs} || {}} }
			);
			return { '' => $rel_rs->count_rs->as_query, -as => $name };
		}
	}
}


sub resolve_dbic_rel_alias_by_column_name  {
	my $self = shift;
	my $name = shift;
	my $get_render_col = shift || 0; 
	
	# -- applies only to relationship columns and currently only used for sort:
	#  UPDATE: now also used for column_summaries
	if($get_render_col) {
		my $render_col = $self->relationship_column_render_column_map->{$name};
		$name = $render_col if ($render_col);
	}
	# --
	
	my $rel = $self->column_name_relationship_map->{$name};
	unless ($rel) {
		
		my $join = $self->needed_join;
		my $pre = $self->column_prefix;
		$name =~ s/^${pre}//;
		
		# Special case for "multi" relationships... they return the related row count
		my $cond_data = $self->multi_rel_columns_indx->{$name};
		if ($cond_data) {
			# Need to manually build the join to include the rel column:
			# Update: we no longer add this to the join, because we use a sub-select
			#   to query the multi-relation, and don't want a product-style join in
			#   the top-level query.
			#my $rel_pre = $self->relspec_prefix;
			#$rel_pre .= '.' unless ($rel_pre eq '');
			#$rel_pre .= $name;
			#$join = $self->chain_to_hash(split(/\./,$rel_pre));
			
			$join = $self->chain_to_hash($self->relspec_prefix)
				if length $self->relspec_prefix;
			
			return ('me',$name,$join,$cond_data)
		}
	
		return ('me',$name,$join);
	}
	
	my $TableSpec = $self->related_TableSpec->{$rel};
	my ($alias,$dbname,$join,$cond_data) = $TableSpec->resolve_dbic_rel_alias_by_column_name($name,$get_render_col);
	$alias = $rel if ($alias eq 'me');
	return ($alias,$dbname,$join,$cond_data);
}


# This exists specifically to handle relationship columns:
has 'custom_dbic_rel_aliases' => ( is => 'ro', isa => 'HashRef', default => sub {{}} );

sub chain_to_hash {
	my $self = shift;
	my @chain = @_;
	
	my $hash = {};

	my @evals = ();
	foreach my $item (@chain) {
		unshift @evals, '$hash->{\'' . join('\'}->{\'',@chain) . '\'} = {}';
		pop @chain;
	}
	eval $_ for (@evals);
	
	return $hash;
}


hashash 'relationship_column_render_column_map';
sub get_relationship_column_cnf {
	my $self = shift;
	my $rel = shift;
	my %opt = (ref($_[0]) eq 'HASH') ? %{ $_[0] } : @_; # <-- arg as hash or hashref
	
	return $self->get_multi_relationship_column_cnf($rel,\%opt) if ($self->multi_rel_columns_indx->{$rel});
	
	my $conf = \%opt;
	my $info = $conf->{relationship_info} or die "relationship_info is required";
	
	my $err_info = "rel col: " . $self->ResultSource->from . ".$rel - " . Dumper($conf);
	
	die "displayField is required ($err_info)" unless (defined $conf->{displayField});
	die "valueField is required ($err_info)" unless (defined $conf->{valueField});
	die "keyField is required ($err_info)" unless (defined $conf->{keyField});
	
	my $Source = $self->ResultSource->related_source($rel);
	

	my $render_col = $self->column_prefix . $rel . $self->relation_sep . $conf->{displayField};
	my $key_col = $self->column_prefix . $rel . $self->relation_sep . $conf->{valueField};
	my $upd_key_col = $self->column_prefix . $conf->{keyField};
	
	# -- Assume the the column profiles of the display column:
	my $relTS = $self->related_TableSpec->{$rel};
	if($relTS) {
		my $relconf = $relTS->Cnf_columns->{$conf->{displayField}};
		$conf->{profiles} = $relconf->{profiles} || $conf->{profiles};
	}
	# --
	
	my $colname = $self->column_prefix . $rel;
	
	# -- 
	# Store the render column that is associated with this relationship column
	# Currently we use this for sorting on relationship columns:
	$self->relationship_column_render_column_map->{$colname} = $render_col;
	# Also store in the column itself - added for excel export - is this redundant to above? probably. FIXME
	$conf->{render_column} = $render_col; 
	# --

	my $rows;
	my $read_raw_munger = sub {
		$rows = (shift)->{rows};
		$rows = [ $rows ] unless (ref($rows) eq 'ARRAY');
		foreach my $row (@$rows) {
			$row->{$colname} = $row->{$upd_key_col} if (exists $row->{$upd_key_col});
		}
	};
	
	my $required_fetch_columns = [ 
		$render_col,
		$key_col,
		$upd_key_col
	];
	
	$conf->{renderer} = 'Ext.ux.showNull' unless ($conf->{renderer});
	
	# ---
	# We need to set 'no_fetch' to prevent DbicLink2 trying to fetch the rel name
	# as a column -- EXCEPT if the rel name is ALSO a column name:
	my $is_also_local_col = $self->ResultSource->has_column($rel) ? 1 : 0;
	$conf->{no_fetch} = 1 unless ($is_also_local_col);
	# ---
	
	$conf = { %$conf, 
		
		#no_quick_search => \1,
		#no_multifilter => \1,
		
		query_id_use_column => $upd_key_col,
		query_search_use_column => $render_col,
		
		#required_fetch_colspecs => [],
		
		required_fetch_columns => $required_fetch_columns,
		
		read_raw_munger => RapidApp::Handler->new( code => $read_raw_munger ),
		#update_munger => RapidApp::Handler->new( code => $update_munger ),
		
		renderer => jsfunc(
			'function(value, metaData, record, rowIndex, colIndex, store) {' .
				'return Ext.ux.RapidApp.DbicSingleRelationshipColumnRender({' .
					'value:value,metaData:metaData,record:record,rowIndex:rowIndex,colIndex:colIndex,store:store,' .
					'render_col: "' . $render_col . '",' .
					'key_col: "' . $key_col . '",' .
					'upd_key_col: "' . $upd_key_col . '"' .
					( $conf->{open_url} ? ",open_url: '" . $conf->{open_url} . "'" : '' ) .
				'});' .
			'}', $conf->{renderer}
		)
	};
	
	
	############# ---
	switch ($conf->{auto_editor_type}) {
	
		$conf->{editor} = $conf->{editor} || {};
		$conf->{auto_editor_params} = $conf->{auto_editor_params} || {};
		
		# Set allowBlank according to the db schema of the key column. This is handled
		# automatically in normal columns in the profile stuff, but has to be done special
		# for relationship columns:
		unless(exists $conf->{editor}->{allowBlank}) {
			my $cinfo = $self->ResultSource->column_info($conf->{keyField});
			$conf->{editor}->{allowBlank} = \0 if($cinfo && $cinfo->{is_nullable} == 0);
		}
	
		$conf->{auto_editor_params} = $conf->{auto_editor_params} || {};
	
		case 'combo' {
		
			my $module_name = 'combo_' . $self->ResultClass->table . '_' . $colname;
			my $Module = $self->get_or_create_rapidapp_module( $module_name,
				class	=> 'RapidApp::DbicAppCombo2',
				params	=> {
					valueField		=> $conf->{valueField},
					displayField	=> $conf->{displayField},
					name				=> $colname,
					ResultSet		=> $Source->resultset,
					record_pk		=> $conf->{valueField},
					# Optional custom ResultSet params applied to the dropdown query
					RS_condition	=> $conf->{RS_condition} ? $conf->{RS_condition} : {},
					RS_attr			=> $conf->{RS_attr} ? $conf->{RS_attr} : {},
					%{ $conf->{auto_editor_params} },
				}
			);
			
			if($conf->{editor}) {
				if($conf->{editor}->{listeners}) {
					my $listeners = delete $conf->{editor}->{listeners};
					$Module->add_listener( $_ => $listeners->{$_} ) for (keys %$listeners);
				}
				$Module->apply_extconfig(%{$conf->{editor}}) if (keys %{$conf->{editor}} > 0);
			}
			
			$conf->{editor} =  $Module->content;
		}
		
		case 'grid' {
			
			die "display_columns is required with 'grid' auto_editor_type" 
				unless (defined $conf->{display_columns});
			
			my $custOnBUILD = $conf->{auto_editor_params}->{onBUILD} || sub{};
			my $onBUILD = sub {
				my $self = shift;		
				$self->apply_to_all_columns( hidden => \1 );
				$self->apply_columns_list($conf->{display_columns},{ hidden => \0 });
				return $custOnBUILD->($self);
			};
			$conf->{auto_editor_params}->{onBUILD} = $onBUILD;
			
			my $grid_module_name = 'grid_' . $self->ResultClass->table . '_' . $colname;
			my $GridModule = $self->get_or_create_rapidapp_module( $grid_module_name,
				class	=> 'RapidApp::DbicAppGrid3',
				params	=> {
					ResultSource => $Source,
					include_colspec => [ '*', '{?:single}*.*' ],
					#include_colspec => [ ($conf->{valueField},$conf->{displayField},@{$conf->{display_columns}}) ],
					title => '',
					%{ $conf->{auto_editor_params} }
				}
			);
			
			
			$conf->{editor} = { 

				# These can be overridden
				header			=> $conf->{header},
				win_title		=> 'Select ' . $conf->{header},
				win_height		=> 450,
				win_width		=> 650,
				
				%{$conf->{editor}},
				
				# These can't be overridden
				name		=> $colname,
				xtype => 'datastore-app-field',
				valueField		=> $conf->{valueField},
				displayField	=> $conf->{displayField},
				load_url	=> $GridModule->base_url,
				
			};
		}
		
		case 'custom' {
			
			# Use whatever is already in 'editor' plus some sane defaults
			$conf->{editor} = { 

				# These can be overridden
				header			=> $conf->{header},
				win_title		=> 'Select ' . $conf->{header},
				win_height		=> 450,
				win_width		=> 650,
				valueField		=> $conf->{valueField},
				displayField	=> $conf->{displayField},
				name			=> $colname,
				
				%{$conf->{auto_editor_params}},
				%{$conf->{editor}},
			};
		}
	}
	############# ---
	
	return (name => $colname, %$conf);
}


sub get_multi_relationship_column_cnf {
	my $self = shift;
	my $rel = shift;
	my %opt = (ref($_[0]) eq 'HASH') ? %{ $_[0] } : @_; # <-- arg as hash or hashref
	
	my $conf = \%opt;
	
	#$conf->{no_multifilter} = \1;
	$conf->{multifilter_type} = 'number';
	
	$conf->{no_quick_search} = \1;
	$conf->{no_summary} = \1;
	
	$conf->{editor} = '';
	
	my $rel_data = clone($conf->{relationship_cond_data});
	
	## -- allow override of the associated TabsleSpec cnfs from the relationship attrs:
	$conf->{title_multi} = delete $rel_data->{attrs}->{title_multi} if ($rel_data->{attrs}->{title_multi});
	$conf->{multiIconCls} = delete $rel_data->{attrs}->{multiIconCls} if ($rel_data->{attrs}->{multiIconCls});
	$conf->{open_url_multi} = delete $rel_data->{attrs}->{open_url_multi} if ($rel_data->{attrs}->{open_url_multi});
	$conf->{open_url_multi_rs_join_name} = delete $rel_data->{attrs}->{open_url_multi_rs_join_name} if ($rel_data->{attrs}->{open_url_multi_rs_join_name});
	delete $rel_data->{attrs}->{cascade_copy};
	delete $rel_data->{attrs}->{cascade_delete};
	delete $rel_data->{attrs}->{join_type};
	delete $rel_data->{attrs}->{accessor};
	
	$rel_data->{attrs}->{join} = [ $rel_data->{attrs}->{join} ] if (
		defined $rel_data->{attrs}->{join} and
		ref($rel_data->{attrs}->{join}) ne 'ARRAY'
	);
	
	if($rel_data->{attrs}->{join}) {
		@{$rel_data->{attrs}->{join}} = grep { $_ ne $conf->{open_url_multi_rs_join_name} } @{$rel_data->{attrs}->{join}};
		delete $rel_data->{attrs}->{join} unless (scalar @{$rel_data->{attrs}->{join}} > 0);
	}
	
	
	my $title = $conf->{title_multi} ? $conf->{title_multi} : 'Related "' . $rel . '" Rows';
	
	my $loadCfg = {
		title => $title,
		iconCls => $conf->{multiIconCls} ,
		autoLoad => {
			url => $conf->{open_url_multi},
			params => {}
		}
	};
	
	my $div_open = 
		'<div' . 
		( $conf->{multiIconCls} ? ' class="with-icon ' . $conf->{multiIconCls} . '"' : '' ) . '><span>' .
		$title .
		'&nbsp;<span class="superscript-navy">';
	
	#scream($conf->{relationship_cond_data});
	
	#my $attrs = {};
	#$attrs->{join} = $conf->{relationship_cond_data}->{attrs}->{join} if ($conf->{relationship_cond_data}->{attrs}->{join});
	
	
	
	$conf->{renderer} = jsfunc(
		'function(value, metaData, record, rowIndex, colIndex, store) {' .
			"var div_open = '$div_open';" .
			"var disp = div_open + value + '</span>';" .
			
			#'var key_key = ' .
			'var key_val = record.data["' . $self->column_prefix . $rel_data->{self} . '"];' .
			
			'var attr = ' . JSON::PP::encode_json($rel_data->{attrs}) . ';' .
			
			( # TODO: needs to be generalized better
				$conf->{open_url_multi} ?
					'if(key_val && value && value > 0) {' .
						'var loadCfg = ' . JSON::PP::encode_json($loadCfg) . ';' .
						
						'var join_name = "' . $conf->{open_url_multi_rs_join_name} . '";' .
						
						'var cond = {};' .
						'cond[join_name + ".' . $rel_data->{foreign} . '"] = key_val;' .
						
						#'var attr = {};' .
						'if(join_name != "me"){ if(!attr.join) { attr.join = []; } attr.join.push(join_name); }' .
						
						# Fix!!!
						'if(join_name == "me" && Ext.isArray(attr.join) && attr.join.length > 0) { join_name = attr.join[0]; }' .
						
						#Fix!!
						'loadCfg.autoLoad.params.personality = join_name;' .
						
						'loadCfg.autoLoad.params.base_params = Ext.encode({' .
							'resultset_condition: Ext.encode(cond),' .
							'resultset_attr: Ext.encode(attr)' .
						'});' .
						
						'var href = "#loadcfg:" + Ext.urlEncode({data: Ext.encode(loadCfg)});' .
						'disp += "&nbsp;" + Ext.ux.RapidApp.inlineLink(' .
							'href,"<span>open</span>","magnify-link-tiny",null,"Open/view: " + loadCfg.title' .
						');' .
					'}'
				:
					''
			) .
			"disp += '</span></div>';" .
			'return disp;' .
		'}', $conf->{renderer}
	);
	
	

	$conf->{name} = $self->column_prefix . $rel;
	
	return %$conf;
}


sub get_or_create_rapidapp_module {
	my $self = shift;
	my $name = shift or die "get_or_create_rapidapp_module(): Missing module name";
	my %opt = (ref($_[0]) eq 'HASH') ? %{ $_[0] } : @_; # <-- arg as hash or hashref

	my $rootModule = RapidApp::ScopedGlobals->get("rootModule") or die "Failed to find RapidApp Root Module!!";
	
	$rootModule->apply_init_modules( tablespec => 'RapidApp::AppBase' ) 
		unless ( $rootModule->has_module('tablespec') );
	
	my $TMod = $rootModule->Module('tablespec');
	
	$TMod->apply_init_modules( $name => \%opt ) unless ( $TMod->has_module($name) );
	
	my $Module = $TMod->Module($name);
	$Module->call_ONREQUEST_handlers;
	$Module->DataStore->call_ONREQUEST_handlers;
	
	return $Module;
}

1;